package utils_private

import "base:intrinsics"
import "base:runtime"
import "core:math"

import "core:math/linalg"
import "core:mem"


import "core:math/fixed"

make_non_zeroed_slice :: #force_inline proc(
	$T: typeid/[]$E,
	#any_int len: int,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	res: T,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	runtime.make_slice_error_loc(loc, len)
	data: []byte
	data, err = runtime.mem_alloc_non_zeroed(size_of(E) * len, align_of(E), allocator, loc)
	if data == nil && size_of(E) != 0 {
		return nil, err
	}
	(^runtime.Raw_Slice)(&res).data = raw_data(data)
	(^runtime.Raw_Slice)(&res).len = len
	return
}

make_non_zeroed_dynamic_array_len_cap :: #force_inline proc(
	$T: typeid/[dynamic]$E,
	#any_int len, cap: int,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	res: T,
	err: runtime.Allocator_Error,
) #optional_allocator_error {
	runtime.make_dynamic_array_error_loc(loc, len, cap)
	array := (^runtime.Raw_Dynamic_Array)(&res)
	array.allocator = allocator // initialize allocator before just in case it fails to allocate any memory
	data := runtime.mem_alloc_non_zeroed(size_of(E) * cap, align_of(E), allocator, loc) or_return
	use_zero := data == nil && size_of(E) != 0
	array.data = raw_data(data)
	array.len = 0 if use_zero else len
	array.cap = 0 if use_zero else cap
	return
}

non_zero_resize_dynamic_array :: proc(
	array: ^$T/[dynamic]$E,
	#any_int length: int,
	loc := #caller_location,
) -> runtime.Allocator_Error {
	return runtime._resize_dynamic_array(
		(^runtime.Raw_Dynamic_Array)(array),
		size_of(E),
		align_of(E),
		length,
		false,
		loc = loc,
	)
}

_resize_slice :: #force_no_inline proc(
	a: ^runtime.Raw_Slice,
	size_of_elem, align_of_elem: int,
	length: int,
	should_zero: bool,
	allocator: runtime.Allocator,
	loc := #caller_location,
) -> runtime.Allocator_Error {
	if a == nil {
		return nil
	}

	old_size := a.len * size_of_elem
	new_size := length * size_of_elem

	new_data: []byte
	if should_zero {
		new_data = runtime.mem_resize(
			a.data,
			old_size,
			new_size,
			align_of_elem,
			allocator,
			loc,
		) or_return
	} else {
		new_data = runtime.non_zero_mem_resize(
			a.data,
			old_size,
			new_size,
			align_of_elem,
			allocator,
			loc,
		) or_return
	}
	if new_data == nil && new_size > 0 {
		return .Out_Of_Memory
	}

	a.data = raw_data(new_data)

	if should_zero && a.len < length {
		intrinsics.mem_zero(
			([^]byte)(a.data)[a.len * size_of_elem:],
			(length - a.len) * size_of_elem,
		)
	}
	a.len = length
	return nil
}

non_zero_resize_slice :: proc(
	slice: ^$T/[]$E,
	#any_int length: int,
	allocator := context.allocator,
	loc := #caller_location,
) -> runtime.Allocator_Error {
	return _resize_slice(
		(^runtime.Raw_Slice)(slice),
		size_of(E),
		align_of(E),
		length,
		false,
		allocator,
		loc = loc,
	)
}

resize_slice :: proc(
	slice: ^$T/[]$E,
	#any_int length: int,
	allocator := context.allocator,
	loc := #caller_location,
) -> runtime.Allocator_Error {
	return _resize_slice(
		(^runtime.Raw_Slice)(slice),
		size_of(E),
		align_of(E),
		length,
		true,
		allocator,
		loc = loc,
	)
}

// digit-by-digit integer sqrt (port of C sqrt_i64) https://github.com/chmike/fpsqrt
@(require_results)
sqrt_i64 :: #force_inline proc "contextless" (v: $T) -> T where intrinsics.type_is_integer(T) {
	b := u64(1) << u64(62)
	q: u64 = 0
	r := u64(v)
	for b > r do b >>= 2
	for b > 0 {
		t := q + b
		q >>= 1
		if r >= t {
			r -= t
			q += b
		}
		b >>= 2
	}
	return T(q)
}

@(require_results)
sqrt_i32 :: #force_inline proc "contextless" (v: $T) -> T where intrinsics.type_is_integer(T) {
	b := u32(1) << u32(30)
	q: u32 = 0
	r := u32(v)
	for b > r do b >>= 2
	for b > 0 {
		t := q + b
		q >>= 1
		if r >= t {
			r -= t
			q += b
		}
		b >>= 2
	}
	return T(q)
}

@(require_results)
sqrt_i128 :: #force_inline proc "contextless" (v: $T) -> T where intrinsics.type_is_integer(T) {
	b := u128(1) << u128(126)
	q: u128 = 0
	r := u128(v)
	for b > r do b >>= 2
	for b > 0 {
		t := q + b
		q >>= 1
		if r >= t {
			r -= t
			q += b
		}
		b >>= 2
	}
	return T(q)
}

// `inject_at_elem` injects an element in a dynamic array at a specified index and moves the previous elements after that index "across"
non_zero_inject_at_elem :: proc(
	array: ^$T/[dynamic]$E,
	#any_int index: int,
	#no_broadcast arg: E,
	loc := #caller_location,
) -> (
	ok: bool,
	err: runtime.Allocator_Error,
) #no_bounds_check #optional_allocator_error {
	when !ODIN_NO_BOUNDS_CHECK {
		ensure(index >= 0, "Index must be positive.", loc)
	}
	if array == nil {
		return
	}
	n := max(len(array), index)
	m :: 1
	new_size := n + m

	non_zero_resize_dynamic_array(array, new_size, loc) or_return
	when size_of(E) != 0 {
		copy(array[index + m:], array[index:])
		array[index] = arg
	}
	ok = true
	return
}

// `inject_at_elems` injects multiple elements in a dynamic array at a specified index and moves the previous elements after that index "across"
non_zero_inject_at_elems :: proc(
	array: ^$T/[dynamic]$E,
	#any_int index: int,
	#no_broadcast args: ..E,
	loc := #caller_location,
) -> (
	ok: bool,
	err: runtime.Allocator_Error,
) #no_bounds_check #optional_allocator_error {
	when !ODIN_NO_BOUNDS_CHECK {
		ensure(index >= 0, "Index must be positive.", loc)
	}
	if array == nil {
		return
	}
	if len(args) == 0 {
		ok = true
		return
	}

	n := max(len(array), index)
	m := len(args)
	new_size := n + m

	non_zero_resize_dynamic_array(array, new_size, loc) or_return
	when size_of(E) != 0 {
		copy(array[index + m:], array[index:])
		copy(array[index:], args)
	}
	ok = true
	return
}

@(require_results)
ceil_up :: proc "contextless" (num: $T, multiple: T) -> T where intrinsics.type_is_integer(T) {
	if multiple == 0 do return num

	remain := abs(num) % multiple
	if remain == 0 do return num

	if num < 0 do return -(abs(num) + multiple - remain)
	return num + multiple - remain
}
@(require_results)
floor_up :: proc "contextless" (num: $T, multiple: T) -> T where intrinsics.type_is_integer(T) {
	if multiple == 0 do return num

	remain := abs(num) % multiple
	if remain == 0 do return num

	if num < 0 do return -(abs(num) - remain)
	return num - remain
}
@(require_results)
min_array :: proc "contextless" (
	value0: $T/[$N]$E,
	value1: T,
) -> (
	result: T,
) where intrinsics.type_is_array(T) {
	#unroll for i in 0 ..< len(value0) {
		m: E = value0[i]
		if m > value1[i] do m = value1[i]
		result[i] = m
	}
	return
}
@(require_results)
max_array :: proc "contextless" (
	value0: $T/[$N]$E,
	value1: T,
) -> (
	result: T,
) where intrinsics.type_is_array(T) {
	#unroll for i in 0 ..< len(value0) {
		m: E = value0[i]
		if m < value1[i] do m = value1[i]
		result[i] = m
	}
	return
}
@(require_results)
epsilon :: proc "contextless" ($T: typeid) -> T where intrinsics.type_is_float(T) {
	when T == f16 || T == f16be || T == f16le do return T(math.F16_EPSILON)
	when T == f32 || T == f32be || T == f32le do return T(math.F32_EPSILON)
	return T(math.F64_EPSILON)
}
@(require_results)
epsilon_equal :: proc "contextless" (a: $T, b: T) -> bool where intrinsics.type_is_float(T) {
	return abs(a - b) < epsilon(T)
}

Prev :: proc "contextless" (#any_int idx: int, #any_int len: int) -> int {
	return idx == 0 ? len - 1 : idx - 1
}

Next :: proc "contextless" (#any_int idx: int, #any_int len: int) -> int {
	return (idx + 1) % len
}
