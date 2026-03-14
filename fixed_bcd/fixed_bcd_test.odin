package fixed_bcd

import "core:fmt"
import "core:math"
import "core:testing"


@(test)
test_from_f64 :: proc(t: ^testing.T) {
	a := from_f64(MAX_FRAC_DIGITS, math.PI)
	fmt.println("[from_f64 π]", to_string(a, context.temp_allocator))

	testing.expect(t, to_f64(a) == math.PI)
}

@(test)
test_add :: proc(t: ^testing.T) {
	a := init_const2(2, 1334, DEF_FRAC_DIGITS)
	b := init_const2(2, 1334, DEF_FRAC_DIGITS)
	r := add(a, b)
	fmt.println("[add] 2.1334 + 2.1334 =", to_string(r, context.temp_allocator))
}

@(test)
test_sub :: proc(t: ^testing.T) {
	a := init_const2(130, 0, DEF_FRAC_DIGITS)
	b := init_const2(0, 1, DEF_FRAC_DIGITS)
	r := sub(a, b)
	fmt.println("[sub] 130.0 - 0.1 =", to_string(r, context.temp_allocator))
}

@(test)
test_sub_negative :: proc(t: ^testing.T) {
	a := init_const2(-133, 456, DEF_FRAC_DIGITS)
	b := init_const2(130, 0, DEF_FRAC_DIGITS)
	r := sub(a, b)
	fmt.println("[sub_negative] -133.456 - 130.0 =", to_string(r, context.temp_allocator))
}

@(test)
test_mul :: proc(t: ^testing.T) {
	a := init_const2(2, 1334, DEF_FRAC_DIGITS)
	b := init_const2(2, 1334, DEF_FRAC_DIGITS)
	r := mul(a, b)
	fmt.println("[mul] 2.1334 × 2.1334 =", to_string(r, context.temp_allocator))
	fmt.println("[mul] 기댓값          = 4.551395560000000")
}

@(test)
test_mul_big :: proc(t: ^testing.T) {
	a := init_const2(99999999999, 12345, DEF_FRAC_DIGITS)
	b := init_const2(99999999999, 12345, DEF_FRAC_DIGITS)
	r := mul(a, b)
	fmt.println(
		"[mul] 999999999999.12345 × 999999999999.12345 =",
		to_string(r, context.temp_allocator),
	)
	fmt.println(
		"[mul] 기댓값                                  = 9999999999824690000000.768339902500000",
	)
}

@(test)
test_mul_max_frag :: proc(t: ^testing.T) {
	a := init_const2(9999, 99999999, MAX_FRAC_DIGITS)
	b := init_const2(9999, 99999999, MAX_FRAC_DIGITS)
	r := mul(a, b)
	fmt.println("[mul] 9999.99999999 × 9999.99999999 =", to_string(r, context.temp_allocator))
	fmt.println("[mul] 기댓값                        = 99999999.99980000000000010")
}

@(test)
test_mul_negative :: proc(t: ^testing.T) {
	a := init_const2(-2.0, 0, MAX_FRAC_DIGITS)
	b := init_const2(3.0, 0, MAX_FRAC_DIGITS)
	r := mul(a, b)
	fmt.println("[mul_negative] -2.0 × 3.0 =", to_string(r, context.temp_allocator))
}

@(test)
test_div :: proc(t: ^testing.T) {
	a := init_const2(99999999, 0, DEF_FRAC_DIGITS) //max cover 99999999 becaude not impl overflow handle only div
	b := init_const2(10, 0, DEF_FRAC_DIGITS)
	r := div(a, b)
	fmt.println("[div] 99999999 / 10 =", to_string(r, context.temp_allocator))
}

