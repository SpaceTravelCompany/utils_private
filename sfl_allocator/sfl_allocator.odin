package sfl_allocator

import "core:mem"
import virtual "core:mem/virtual"
import "core:testing"

// ============================================================
// Segregated Free List Allocator (performance build)
//
// - Single-threaded, no locks
// - No magic / debug validation on hot paths
// - Small: class 0..NumClasses-1, free-list + segment bump
// - Large: class == LargeClass (NumClasses), separate virtual mapping
// ============================================================

alignment: uintptr : 16
minSize: uintptr : 16
tinyMaxSize: uintptr : 256
smallMaxSize: uintptr : 4096
maxSlabSize: uintptr : 64 * mem.Kilobyte
segmentSize: uintptr : 8 * mem.Megabyte

tinyClassStep: uintptr : 16
smallClassStep: uintptr : 256
mediumClassStep: uintptr : 4 * mem.Kilobyte

TinyClassCount :: tinyMaxSize / tinyClassStep
SmallClassCount :: 16
MediumClassCount :: 16
NumClasses :: TinyClassCount + SmallClassCount + MediumClassCount
LargeClass :: u16(NumClasses)

@(private)
AllocationHeader :: struct {
	class:         u16,
	_pad:          u16,
	rawBase:      rawptr,
	reservedSize: uintptr,
}

@(private)
headerSize: uintptr : ((size_of(AllocationHeader) + alignment - 1) / alignment) * alignment

@(private)
Node :: struct {
	next: ^Node,
}

@(private)
Segment :: struct {
	next:          ^Segment,
	size:          uintptr,
	cursor:        uintptr,
	payloadStart: uintptr,
	payloadLimit: uintptr,
}

SFL :: struct {
	freeLists: [NumClasses]^Node,
	segHead:   ^Segment,
	segSize:   uintptr,
}

// ============================================================
// Helpers
// ============================================================

@(private)
alignUp :: #force_inline proc(x, algn: uintptr) -> uintptr {
	return mem.align_forward_uintptr(x, algn)
}

@(private)
sizeToClass :: #force_inline proc "contextless" (size: uintptr) -> uintptr {
	if size < tinyMaxSize {
		return ((size + tinyClassStep - 1) / tinyClassStep) - 1
	}
	if size < smallMaxSize {
		return(
			TinyClassCount +
			((size - tinyMaxSize + smallClassStep - 1) / smallClassStep) \
		)
	}
	return(
		TinyClassCount +
		SmallClassCount +
		((size - smallMaxSize + mediumClassStep - 1) / mediumClassStep) \
	)
}

@(private)
classToSize :: #force_inline proc "contextless" (class: uintptr) -> uintptr {
	if class < TinyClassCount {
		return (class + 1) * tinyClassStep
	}
	if class < TinyClassCount + SmallClassCount {
		return tinyMaxSize + (class - TinyClassCount) * smallClassStep
	}
	return smallMaxSize + (class - TinyClassCount - SmallClassCount) * mediumClassStep
}

@(private)
ptrHeader :: #force_inline proc "contextless" (ptr: rawptr) -> ^AllocationHeader {
	return (^AllocationHeader)(uintptr(ptr) - headerSize)
}

@(private)
slotBase :: #force_inline proc "contextless" (ptr: rawptr) -> rawptr {
	return rawptr(uintptr(ptr) - headerSize)
}

@(private)
segmentInitPayloadBounds :: #force_inline proc(seg: ^Segment) {
	seg.payloadStart = mem.align_forward_uintptr(uintptr(seg) + size_of(Segment), alignment)
	seg.payloadLimit = uintptr(seg) + seg.size
}

@(private)
osAlloc :: proc(size: uintptr) -> rawptr {
	alignedSize := alignUp(size, uintptr(virtual.DEFAULT_PAGE_SIZE))
	data, err := virtual.reserve_and_commit(uint(alignedSize))
	if err != nil {
		return nil
	}
	return raw_data(data)
}

@(private)
osFree :: #force_inline proc(raw: rawptr, size: uintptr) {
	virtual.release(raw, uint(alignUp(size, uintptr(virtual.DEFAULT_PAGE_SIZE))))
}

@(private)
segBumpAlloc :: #force_inline proc(seg: ^Segment, blockSize: uintptr) -> rawptr {
	cursor := alignUp(seg.cursor, alignment)
	end := cursor + blockSize
	if end > seg.payloadLimit - seg.payloadStart {
		return nil
	}
	base := rawptr(seg.payloadStart + cursor)
	seg.cursor = end
	return base
}

@(private)
newSegment :: proc(g: ^SFL, minBlock: uintptr) -> ^Segment {
	segSz := g.segSize
	if segSz == 0 {
		segSz = segmentSize
	}

	needed := minBlock + size_of(Segment) + alignment
	for segSz < needed {
		segSz *= 2
	}
	segSz = alignUp(segSz, uintptr(virtual.DEFAULT_PAGE_SIZE))

	raw := osAlloc(segSz)
	if raw == nil {
		return nil
	}

	seg := (^Segment)(raw)
	seg.next = g.segHead
	seg.size = segSz
	seg.cursor = 0
	segmentInitPayloadBounds(seg)
	g.segHead = seg
	return seg
}

@(private)
freeSegment :: proc(seg: ^Segment) {
	osFree(rawptr(seg), seg.size)
}

@(private)
writeSmallHeader :: #force_inline proc(ptr: rawptr, class: u16) {
	ptrHeader(ptr).class = class
}

@(private)
writeLargeHeader :: #force_inline proc(ptr: rawptr, raw: rawptr, reserved: uintptr) {
	h := ptrHeader(ptr)
	h.class = LargeClass
	h.rawBase = raw
	h.reservedSize = reserved
}

@(private)
allocSmall :: proc(g: ^SFL, size: uintptr) -> rawptr {
	class := sizeToClass(max(size, minSize))
	blockSize := headerSize + classToSize(class)

	head := g.freeLists[class]
	base: rawptr
	if head != nil {
		g.freeLists[class] = head.next
		base = rawptr(head)
	} else {
		base = segBumpAlloc(g.segHead, blockSize)
		if base == nil {
			if newSegment(g, blockSize) == nil {
				return nil
			}
			base = segBumpAlloc(g.segHead, blockSize)
		}
	}

	if base == nil {
		return nil
	}

	ptr := rawptr(uintptr(base) + headerSize)
	writeSmallHeader(ptr, u16(class))
	return ptr
}

@(private)
allocLarge :: proc(size, algn: uintptr) -> rawptr {
	requestedAlignment := max(algn, alignment)
	total := headerSize + size + requestedAlignment - 1
	reservedSize := alignUp(total, uintptr(virtual.DEFAULT_PAGE_SIZE))
	raw := osAlloc(reservedSize)
	if raw == nil {
		return nil
	}

	ptr := rawptr(mem.align_forward_uintptr(uintptr(raw) + headerSize, requestedAlignment))
	writeLargeHeader(ptr, raw, reservedSize)
	return ptr
}

// ============================================================
// Public API
// ============================================================

init :: proc(g: ^SFL, segSz: uintptr = segmentSize) -> bool {
	g^ = {}
	g.segSize = alignUp(max(segSz, 4096), uintptr(virtual.DEFAULT_PAGE_SIZE))
	return newSegment(g, 0) != nil
}

destroy :: proc(g: ^SFL) {
	for seg := g.segHead; seg != nil; {
		next := seg.next
		freeSegment(seg)
		seg = next
	}
	g^ = {}
}

alloc :: #force_inline proc(g: ^SFL, size: uintptr, algn: uintptr = alignment) -> rawptr {
	if algn <= alignment && size <= maxSlabSize {
		return allocSmall(g, size)
	}
	return allocLarge(size, algn)
}

free :: #force_inline proc(g: ^SFL, ptr: rawptr) {
	h := ptrHeader(ptr)
	if h.class >= LargeClass {
		osFree(h.rawBase, h.reservedSize)
		return
	}
	class := int(h.class)
	node := (^Node)(slotBase(ptr))
	node.next = g.freeLists[class]
	g.freeLists[class] = node
}

resize :: proc(
	g: ^SFL,
	ptr: rawptr,
	oldSize, newSize: uintptr,
	algn: uintptr = alignment,
) -> rawptr {
	if ptr == nil {
		return alloc(g, newSize, algn)
	}
	if newSize == 0 {
		free(g, ptr)
		return nil
	}

	h := ptrHeader(ptr)
	if h.class >= LargeClass {
		if newSize <= h.reservedSize - headerSize {
			return ptr
		}
	} else if algn <= alignment {
		if newSize <= classToSize(uintptr(h.class)) {
			return ptr
		}
	}

	newPtr := alloc(g, newSize, algn)
	if newPtr == nil {
		return nil
	}

	copySize := min(oldSize, newSize)
	if newPtr != ptr && copySize > 0 {
		mem.copy_non_overlapping(newPtr, ptr, int(copySize))
	}
	free(g, ptr)
	return newPtr
}

// ============================================================
// Odin Allocator Interface
// ============================================================

allocatorProc :: proc(
	allocatorData: rawptr,
	mode: mem.Allocator_Mode,
	size, algn: int,
	oldMemory: rawptr,
	oldSize: int,
	loc := #caller_location,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	g := (^SFL)(allocatorData)

	#partial switch mode {
	case .Alloc:
		ptr := alloc(g, uintptr(size), uintptr(algn))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		mem.zero(ptr, size)
		return mem.byte_slice(ptr, size), nil

	case .Alloc_Non_Zeroed:
		ptr := alloc(g, uintptr(size), uintptr(algn))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		return mem.byte_slice(ptr, size), nil

	case .Free:
		if oldMemory != nil {
			free(g, oldMemory)
		}

	case .Free_All:
		segSz := g.segSize
		destroy(g)
		init(g, segSz)

	case .Resize, .Resize_Non_Zeroed:
		ptr := resize(g, oldMemory, uintptr(oldSize), uintptr(size), uintptr(algn))
		if ptr == nil && size > 0 {
			return nil, .Out_Of_Memory
		}
		if mode == .Resize && ptr != nil && size > oldSize {
			mem.zero(rawptr(uintptr(ptr) + uintptr(oldSize)), size - oldSize)
		}
		return mem.byte_slice(ptr, size), nil

	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(oldMemory)
		if set != nil {
			set^ = {
				.Alloc,
				.Alloc_Non_Zeroed,
				.Free,
				.Free_All,
				.Resize,
				.Resize_Non_Zeroed,
				.Query_Features,
			}
		}

	case .Query_Info:
	}

	return nil, nil
}

allocator :: #force_inline proc(g: ^SFL) -> mem.Allocator {
	return {procedure = allocatorProc, data = g}
}

// ============================================================
// Tests
// ============================================================

@(test)
testClassMapping :: proc(t: ^testing.T) {
	testing.expect_value(t, NumClasses, 48)
	testing.expect_value(t, sizeToClass(1), 0)
	testing.expect_value(t, sizeToClass(16), 0)
	testing.expect_value(t, sizeToClass(17), 1)
	testing.expect_value(t, sizeToClass(255), 15)
	testing.expect_value(t, sizeToClass(256), 16)
	testing.expect_value(t, sizeToClass(257), 17)
	testing.expect_value(t, sizeToClass(4095), 31)
	testing.expect_value(t, sizeToClass(4096), 32)
	testing.expect_value(t, sizeToClass(4097), 33)
	testing.expect_value(t, sizeToClass(64 * mem.Kilobyte), 47)

	testing.expect_value(t, classToSize(0), 16)
	testing.expect_value(t, classToSize(15), 256)
	testing.expect_value(t, classToSize(16), 256)
	testing.expect_value(t, classToSize(17), 512)
	testing.expect_value(t, classToSize(31), 4096)
	testing.expect_value(t, classToSize(32), 4096)
	testing.expect_value(t, classToSize(33), 8192)
	testing.expect_value(t, classToSize(47), 64 * mem.Kilobyte)
}

@(test)
testSmallAllocFreeReuse :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	a := alloc(&g, 32)
	b := alloc(&g, 32)
	testing.expect(t, a != nil)
	testing.expect(t, b != nil)
	testing.expect(t, uintptr(a) % alignment == 0)
	free(&g, a)
	c := alloc(&g, 32)
	testing.expect_value(t, c, a)
	free(&g, b)
	free(&g, c)
}

@(test)
testLargeAllocIndividualFree :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	big := alloc(&g, 64 * mem.Kilobyte + 1)
	testing.expect(t, big != nil)
	mem.set(big, 0xab, int(64 * mem.Kilobyte + 1))
	free(&g, big)

	bigger := alloc(&g, 2 * mem.Megabyte)
	testing.expect(t, bigger != nil)
	mem.set(bigger, 0xcd, int(2 * mem.Megabyte))
	free(&g, bigger)
}

@(test)
testOveralignedUsesLargePath :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	p := alloc(&g, 64, 256)
	testing.expect(t, p != nil)
	testing.expect(t, uintptr(p) % 256 == 0)
	free(&g, p)
}

@(test)
testAllocatorInterface :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	oldAllocator := context.allocator
	context.allocator = allocator(&g)
	defer context.allocator = oldAllocator

	data := make([]byte, 128)
	testing.expect(t, len(data) == 128)
	for b in data {
		testing.expect_value(t, b, byte(0))
	}

	for i in 0 ..< len(data) {
		data[i] = byte(i)
	}

	newData, resizeErr := mem.resize(
		raw_data(data),
		len(data),
		4096,
		align_of(byte),
		context.allocator,
	)
	testing.expect_value(t, resizeErr, nil)
	data = mem.byte_slice(newData, 4096)
	for i in 0 ..< 128 {
		testing.expect_value(t, data[i], byte(i))
	}
	for i in 128 ..< 4096 {
		testing.expect_value(t, data[i], byte(0))
	}
	delete(data)
}

@(test)
testDynamicArrayAppend :: proc(t: ^testing.T) {
	SceneEntry :: struct {
		vtable: rawptr,
		imp:    rawptr,
	}

	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	oldAllocator := context.allocator
	context.allocator = allocator(&g)
	defer context.allocator = oldAllocator

	scene, err := make([dynamic]SceneEntry)
	testing.expect_value(t, err, nil)
	defer delete(scene)

	for i in 0 ..< 64 {
		_, appendErr := append(&scene, SceneEntry{})
		testing.expectf(t, appendErr == nil, "append failed at %v", i)
	}
	testing.expect_value(t, len(scene), 64)
}

@(test)
testStress :: proc(t: ^testing.T) {
	Slot :: struct {
		ptr:   rawptr,
		size:  uintptr,
		align: uintptr,
	}

	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	slots: [256]Slot
	state: uintptr = 0x1234_5678
	nextRand :: proc(state: ^uintptr) -> uintptr {
		state^ = state^ * 1664525 + 1013904223
		return state^
	}

	for step in 0 ..< 20000 {
		idx := int(nextRand(&state) % len(slots))
		if slots[idx].ptr != nil && (nextRand(&state) & 3) != 0 {
			free(&g, slots[idx].ptr)
			slots[idx] = {}
			continue
		}

		size := (nextRand(&state) % (96 * 1024)) + 1
		algn := alignment
		if (nextRand(&state) & 15) == 0 {
			algn = alignment << (nextRand(&state) % 5)
		}

		if slots[idx].ptr != nil {
			newPtr := resize(&g, slots[idx].ptr, slots[idx].size, size, slots[idx].align)
			testing.expectf(t, newPtr != nil, "resize failed at step %v", step)
			testing.expect(t, uintptr(newPtr) % slots[idx].align == 0)
			slots[idx] = Slot{newPtr, size, slots[idx].align}
		} else {
			ptr := alloc(&g, size, algn)
			testing.expectf(t, ptr != nil, "alloc failed at step %v", step)
			testing.expect(t, uintptr(ptr) % algn == 0)
			mem.set(ptr, byte(idx), int(size))
			slots[idx] = Slot{ptr, size, algn}
		}
	}

	for slot in slots {
		if slot.ptr != nil {
			free(&g, slot.ptr)
		}
	}
}
