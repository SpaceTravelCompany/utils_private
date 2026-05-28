package sfl_allocator

import "core:mem"
import virtual "core:mem/virtual"
import "core:testing"

// ============================================================
// Segregated Free List Allocator (performance build)
//
// - Single-threaded, no locks
// - No magic / debug validation on hot paths
// - Small: class 0..NUM_CLASSES-1, free-list + segment bump
// - Large: class == LARGE_CLASS (NUM_CLASSES), separate virtual mapping
// ============================================================

ALIGNMENT: uintptr : 16
MIN_SIZE: uintptr : 16
TINY_MAX_SIZE: uintptr : 256
SMALL_MAX_SIZE: uintptr : 4096
MAX_SLAB_SIZE: uintptr : 64 * mem.Kilobyte
SEGMENT_SIZE: uintptr : 8 * mem.Megabyte

TINY_CLASS_STEP: uintptr : 16
SMALL_CLASS_STEP: uintptr : 256
MEDIUM_CLASS_STEP: uintptr : 4 * mem.Kilobyte

TINY_CLASS_COUNT :: TINY_MAX_SIZE / TINY_CLASS_STEP
SMALL_CLASS_COUNT :: 16
MEDIUM_CLASS_COUNT :: 16
NUM_CLASSES :: TINY_CLASS_COUNT + SMALL_CLASS_COUNT + MEDIUM_CLASS_COUNT
LARGE_CLASS :: u16(NUM_CLASSES)

@(private)
Allocation_Header :: struct {
	class:         u16,
	_pad:          u16,
	raw_base:      rawptr,
	reserved_size: uintptr,
}

@(private)
HEADER_SIZE: uintptr : ((size_of(Allocation_Header) + ALIGNMENT - 1) / ALIGNMENT) * ALIGNMENT

@(private)
Node :: struct {
	next: ^Node,
}

@(private)
Segment :: struct {
	next:          ^Segment,
	size:          uintptr,
	cursor:        uintptr,
	payload_start: uintptr,
	payload_limit: uintptr,
}

SFL :: struct {
	free_lists: [NUM_CLASSES]^Node,
	seg_head:   ^Segment,
	seg_size:   uintptr,
}

// ============================================================
// Helpers
// ============================================================

@(private)
align_up :: #force_inline proc(x, alignment: uintptr) -> uintptr {
	return mem.align_forward_uintptr(x, alignment)
}

@(private)
size_to_class :: #force_inline proc "contextless" (size: uintptr) -> uintptr {
	if size < TINY_MAX_SIZE {
		return ((size + TINY_CLASS_STEP - 1) / TINY_CLASS_STEP) - 1
	}
	if size < SMALL_MAX_SIZE {
		return(
			TINY_CLASS_COUNT +
			((size - TINY_MAX_SIZE + SMALL_CLASS_STEP - 1) / SMALL_CLASS_STEP) \
		)
	}
	return(
		TINY_CLASS_COUNT +
		SMALL_CLASS_COUNT +
		((size - SMALL_MAX_SIZE + MEDIUM_CLASS_STEP - 1) / MEDIUM_CLASS_STEP) \
	)
}

@(private)
class_to_size :: #force_inline proc "contextless" (class: uintptr) -> uintptr {
	if class < TINY_CLASS_COUNT {
		return (class + 1) * TINY_CLASS_STEP
	}
	if class < TINY_CLASS_COUNT + SMALL_CLASS_COUNT {
		return TINY_MAX_SIZE + (class - TINY_CLASS_COUNT) * SMALL_CLASS_STEP
	}
	return SMALL_MAX_SIZE + (class - TINY_CLASS_COUNT - SMALL_CLASS_COUNT) * MEDIUM_CLASS_STEP
}

@(private)
ptr_header :: #force_inline proc "contextless" (ptr: rawptr) -> ^Allocation_Header {
	return (^Allocation_Header)(uintptr(ptr) - HEADER_SIZE)
}

@(private)
slot_base :: #force_inline proc "contextless" (ptr: rawptr) -> rawptr {
	return rawptr(uintptr(ptr) - HEADER_SIZE)
}

@(private)
segment_init_payload_bounds :: #force_inline proc(seg: ^Segment) {
	seg.payload_start = mem.align_forward_uintptr(uintptr(seg) + size_of(Segment), ALIGNMENT)
	seg.payload_limit = uintptr(seg) + seg.size
}

@(private)
os_alloc :: proc(size: uintptr) -> rawptr {
	aligned_size := align_up(size, uintptr(virtual.DEFAULT_PAGE_SIZE))
	data, err := virtual.reserve_and_commit(uint(aligned_size))
	if err != nil {
		return nil
	}
	return raw_data(data)
}

@(private)
os_free :: #force_inline proc(raw: rawptr, size: uintptr) {
	virtual.release(raw, uint(align_up(size, uintptr(virtual.DEFAULT_PAGE_SIZE))))
}

@(private)
seg_bump_alloc :: #force_inline proc(seg: ^Segment, block_size: uintptr) -> rawptr {
	cursor := align_up(seg.cursor, ALIGNMENT)
	end := cursor + block_size
	if end > seg.payload_limit - seg.payload_start {
		return nil
	}
	base := rawptr(seg.payload_start + cursor)
	seg.cursor = end
	return base
}

@(private)
new_segment :: proc(g: ^SFL, min_block: uintptr) -> ^Segment {
	seg_size := g.seg_size
	if seg_size == 0 {
		seg_size = SEGMENT_SIZE
	}

	needed := min_block + size_of(Segment) + ALIGNMENT
	for seg_size < needed {
		seg_size *= 2
	}
	seg_size = align_up(seg_size, uintptr(virtual.DEFAULT_PAGE_SIZE))

	raw := os_alloc(seg_size)
	if raw == nil {
		return nil
	}

	seg := (^Segment)(raw)
	seg.next = g.seg_head
	seg.size = seg_size
	seg.cursor = 0
	segment_init_payload_bounds(seg)
	g.seg_head = seg
	return seg
}

@(private)
free_segment :: proc(seg: ^Segment) {
	os_free(rawptr(seg), seg.size)
}

@(private)
write_small_header :: #force_inline proc(ptr: rawptr, class: u16) {
	ptr_header(ptr).class = class
}

@(private)
write_large_header :: #force_inline proc(ptr: rawptr, raw: rawptr, reserved: uintptr) {
	h := ptr_header(ptr)
	h.class = LARGE_CLASS
	h.raw_base = raw
	h.reserved_size = reserved
}

@(private)
alloc_small :: proc(g: ^SFL, size: uintptr) -> rawptr {
	class := size_to_class(max(size, MIN_SIZE))
	block_size := HEADER_SIZE + class_to_size(class)

	head := g.free_lists[class]
	base: rawptr
	if head != nil {
		g.free_lists[class] = head.next
		base = rawptr(head)
	} else {
		base = seg_bump_alloc(g.seg_head, block_size)
		if base == nil {
			if new_segment(g, block_size) == nil {
				return nil
			}
			base = seg_bump_alloc(g.seg_head, block_size)
		}
	}

	if base == nil {
		return nil
	}

	ptr := rawptr(uintptr(base) + HEADER_SIZE)
	write_small_header(ptr, u16(class))
	return ptr
}

@(private)
alloc_large :: proc(size, alignment: uintptr) -> rawptr {
	requested_alignment := max(alignment, ALIGNMENT)
	total := HEADER_SIZE + size + requested_alignment - 1
	reserved_size := align_up(total, uintptr(virtual.DEFAULT_PAGE_SIZE))
	raw := os_alloc(reserved_size)
	if raw == nil {
		return nil
	}

	ptr := rawptr(mem.align_forward_uintptr(uintptr(raw) + HEADER_SIZE, requested_alignment))
	write_large_header(ptr, raw, reserved_size)
	return ptr
}

// ============================================================
// Public API
// ============================================================

init :: proc(g: ^SFL, segment_size: uintptr = SEGMENT_SIZE) -> bool {
	g^ = {}
	g.seg_size = align_up(max(segment_size, 4096), uintptr(virtual.DEFAULT_PAGE_SIZE))
	return new_segment(g, 0) != nil
}

destroy :: proc(g: ^SFL) {
	for seg := g.seg_head; seg != nil; {
		next := seg.next
		free_segment(seg)
		seg = next
	}
	g^ = {}
}

alloc :: #force_inline proc(g: ^SFL, size: uintptr, alignment: uintptr = ALIGNMENT) -> rawptr {
	if alignment <= ALIGNMENT && size <= MAX_SLAB_SIZE {
		return alloc_small(g, size)
	}
	return alloc_large(size, alignment)
}

free :: #force_inline proc(g: ^SFL, ptr: rawptr) {
	h := ptr_header(ptr)
	if h.class >= LARGE_CLASS {
		os_free(h.raw_base, h.reserved_size)
		return
	}
	class := int(h.class)
	node := (^Node)(slot_base(ptr))
	node.next = g.free_lists[class]
	g.free_lists[class] = node
}

resize :: proc(
	g: ^SFL,
	ptr: rawptr,
	old_size, new_size: uintptr,
	alignment: uintptr = ALIGNMENT,
) -> rawptr {
	if ptr == nil {
		return alloc(g, new_size, alignment)
	}
	if new_size == 0 {
		free(g, ptr)
		return nil
	}

	h := ptr_header(ptr)
	if h.class >= LARGE_CLASS {
		if new_size <= h.reserved_size - HEADER_SIZE {
			return ptr
		}
	} else if alignment <= ALIGNMENT {
		if new_size <= class_to_size(uintptr(h.class)) {
			return ptr
		}
	}

	new_ptr := alloc(g, new_size, alignment)
	if new_ptr == nil {
		return nil
	}

	copy_size := min(old_size, new_size)
	if new_ptr != ptr && copy_size > 0 {
		mem.copy_non_overlapping(new_ptr, ptr, int(copy_size))
	}
	free(g, ptr)
	return new_ptr
}

// ============================================================
// Odin Allocator Interface
// ============================================================

allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	g := (^SFL)(allocator_data)

	#partial switch mode {
	case .Alloc:
		ptr := alloc(g, uintptr(size), uintptr(alignment))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		mem.zero(ptr, size)
		return mem.byte_slice(ptr, size), nil

	case .Alloc_Non_Zeroed:
		ptr := alloc(g, uintptr(size), uintptr(alignment))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		return mem.byte_slice(ptr, size), nil

	case .Free:
		if old_memory != nil {
			free(g, old_memory)
		}

	case .Free_All:
		seg_size := g.seg_size
		destroy(g)
		init(g, seg_size)

	case .Resize, .Resize_Non_Zeroed:
		ptr := resize(g, old_memory, uintptr(old_size), uintptr(size), uintptr(alignment))
		if ptr == nil && size > 0 {
			return nil, .Out_Of_Memory
		}
		if mode == .Resize && ptr != nil && size > old_size {
			mem.zero(rawptr(uintptr(ptr) + uintptr(old_size)), size - old_size)
		}
		return mem.byte_slice(ptr, size), nil

	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
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
	return {procedure = allocator_proc, data = g}
}

// ============================================================
// Tests
// ============================================================

@(test)
test_class_mapping :: proc(t: ^testing.T) {
	testing.expect_value(t, NUM_CLASSES, 48)
	testing.expect_value(t, size_to_class(1), 0)
	testing.expect_value(t, size_to_class(16), 0)
	testing.expect_value(t, size_to_class(17), 1)
	testing.expect_value(t, size_to_class(255), 15)
	testing.expect_value(t, size_to_class(256), 16)
	testing.expect_value(t, size_to_class(257), 17)
	testing.expect_value(t, size_to_class(4095), 31)
	testing.expect_value(t, size_to_class(4096), 32)
	testing.expect_value(t, size_to_class(4097), 33)
	testing.expect_value(t, size_to_class(64 * mem.Kilobyte), 47)

	testing.expect_value(t, class_to_size(0), 16)
	testing.expect_value(t, class_to_size(15), 256)
	testing.expect_value(t, class_to_size(16), 256)
	testing.expect_value(t, class_to_size(17), 512)
	testing.expect_value(t, class_to_size(31), 4096)
	testing.expect_value(t, class_to_size(32), 4096)
	testing.expect_value(t, class_to_size(33), 8192)
	testing.expect_value(t, class_to_size(47), 64 * mem.Kilobyte)
}

@(test)
test_small_alloc_free_reuse :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	a := alloc(&g, 32)
	b := alloc(&g, 32)
	testing.expect(t, a != nil)
	testing.expect(t, b != nil)
	testing.expect(t, uintptr(a) % ALIGNMENT == 0)
	free(&g, a)
	c := alloc(&g, 32)
	testing.expect_value(t, c, a)
	free(&g, b)
	free(&g, c)
}

@(test)
test_large_alloc_individual_free :: proc(t: ^testing.T) {
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
test_overaligned_uses_large_path :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	p := alloc(&g, 64, 256)
	testing.expect(t, p != nil)
	testing.expect(t, uintptr(p) % 256 == 0)
	free(&g, p)
}

@(test)
test_allocator_interface :: proc(t: ^testing.T) {
	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	old_allocator := context.allocator
	context.allocator = allocator(&g)
	defer context.allocator = old_allocator

	data := make([]byte, 128)
	testing.expect(t, len(data) == 128)
	for b in data {
		testing.expect_value(t, b, byte(0))
	}

	for i in 0 ..< len(data) {
		data[i] = byte(i)
	}

	new_data, resize_err := mem.resize(
		raw_data(data),
		len(data),
		4096,
		align_of(byte),
		context.allocator,
	)
	testing.expect_value(t, resize_err, nil)
	data = mem.byte_slice(new_data, 4096)
	for i in 0 ..< 128 {
		testing.expect_value(t, data[i], byte(i))
	}
	for i in 128 ..< 4096 {
		testing.expect_value(t, data[i], byte(0))
	}
	delete(data)
}

@(test)
test_dynamic_array_append :: proc(t: ^testing.T) {
	Scene_Entry :: struct {
		vtable: rawptr,
		imp:    rawptr,
	}

	g: SFL
	testing.expect(t, init(&g, 4096))
	defer destroy(&g)

	old_allocator := context.allocator
	context.allocator = allocator(&g)
	defer context.allocator = old_allocator

	scene, err := make([dynamic]Scene_Entry)
	testing.expect_value(t, err, nil)
	defer delete(scene)

	for i in 0 ..< 64 {
		_, append_err := append(&scene, Scene_Entry{})
		testing.expectf(t, append_err == nil, "append failed at %v", i)
	}
	testing.expect_value(t, len(scene), 64)
}

@(test)
test_stress :: proc(t: ^testing.T) {
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
	next_rand :: proc(state: ^uintptr) -> uintptr {
		state^ = state^ * 1664525 + 1013904223
		return state^
	}

	for step in 0 ..< 20000 {
		idx := int(next_rand(&state) % len(slots))
		if slots[idx].ptr != nil && (next_rand(&state) & 3) != 0 {
			free(&g, slots[idx].ptr)
			slots[idx] = {}
			continue
		}

		size := (next_rand(&state) % (96 * 1024)) + 1
		alignment := ALIGNMENT
		if (next_rand(&state) & 15) == 0 {
			alignment = ALIGNMENT << (next_rand(&state) % 5)
		}

		if slots[idx].ptr != nil {
			new_ptr := resize(&g, slots[idx].ptr, slots[idx].size, size, slots[idx].align)
			testing.expectf(t, new_ptr != nil, "resize failed at step %v", step)
			testing.expect(t, uintptr(new_ptr) % slots[idx].align == 0)
			slots[idx] = Slot{new_ptr, size, slots[idx].align}
		} else {
			ptr := alloc(&g, size, alignment)
			testing.expectf(t, ptr != nil, "alloc failed at step %v", step)
			testing.expect(t, uintptr(ptr) % alignment == 0)
			mem.set(ptr, byte(idx), int(size))
			slots[idx] = Slot{ptr, size, alignment}
		}
	}

	for slot in slots {
		if slot.ptr != nil {
			free(&g, slot.ptr)
		}
	}
}
