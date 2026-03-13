package fixed_bcd

import "core:fmt"
import "core:math"
import "core:testing"


@(test)
test_from_f64 :: proc(t: ^testing.T) {
	a := from_f64(DEF_FRAC_DIGITS, math.PI)
	fmt.println("[from_f64 π]", to_string(a, context.temp_allocator))
}

@(test)
test_add :: proc(t: ^testing.T) {
	a := init(2, 1334, DEF_FRAC_DIGITS)
	b := init(2, 1334, DEF_FRAC_DIGITS)
	r := add(a, b)
	fmt.println("[add] 2.1334 + 2.1334 =", to_string(r, context.temp_allocator))
}

@(test)
test_add_carry :: proc(t: ^testing.T) {
	a := init(9, 9, DEF_FRAC_DIGITS)
	b := init(0, 1, DEF_FRAC_DIGITS)
	r := add(a, b)
	fmt.println("[add_carry] 9.9 + 0.1 =", to_string(r, context.temp_allocator))
}

@(test)
test_sub :: proc(t: ^testing.T) {
	a := init(130, 0, DEF_FRAC_DIGITS)
	b := init(0, 1, DEF_FRAC_DIGITS)
	r := sub(a, b)
	fmt.println("[sub] 130.0 - 0.1 =", to_string(r, context.temp_allocator))
}

@(test)
test_sub_negative :: proc(t: ^testing.T) {
	a := init(-133, 456, DEF_FRAC_DIGITS)
	b := init(130, 0, DEF_FRAC_DIGITS)
	r := sub(a, b)
	fmt.println("[sub_negative] -133.456 - 130.0 =", to_string(r, context.temp_allocator))
}

@(test)
test_mul :: proc(t: ^testing.T) {
	a := init(2, 1334, DEF_FRAC_DIGITS)
	b := init(2, 1334, DEF_FRAC_DIGITS)
	r := mul(a, b)
	fmt.println("[mul] 2.1334 × 2.1334 =", to_string(r, context.temp_allocator))
	fmt.println("[mul] 기댓값          = 4.551395560000000")
}

@(test)
test_mul_big :: proc(t: ^testing.T) {
	a := init(99999999999, 12345, DEF_FRAC_DIGITS)
	b := init(99999999999, 12345, DEF_FRAC_DIGITS)
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
	a := init(9999, 99999999, MAX_FRAC_DIGITS)
	b := init(9999, 99999999, MAX_FRAC_DIGITS)
	r := mul(a, b)
	fmt.println("[mul] 9999.12345 × 9999.12345 =", to_string(r, context.temp_allocator))
	fmt.println("[mul] 기댓값                  = 99999999.99980000000000010")
}

@(test)
test_mul_negative :: proc(t: ^testing.T) {
	a := from_f64(DEF_FRAC_DIGITS, -2.0)
	b := from_f64(DEF_FRAC_DIGITS, 3.0)
	r := mul(a, b)
	fmt.println("[mul_negative] -2.0 × 3.0 =", to_string(r, context.temp_allocator))
}

@(test)
test_div :: proc(t: ^testing.T) {
	a := from_f64(DEF_FRAC_DIGITS, 13.0)
	b := from_f64(DEF_FRAC_DIGITS, 4.0)
	r := div(a, b)
	fmt.println("[div] 13.0 / 4.0 =", to_string(r, context.temp_allocator))
}

@(test)
test_cmp :: proc(t: ^testing.T) {
	p := from_f64(DEF_FRAC_DIGITS, 13.5)
	q := from_f64(DEF_FRAC_DIGITS, 13.6)
	testing.expect(t, cmp(p, q) < 0, "13.5 < 13.6 실패")
	testing.expect(t, cmp(q, p) > 0, "13.6 > 13.5 실패")
	testing.expect(t, cmp(p, p) == 0, "13.5 == 13.5 실패")
	fmt.println("[cmp] cmp(13.5, 13.6) =", cmp(p, q))
}

@(test)
test_cmp_negative :: proc(t: ^testing.T) {
	a := from_f64(DEF_FRAC_DIGITS, -5.0)
	b := from_f64(DEF_FRAC_DIGITS, 5.0)
	testing.expect(t, cmp(a, b) < 0, "-5.0 < 5.0 실패")
	fmt.println("[cmp_negative] cmp(-5.0, 5.0) =", cmp(a, b))
}

@(test)
test_to_f64 :: proc(t: ^testing.T) {
	a := from_f64(DEF_FRAC_DIGITS, 2.1334)
	f := to_f64(a)
	fmt.println("[to_f64]", f)
}

@(test)
test_init :: proc(t: ^testing.T) {
	a := init(2, 1334, DEF_FRAC_DIGITS)
	fmt.println("[init] 2.1334 =", to_string(a, context.temp_allocator))
	b := init(-2, 1334, DEF_FRAC_DIGITS)
	fmt.println("[init] 2.1334 =", to_string(b, context.temp_allocator))
}

