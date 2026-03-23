package fixed_bcd

import "base:intrinsics"
import "core:fmt"


DEF_FRAC_DIGITS :: MAX_FRAC_DIGITS
MAX_FRAC_DIGITS :: len(_SCALE_TABLE) - 1

BCD :: struct($FRAC_DIGITS: int) {
	i: i128, // 스케일된 값 (부호 포함)
}

// 10^n table for scale lookup: n => 10^n, n=1..<=len(_SCALE_TABLE) (i128 fits up to 10^38)
_SCALE_TABLE :: [18]i128 {
	1,
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
	scale := _SCALE_TABLE[FRAC]
	neg := x < 0
	x_abs := abs(x)
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
	$FRAC_LEN: int,
	$FRAC_DIGITS: int,
) -> BCD(FRAC_DIGITS) {
	n := FRAC
	ii: int

	when FRAC_LEN <= 0 { 	// 직접 계산
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

		ii = abs(INT)
		return BCD(FRAC_DIGITS) {
			i = INT < 0 ? -(i128(ii) * _SCALE_TABLE[FRAC_DIGITS] + i128(FRAC) * i128(d2)) : i128(ii) * _SCALE_TABLE[FRAC_DIGITS] + i128(FRAC) * i128(d2),
		}
	}

	ii = abs(INT)
	return BCD(FRAC_DIGITS) {
		i = INT < 0 ? -(i128(ii) * _SCALE_TABLE[FRAC_DIGITS] + i128(FRAC) * _SCALE_TABLE[FRAC_DIGITS - FRAC_LEN]) : i128(ii) * _SCALE_TABLE[FRAC_DIGITS] + i128(FRAC) * _SCALE_TABLE[FRAC_DIGITS - FRAC_LEN],
	}
}

init_const :: proc "contextless" (
	$INT: int,
	$FRAC: int,
	$FRAC_LEN: int,
	$FRAC_DIGITS: int,
) -> BCD(FRAC_DIGITS) {
	when INT < 0 {
		return BCD(FRAC_DIGITS) {
			i = i128(INT) * _SCALE_TABLE[FRAC_DIGITS] -
			i128(FRAC) * _SCALE_TABLE[FRAC_DIGITS - FRAC_LEN],
		}
	}
	return BCD(FRAC_DIGITS) {
		i = i128(INT) * _SCALE_TABLE[FRAC_DIGITS] +
		i128(FRAC) * _SCALE_TABLE[FRAC_DIGITS - FRAC_LEN],
	}
}

to_string :: proc(a: $T/BCD, allocator := context.allocator) -> string {
	v := a.i
	negative := v < 0
	if negative do v = -v

	int_part := v / _SCALE_TABLE[type_of(a).FRAC_DIGITS]

	when type_of(a).FRAC_DIGITS == 0 {
		return negative ? fmt.aprintf("-%d", int_part) : fmt.aprintf("%d", int_part)
	}
	frac_part := v % _SCALE_TABLE[type_of(a).FRAC_DIGITS]

	return(
		negative ? fmt.aprintf("-%d.%0*d", int_part, type_of(a).FRAC_DIGITS, frac_part, allocator = allocator) : fmt.aprintf("%d.%0*d", int_part, type_of(a).FRAC_DIGITS, frac_part, allocator = allocator) \
	)
}

add :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> BCD(FRAC_DIGITS) {
	return BCD(FRAC_DIGITS){i = a.i + b.i}
}

sub :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> BCD(FRAC_DIGITS) {
	return BCD(FRAC_DIGITS){i = a.i - b.i}
}

@(private)
MulU128ByU64 :: proc "contextless" (a: u128, b: u64) -> (hi, lo: u128) {
	mask64 :: u128(max(u64))
	a0 := a & mask64
	a1 := a >> 64

	p0 := a0 * u128(b)
	p1 := a1 * u128(b)

	mid := (p0 >> 64) + (p1 & mask64)

	lo = (p0 & mask64) | (mid << 64)
	hi = p1 >> 64
	return
}

//Knuth TAOCP Vol.2 Algorithm D // TODO 복잡해서 추후에 더 확인
@(private)
DivU256ByU128 :: proc "contextless" (n_hi, n_lo, d: u128) -> u128 {
	if n_hi == 0 do return n_lo / d

	// d 를 64비트로 정규화
	shift := u32(intrinsics.count_leading_zeros(d))
	d_norm := d << shift
	n_hi_s := (n_hi << shift) | (n_lo >> (128 - shift))
	n_lo_s := n_lo << shift

	d_hi := d_norm >> 64
	d_lo := d_norm & u128(max(u64))

	// 1단계: 상위 128비트 / d_hi → 몫 근사
	q1 := n_hi_s / d_hi
	rem1 := n_hi_s % d_hi

	// q1 보정 (최대 2번)
	for q1 >> 64 != 0 || q1 * d_lo > (rem1 << 64) | (n_lo_s >> 64) {
		q1 -= 1
		rem1 += d_hi
		if rem1 >> 64 != 0 do break
	}

	// 2단계: 하위 128비트 / d_hi → 몫 근사
	rem2 := ((n_hi_s - q1 * d_hi) << 64) | (n_lo_s >> 64)
	q2 := rem2 / d_hi
	rem3 := rem2 % d_hi

	for q2 >> 64 != 0 || q2 * d_lo > (rem3 << 64) | (n_lo_s & u128(max(u64))) {
		q2 -= 1
		rem3 += d_hi
		if rem3 >> 64 != 0 do break
	}

	return (q1 << 64) | q2
}

mul :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> BCD(FRAC_DIGITS) {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _SCALE_TABLE[FRAC]

	product, overflowed := intrinsics.overflow_mul(a.i, b.i)
	if !overflowed {
		return BCD(FRAC_DIGITS){i = product / scale}
	}
	// 정수 분해 (최종 값이 오버플로우 없다고 가정)
	a_int := a.i / scale
	a_frac := a.i % scale
	b_int := b.i / scale
	b_frac := b.i % scale

	return BCD(FRAC_DIGITS) {
		i = a_int * b_int * scale + a_int * b_frac + a_frac * b_int + a_frac * b_frac / scale,
	}
}

div :: proc "contextless" (a, b: $T/BCD) -> T {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _SCALE_TABLE[FRAC]

	if a.i == 0 do return T{i = 0}

	scaled, overflowed := intrinsics.overflow_mul(a.i, scale)
	if !overflowed do return T{i = scaled / b.i}

	negative := (a.i < 0) != (b.i < 0)
	n_hi, n_lo := MulU128ByU64(auto_cast abs(a.i), u64(scale))
	q_u := DivU256ByU128(n_hi, n_lo, auto_cast abs(b.i))
	return T{i = negative ? -i128(q_u) : i128(q_u)}
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
less :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> bool {return a.i < b.i}
greater :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> bool {return(
		a.i >
		b.i \
	)}

sign :: proc "contextless" (a: BCD($FRAC_DIGITS)) -> BCD(FRAC_DIGITS) {
	return BCD(FRAC_DIGITS){i = -a.i}
}

less_than :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> bool {return(
		a.i <=
		b.i \
	)}
greater_than :: proc "contextless" (a: BCD($FRAC_DIGITS), b: BCD(FRAC_DIGITS)) -> bool {return(
		a.i >=
		b.i \
	)}

to_f64 :: proc "contextless" (a: BCD($FRAC_DIGITS)) -> f64 {
	FRAC :: type_of(a).FRAC_DIGITS
	scale := _SCALE_TABLE[FRAC]
	return f64(a.i) / f64(scale)
}

length2 :: proc "contextless" (ab: [2]BCD($FRAC_DIGITS)) -> BCD(FRAC_DIGITS) {
	dx := ab.x
	dy := ab.y
	return add(mul(dx, dx), mul(dy, dy))
}

inf_min :: proc "contextless" ($FRAC_DIGITS: int) -> BCD(FRAC_DIGITS) {
	return BCD(FRAC_DIGITS){i = min(i128)}
}
inf_max :: proc "contextless" ($FRAC_DIGITS: int) -> BCD(FRAC_DIGITS) {
	return BCD(FRAC_DIGITS){i = max(i128)}
}

//a*b ? c*d
compare_product :: proc "contextless" (
	a: BCD($FRAC_DIGITS),
	b: BCD(FRAC_DIGITS),
	c: BCD(FRAC_DIGITS),
	d: BCD(FRAC_DIGITS),
) -> int {
	if (c.i == 0 || d.i == 0) && (b.i == 0 || a.i == 0) do return 0

	if (c.i == 0 || d.i == 0) {
		return ((a.i > 0) == (b.i > 0)) ? 1 : -1
	} else if (b.i == 0 || a.i == 0) {
		return ((c.i > 0) == (d.i > 0)) ? -1 : 1
	}
	q1 := a.i / c.i
	q2 := d.i / b.i

	// 1단계: 몫 비교
	if q1 != q2 {
		return q1 > q2 ? 1 : -1
	}

	r1 := a.i % c.i
	r2 := d.i % b.i

	// 2단계: r1*b vs r2*c
	lhs := r1 * b.i
	rhs := r2 * c.i

	if lhs > rhs do return 1
	if lhs < rhs do return -1
	return 0
}

