package fixed_ex

import "core:math/fixed"

equal :: proc {
	_equal,
	array_equal,
}

_equal :: proc "contextless" (a:$T/fixed.Fixed($Backing, $Fraction_Width), b:T) -> bool {
	return a.i == b.i
}

array_equal :: proc "contextless" (a:$T/[$N]fixed.Fixed($Backing, $Fraction_Width), b:T) -> bool {
	#unroll for i in 0..<N {
		if a[i].i != b[i].i do return false
	}
	return true
}


// Flip the sign (positive ↔ negative)
@(require_results)
sign :: #force_inline proc "contextless" (v: $T/fixed.Fixed($Backing, $Fraction_Width)) -> (r: T) {
	r.i = -r.i
	return
}

// [2]FixedDef vector difference
@(require_results)
sub2 :: #force_inline proc "contextless" (a, b: [2]$T/fixed.Fixed($Backing, $Fraction_Width)) -> [2]T {
    return {fixed.sub(a.x, b.x), fixed.sub(a.y, b.y)}
}

// squared length (x*x + y*y), fixed-Vector2f32
@(require_results)
length2 :: #force_inline proc "contextless" (v: [2]$T/fixed.Fixed($Backing, $Fraction_Width)) -> T {
    return fixed.add(fixed.mul(v.x, v.x), fixed.mul(v.y, v.y))
}