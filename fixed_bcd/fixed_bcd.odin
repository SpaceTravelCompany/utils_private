package fixed_bcd

import "base:intrinsics"
import "core:fmt"
import "core:math"


DEF_FRAC_DIGITS :: 15
MAX_FRAC_DIGITS :: len(_SCALE_TABLE)

BCD :: struct($FRAC_DIGITS: int) {
	i: i128, // 스케일된 값 (부호 포함)
}

// 10^n table for scale lookup: n => 10^n, n=1..<=len(_SCALE_TABLE) (i128 fits up to 10^38)
_SCALE_TABLE :: [17]i128 {
	10, // 10^1
	100, // 10^2
	1_000, // 10^3
	10_000, // 10^4
	100_000, // 10^5
	1_000_000, // 10^6
	10_000_000, // 10^7
	100_000_000, // 10^8
	1_000_000_000, // 10^9
	10_000_000_000, // 10^10
	100_000_000_000, // 10^11
	1_000_000_000_000, // 10^12
	10_000_000_000_000, // 10^13
	100_000_000_000_000, // 10^14
	1_000_000_000_000_000, // 10^15
	10_000_000_000_000_000, // 10^16
	100_000_000_000_000_000, // 10^17
}

// Convert f64 to BCD without overflow: build scaled i from int/frac parts in integer.
from_f64 :: proc "contextless" ($FRAC: int, x: f64) -> BCD(FRAC) {
	scale := _SCALE_TABLE[FRAC - 1]
	neg := x < 0
	x_abs := math.abs(x)
	int_part := i128(x_abs)
	frac := x_abs - f64(int_part) // in [0, 1)

	int_scaled := int_part * scale

	val := int_scaled + i128(frac * f64(scale))
	if neg do val = -val
	return BCD(FRAC){i = val}
}

// init from integer part and fractional part. //!FRAC MUST >= 0
init :: proc "contextless" (
	#any_int INT: int,
	#any_int FRAC: int,
	$FRAC_DIGITS: int,
) -> BCD(FRAC_DIGITS) {
	n := FRAC

	d2 := 1
	if n != 0 {
		d := 0
		for n > 0 {
			d += 1
			n /= 10
		}
		d = FRAC_DIGITS - d
		for d > 0 {
			d -= 1
			d2 *= 10
		}
	}

	ii := abs(INT)
	return BCD(FRAC_DIGITS) {
		i = INT < 0 ? -(i128(ii) * _SCALE_TABLE[FRAC_DIGITS - 1] + i128(FRAC) * i128(d2)) : i128(ii) * _SCALE_TABLE[FRAC_DIGITS - 1] + i128(FRAC) * i128(d2),
	}
}

to_string :: proc(a: $T/BCD, allocator := context.allocator) -> string {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _SCALE_TABLE[FRAC - 1]

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

	a_int := a.i / _SCALE_TABLE[FRAC - 1]
	a_frac := a.i % _SCALE_TABLE[FRAC - 1]
	b_int := b.i / _SCALE_TABLE[FRAC - 1]
	b_frac := b.i % _SCALE_TABLE[FRAC - 1]

	// a_int * b_int 는 스케일 없으므로 다시 곱해야
	// a_int * b_frac, a_frac * b_int 는 스케일 한번 들어있으므로 그대로
	// a_frac * b_frac 는 스케일 두번이므로 나눠야

	return T {
		i = a_int * b_int * _SCALE_TABLE[FRAC - 1] +
		a_int * b_frac +
		a_frac * b_int +
		a_frac * b_frac / _SCALE_TABLE[FRAC - 1],
	}
}

div :: proc "contextless" (a, b: $T/BCD) -> T {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _SCALE_TABLE[FRAC - 1]
	return T{i = a.i * scale / b.i} //TODO 오버플로우 처리?
}

cmp :: proc "contextless" (a, b: $T/BCD) -> int {
	if a.i > b.i do return 1
	if a.i < b.i do return -1
	return 0
}

equal :: proc "contextless" (
	a, b: $T,
) -> bool where intrinsics.type_is_specialization_of(T, BCD) ||
	(intrinsics.type_is_array(T) &&
			intrinsics.type_is_specialization_of(intrinsics.type_elem_type(T), BCD)) {
	when intrinsics.type_is_array(T) {
		#unroll for i in 0 ..< len(a) {
			if a[i].i != b[i].i do return false
		}
		return true
	} else {
		return a.i == b.i
	}
}
less :: proc "contextless" (a, b: BCD($FRAC_DIGITS)) -> bool {return a.i < b.i}
greater :: proc "contextless" (a, b: BCD($FRAC_DIGITS)) -> bool {return a.i > b.i}


to_f64 :: proc "contextless" (a: BCD($FRAC_DIGITS)) -> f64 {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _SCALE_TABLE[FRAC - 1]
	return f64(a.i) / f64(scale)
}

length2 :: proc "contextless" (a, b: [2]BCD($FRAC_DIGITS)) -> BCD(FRAC_DIGITS) {
	dx := sub(b.x, a.x)
	dy := sub(b.y, a.y)
	return add(mul(dx, dx), mul(dy, dy))
}

