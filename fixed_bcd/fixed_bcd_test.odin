package fixed_bcd

import "core:fmt"
import "core:math"
import "core:testing"


@(test)
testFromF64 :: proc(t: ^testing.T) {
	a := fromF64(MaxFracDigits, math.PI)
	fmt.println("[fromF64 π]", toString(a, context.temp_allocator))

	testing.expect(t, toF64(a) == math.PI)
}

@(test)
testAdd :: proc(t: ^testing.T) {
	a := initConst(2, 1334, 4, DefFracDigits)
	b := initConst(2, 1334, 4, DefFracDigits)
	r := add(a, b)
	fmt.println("[add] 2.1334 + 2.1334 =", toString(r, context.temp_allocator))
}

@(test)
testSub :: proc(t: ^testing.T) {
	a := initConst(130, 0, 0, DefFracDigits)
	b := initConst(0, 1, 1, DefFracDigits)
	r := sub(a, b)
	fmt.println("[sub] 130.0 - 0.1 =", toString(r, context.temp_allocator))
}

@(test)
testSubNegative :: proc(t: ^testing.T) {
	a := initConst(-133, 456, 3, DefFracDigits)
	b := initConst(130, 0, 0, DefFracDigits)
	r := sub(a, b)
	fmt.println("[sub_negative] -133.456 - 130.0 =", toString(r, context.temp_allocator))
}

@(test)
testMul :: proc(t: ^testing.T) {
	a := initConst(2, 1334, 4, DefFracDigits)
	b := initConst(2, 1334, 4, DefFracDigits)
	r := mul(a, b)
	fmt.println("[mul] 2.1334 × 2.1334 =", toString(r, context.temp_allocator))
	fmt.println("[mul] 기댓값          = 4.55139556000000000")
}

@(test)
testMulBig :: proc(t: ^testing.T) {
	a := initConst(9999999999, 12345, 5, DefFracDigits)
	b := initConst(9999999999, 12345, 5, DefFracDigits)
	r := mul(a, b)
	fmt.println(
		"[mul] 999999999999.12345 × 999999999999.12345 =",
		toString(r, context.temp_allocator),
	)
	fmt.println(
		"[mul] 기댓값                                  = 99999999998246900000.76833990250000000",
	)
}

@(test)
testMulMaxFrag :: proc(t: ^testing.T) {
	a := initConst(9999, 99999999, 8, MaxFracDigits)
	b := initConst(9999, 99999999, 8, MaxFracDigits)
	r := mul(a, b)
	fmt.println("[mul] 9999.99999999 × 9999.99999999 =", toString(r, context.temp_allocator))
	fmt.println("[mul] 기댓값                        = 99999999.99980000000000010")
}

@(test)
testMulNegative :: proc(t: ^testing.T) {
	a := initConst(-2, 0, 0, MaxFracDigits)
	b := initConst(3, 0, 0, MaxFracDigits)
	r := mul(a, b)
	fmt.println("[mul_negative] -2.0 × 3.0 =", toString(r, context.temp_allocator))
}

@(test)
testDiv :: proc(t: ^testing.T) {
	a := initConst(9999999999999, 0, 0, DefFracDigits)
	b := initConst(10, 0, 0, DefFracDigits)
	r := div(a, b)
	fmt.println("[div] 9999999999999 / 10 =", toString(r, context.temp_allocator))
}
