package fixed_bcd

import "base:intrinsics"
import "core:fmt"


DefFracDigits :: MaxFracDigits
MaxFracDigits :: len(_ScaleTable) - 1

BCD :: struct($fracDigits: i64) {
	i: i128, // 스케일된 값 (부호 포함)
}

// 10^n table for scale lookup: n => 10^n, n=1..<=len(_ScaleTable) (i128 fits up to 10^38)
_ScaleTable :: [18]i128 {
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
fromF64 :: proc "contextless" ($frac: i64, x: f64) -> BCD(frac) {
	scale := _ScaleTable[frac]
	neg := x < 0
	xAbs := abs(x)
	intPart := i128(xAbs)
	fr := xAbs - f64(intPart) // in [0, 1)

	intScaled := intPart * scale

	val := intScaled + i128(fr * f64(scale))
	if neg do val = -val
	return BCD(frac){i = val}
}

// init from integer part and fractional part. //!frac MUST >= 0
init :: proc "contextless" (
	#any_int integ: int,
	#any_int frac: int,
	$fracLen: int,
	$fracDigits: int,
) -> BCD(fracDigits) {
	n := frac
	ii: int

	when fracLen <= 0 { 	// 직접 계산
		d2 := 1
		if n != 0 {
			d := 0
			for n > 0 {
				d += 1
				n /= 10
			}
			d = fracDigits - d
			for d > 0 {
				d -= 1
				d2 *= 10
			}
		}

		ii = abs(integ)
		return BCD(fracDigits) {
			i = integ < 0 ? -(i128(ii) * _ScaleTable[fracDigits] + i128(frac) * i128(d2)) : i128(ii) * _ScaleTable[fracDigits] + i128(frac) * i128(d2),
		}
	}

	ii = abs(integ)
	return BCD(fracDigits) {
		i = integ < 0 ? -(i128(ii) * _ScaleTable[fracDigits] + i128(frac) * _ScaleTable[fracDigits - fracLen]) : i128(ii) * _ScaleTable[fracDigits] + i128(frac) * _ScaleTable[fracDigits - fracLen],
	}
}

initConst :: proc "contextless" (
	$integ: i64,
	$frac: i64,
	$fracLen: i64,
	$fracDigits: i64,
) -> BCD(fracDigits) {
	when integ < 0 {
		return BCD(fracDigits) {
			i = i128(integ) * _ScaleTable[fracDigits] -
			i128(frac) * _ScaleTable[fracDigits - fracLen],
		}
	}
	return BCD(fracDigits) {
		i = i128(integ) * _ScaleTable[fracDigits] +
		i128(frac) * _ScaleTable[fracDigits - fracLen],
	}
}

toString :: proc(a: $T/BCD, allocator := context.allocator) -> string {
	v := a.i
	negative := v < 0
	if negative do v = -v

	intPart := v / _ScaleTable[type_of(a).fracDigits]

	when type_of(a).fracDigits == 0 {
		return negative ? fmt.aprintf("-%d", intPart) : fmt.aprintf("%d", intPart)
	}
	fracPart := v % _ScaleTable[type_of(a).fracDigits]

	return(
		negative ? fmt.aprintf("-%d.%0*d", intPart, type_of(a).fracDigits, fracPart, allocator = allocator) : fmt.aprintf("%d.%0*d", intPart, type_of(a).fracDigits, fracPart, allocator = allocator) \
	)
}

add :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> BCD(fracDigits) {
	return BCD(fracDigits){i = a.i + b.i}
}

sub :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> BCD(fracDigits) {
	return BCD(fracDigits){i = a.i - b.i}
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
DivU256ByU128 :: proc "contextless" (nHi, nLo, d: u128) -> u128 {
	// d 를 64비트로 정규화
	shift := intrinsics.count_leading_zeros(d)
	dNorm := d << shift
	nHiS := (nHi << shift) | (nLo >> (128 - shift))
	nLoS := nLo << shift

	dHi := dNorm >> 64
	dLo := dNorm & u128(max(u64))

	// 1단계: 상위 128비트 / dHi → 몫 근사
	q1 := nHiS / dHi
	rem1 := nHiS % dHi

	// q1 보정 (최대 2번)
	for q1 >> 64 != 0 || q1 * dLo > (rem1 << 64) | (nLoS >> 64) {
		q1 -= 1
		rem1 += dHi
		if rem1 >> 64 != 0 do break
	}

	// 2단계: 하위 128비트 / dHi → 몫 근사
	rem2 := ((nHiS - q1 * dHi) << 64) | (nLoS >> 64)
	q2 := rem2 / dHi
	rem3 := rem2 % dHi

	for q2 >> 64 != 0 || q2 * dLo > (rem3 << 64) | (nLoS & u128(max(u64))) {
		q2 -= 1
		rem3 += dHi
		if rem3 >> 64 != 0 do break
	}

	return (q1 << 64) | q2
}

mul :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> BCD(fracDigits) {
	FRAC :: type_of(a).fracDigits
	scale := _ScaleTable[FRAC]

	product, overflowed := intrinsics.overflow_mul(a.i, b.i)
	if !overflowed {
		return BCD(fracDigits){i = product / scale}
	}
	// 정수 분해 (최종 값이 오버플로우 없다고 가정)
	aInt := a.i / scale
	aFrac := a.i % scale
	bInt := b.i / scale
	bFrac := b.i % scale

	return BCD(fracDigits) {
		i = aInt * bInt * scale + aInt * bFrac + aFrac * bInt + aFrac * bFrac / scale,
	}
}

div :: proc "contextless" (a, b: $T/BCD) -> T {
	FRAC :: type_of(a).fracDigits
	scale := _ScaleTable[FRAC]

	if a.i == 0 do return T{i = 0}

	scaled, overflowed := intrinsics.overflow_mul(a.i, scale)
	if !overflowed do return T{i = scaled / b.i}

	negative := (a.i < 0) != (b.i < 0)
	nHi, nLo := MulU128ByU64(auto_cast abs(a.i), u64(scale))
	qU := DivU256ByU128(nHi, nLo, auto_cast abs(b.i))
	return T{i = negative ? -i128(qU) : i128(qU)}
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
less :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> bool {return a.i < b.i}
greater :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> bool {return(
		a.i >
		b.i \
	)}

sign :: proc "contextless" (a: BCD($fracDigits)) -> BCD(fracDigits) {
	return BCD(fracDigits){i = -a.i}
}

lessThan :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> bool {return(
		a.i <=
		b.i \
	)}
greaterThan :: proc "contextless" (a: BCD($fracDigits), b: BCD(fracDigits)) -> bool {return(
		a.i >=
		b.i \
	)}

toF64 :: proc "contextless" (a: BCD($fracDigits)) -> f64 {
	FRAC :: type_of(a).fracDigits
	scale := _ScaleTable[FRAC]
	return f64(a.i) / f64(scale)
}

length2 :: proc "contextless" (ab: [2]BCD($fracDigits)) -> BCD(fracDigits) {
	dx := ab.x
	dy := ab.y
	return add(mul(dx, dx), mul(dy, dy))
}

infMin :: proc "contextless" ($fracDigits: int) -> BCD(fracDigits) {
	return BCD(fracDigits){i = min(i128)}
}
infMax :: proc "contextless" ($fracDigits: int) -> BCD(fracDigits) {
	return BCD(fracDigits){i = max(i128)}
}

//a*b ? c*d
compareProduct :: proc "contextless" (
	a: BCD($fracDigits),
	b: BCD(fracDigits),
	c: BCD(fracDigits),
	d: BCD(fracDigits),
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
