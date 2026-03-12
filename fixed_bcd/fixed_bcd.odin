package fixed_bcd

import "core:fmt"
import "core:math"


BCD :: struct($FRAC_DIGITS: int) {
	i: i128, // 스케일된 값 (부호 포함)
}

// 10^n table for scale lookup, n=0..15 (i128 fits up to 10^38)
@(private, rodata)
_SCALE_TABLE := [15]i128 {
	10,
	100,
	1_000,
	10_000,
	100_000,
	1_000_000,
	10_000_000,
	100_000_000,
	1_000_000_000,
	10_000_000_000,
	100_000_000_000,
	1_000_000_000_000,
	10_000_000_000_000,
	100_000_000_000_000,
	1_000_000_000_000_000,
}

@(private)
_scale :: #force_inline proc "contextless" ($FRAC: int) -> i128 {
	#assert(FRAC <= 15)
	return _SCALE_TABLE[FRAC]
}

@(private)
_scale_at :: #force_inline proc "contextless" (n: int) -> i128 {
	return _SCALE_TABLE[n]
}

// Convert f64 to BCD without overflow: build scaled i from int/frac parts in integer.
from_f64 :: proc "contextless" ($FRAC: int, x: f64) -> BCD(FRAC) {
	scale := _scale(FRAC)
	neg := x < 0
	x_abs := math.abs(x)
	int_part := i128(x_abs)
	frac := x_abs - f64(int_part) // in [0, 1)

	int_scaled := int_part * scale

	val := int_scaled + i128(frac * f64(scale))
	if neg do val = -val
	return BCD(FRAC){i = val}
}


@(private)
_frac_digit_count :: proc "contextless" (frac: int) -> int {
	n := frac
	if n == 0 do return 0
	d := 0
	for n > 0 {
		d += 1
		n /= 10
	}
	return d
}


// init from integer part and fractional part. //!FRAC MUST >= 0
init :: proc "contextless" (
	#any_int INT: int,
	#any_int FRAC: int,
	$FRAC_DIGITS: int,
) -> BCD(FRAC_DIGITS) {
	diff := FRAC_DIGITS - _frac_digit_count(FRAC)

	ii := abs(INT)
	return BCD(FRAC_DIGITS) {
		i = INT < 0 ? -(i128(ii) * _scale(FRAC_DIGITS) + i128(FRAC) * _scale_at(diff)) : i128(ii) * _scale(FRAC_DIGITS) + i128(FRAC) * _scale_at(diff),
	}
}

to_string :: proc(a: $T/BCD, allocator := context.allocator) -> string {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _scale(FRAC)

	v := a.i
	negative := v < 0
	if negative do v = -v

	int_part := v / scale
	frac_part := v % scale

	if FRAC == 0 {
		return negative ? fmt.aprintf("-%d", int_part) : fmt.aprintf("%d", int_part)
	}

	return(
		negative ? fmt.aprintf("-%d.%0*d", int_part, FRAC, frac_part, allocator = allocator) : fmt.aprintf("%d.%0*d", int_part, FRAC, frac_part, allocator = allocator) \
	)
}

add :: proc "contextless" (a, b: $T/BCD) -> T {
	return T{i = a.i + b.i}
}

sub :: proc "contextless" (a, b: $T/BCD) -> T {
	return T{i = a.i - b.i}
}

mul :: proc "contextless" (a, b: $T/BCD) -> T {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _scale(FRAC)
	return T{i = a.i * b.i / scale}
}

div :: proc "contextless" (a, b: $T/BCD) -> T {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _scale(FRAC)
	return T{i = a.i * scale / b.i}
}

cmp :: proc "contextless" (a, b: $T/BCD) -> int {
	if a.i > b.i do return 1
	if a.i < b.i do return -1
	return 0
}

eq :: proc "contextless" (a, b: $T/BCD) -> bool {return a.i == b.i}
lt :: proc "contextless" (a, b: $T/BCD) -> bool {return a.i < b.i}
gt :: proc "contextless" (a, b: $T/BCD) -> bool {return a.i > b.i}


to_f64 :: proc "contextless" (a: $T/BCD) -> f64 {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _scale(FRAC)
	return f64(a.i) / f64(scale)
}

to_i128 :: proc "contextless" (a: $T/BCD) -> i128 {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _scale(FRAC)
	return a.i / scale
}

