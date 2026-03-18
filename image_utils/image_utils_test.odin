#+private
package image_utils

import "core:mem"
import "core:testing"

// Fills one pixel in the given format (8-bit 4 channels). Used to build test input.
_make_pixel_4 :: proc(fmt: color_fmt, r, g, b, a: u8) -> [4]byte {
	#partial switch fmt {
	case .RGBA:
		return [4]byte{r, g, b, a}
	case .BGRA:
		return [4]byte{b, g, r, a}
	case .ARGB:
		return [4]byte{a, r, g, b}
	case .ABGR:
		return [4]byte{a, b, g, r}
	case:
		return [4]byte{}
	}
}

_make_pixel_3 :: proc(fmt: color_fmt, r, g, b: u8) -> [3]byte {
	#partial switch fmt {
	case .RGB:
		return [3]byte{r, g, b}
	case .BGR:
		return [3]byte{b, g, r}
	case:
		return [3]byte{}
	}
}

_make_pixel_8 :: proc(fmt: color_fmt, r, g, b, a: u16) -> [8]byte {
	rh, rl := u8(r >> 8), u8(r & 0xFF)
	gh, gl := u8(g >> 8), u8(g & 0xFF)
	bh, bl := u8(b >> 8), u8(b & 0xFF)
	ah, al := u8(a >> 8), u8(a & 0xFF)
	#partial switch fmt {
	case .RGBA16:
		return [8]byte{rl, rh, gl, gh, bl, bh, al, ah}
	case .BGRA16:
		return [8]byte{bl, bh, gl, gh, rl, rh, al, ah}
	case .ARGB16:
		return [8]byte{al, ah, rl, rh, gl, gh, bl, bh}
	case .ABGR16:
		return [8]byte{al, ah, bl, bh, gl, gh, rl, rh}
	case:
		return [8]byte{}
	}
}

_make_pixel_6 :: proc(fmt: color_fmt, r, g, b: u16) -> [6]byte {
	rl, rh := u8(r & 0xFF), u8(r >> 8)
	gl, gh := u8(g & 0xFF), u8(g >> 8)
	bl, bh := u8(b & 0xFF), u8(b >> 8)
	#partial switch fmt {
	case .RGB16:
		return [6]byte{rl, rh, gl, gh, bl, bh}
	case .BGR16:
		return [6]byte{bl, bh, gl, gh, rl, rh}
	case:
		return [6]byte{}
	}
}

_make_pixel_12 :: proc(fmt: color_fmt, r, g, b: u32) -> [12]byte {
	r0, r1, r2, r3 := u8(r), u8(r >> 8), u8(r >> 16), u8(r >> 24)
	g0, g1, g2, g3 := u8(g), u8(g >> 8), u8(g >> 16), u8(g >> 24)
	b0, b1, b2, b3 := u8(b), u8(b >> 8), u8(b >> 16), u8(b >> 24)
	#partial switch fmt {
	case .RGB32, .RGB32F:
		return [12]byte{r0, r1, r2, r3, g0, g1, g2, g3, b0, b1, b2, b3}
	case .BGR32, .BGR32F:
		return [12]byte{b0, b1, b2, b3, g0, g1, g2, g3, r0, r1, r2, r3}
	case:
		return [12]byte{}
	}
}

_make_pixel_16 :: proc(fmt: color_fmt, r, g, b, a: u32) -> [16]byte {
	r0, r1, r2, r3 := u8(r), u8(r >> 8), u8(r >> 16), u8(r >> 24)
	g0, g1, g2, g3 := u8(g), u8(g >> 8), u8(g >> 16), u8(g >> 24)
	b0, b1, b2, b3 := u8(b), u8(b >> 8), u8(b >> 16), u8(b >> 24)
	a0, a1, a2, a3 := u8(a), u8(a >> 8), u8(a >> 16), u8(a >> 24)
	#partial switch fmt {
	case .RGBA32, .RGBA32F:
		return [16]byte{r0, r1, r2, r3, g0, g1, g2, g3, b0, b1, b2, b3, a0, a1, a2, a3}
	case .BGRA32, .BGRA32F:
		return [16]byte{b0, b1, b2, b3, g0, g1, g2, g3, r0, r1, r2, r3, a0, a1, a2, a3}
	case .ARGB32, .ARGB32F:
		return [16]byte{a0, a1, a2, a3, r0, r1, r2, r3, g0, g1, g2, g3, b0, b1, b2, b3}
	case .ABGR32, .ABGR32F:
		return [16]byte{a0, a1, a2, a3, b0, b1, b2, b3, g0, g1, g2, g3, r0, r1, r2, r3}
	case:
		return [16]byte{}
	}
}

_formats_4 :: []color_fmt{.RGBA, .BGRA, .ARGB, .ABGR}
_formats_3 :: []color_fmt{.RGB, .BGR}
_formats_8 :: []color_fmt{.RGBA16, .BGRA16, .ARGB16, .ABGR16}
_formats_6 :: []color_fmt{.RGB16, .BGR16}
_formats_12 :: []color_fmt{.RGB32, .BGR32, .RGB32F, .BGR32F}
_formats_16 :: []color_fmt {
	.RGBA32,
	.BGRA32,
	.ARGB32,
	.ABGR32,
	.RGBA32F,
	.BGRA32F,
	.ARGB32F,
	.ABGR32F,
}

// RGBA/BGRA/ARGB/ABGR (4<->4) conversion and round-trip byte equality.
@(test)
test_color_fmt_convert_4_to_4 :: proc(t: ^testing.T) {
	r, g, b, a: u8 = 0x11, 0x22, 0x33, 0x44
	for in_fmt in _formats_4 {
		for out_fmt in _formats_4 {
			if in_fmt == out_fmt do continue
			pix := _make_pixel_4(in_fmt, r, g, b, a)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 4)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// RGB/BGR (3<->3) conversion and round-trip.
@(test)
test_color_fmt_convert_3_to_3 :: proc(t: ^testing.T) {
	r, g, b: u8 = 0x11, 0x22, 0x33
	for in_fmt in _formats_3 {
		for out_fmt in _formats_3 {
			if in_fmt == out_fmt do continue
			pix := _make_pixel_3(in_fmt, r, g, b)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 3)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 4-channel -> 3-channel -> 4-channel; full alpha so round-trip must be byte-identical.
@(test)
test_color_fmt_convert_4_to_3_and_back :: proc(t: ^testing.T) {
	r, g, b: u8 = 0x11, 0x22, 0x33
	a: u8 = 255 // full alpha so re-added alpha matches
	for in_fmt in _formats_4 {
		for out_fmt in _formats_3 {
			pix := _make_pixel_4(in_fmt, r, g, b, a)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 3)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 3-channel -> 4-channel -> 3-channel; round-trip byte equality.
@(test)
test_color_fmt_convert_3_to_4_and_back :: proc(t: ^testing.T) {
	r, g, b: u8 = 0x11, 0x22, 0x33
	for in_fmt in _formats_3 {
		for out_fmt in _formats_4 {
			pix := _make_pixel_3(in_fmt, r, g, b)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 4)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 16-bit 4-channel (RGBA16/BGRA16/ARGB16/ABGR16) conversion and round-trip.
@(test)
test_color_fmt_convert_8_to_8 :: proc(t: ^testing.T) {
	r, g, b, a: u16 = 0x1111, 0x2222, 0x3333, 0x4444
	for in_fmt in _formats_8 {
		for out_fmt in _formats_8 {
			if in_fmt == out_fmt do continue
			pix := _make_pixel_8(in_fmt, r, g, b, a)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 8)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 16-bit 3-channel (RGB16/BGR16) conversion and round-trip.
@(test)
test_color_fmt_convert_6_to_6 :: proc(t: ^testing.T) {
	r, g, b: u16 = 0x1111, 0x2222, 0x3333
	for in_fmt in _formats_6 {
		for out_fmt in _formats_6 {
			if in_fmt == out_fmt do continue
			pix := _make_pixel_6(in_fmt, r, g, b)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 6)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 8-byte -> 6-byte -> 8-byte; full alpha so round-trip must be byte-identical.
@(test)
test_color_fmt_convert_8_to_6_and_back :: proc(t: ^testing.T) {
	r, g, b: u16 = 0x1111, 0x2222, 0x3333
	a: u16 = 0xFFFF // full alpha so re-added alpha matches
	for in_fmt in _formats_8 {
		for out_fmt in _formats_6 {
			pix := _make_pixel_8(in_fmt, r, g, b, a)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 6)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 6-byte -> 8-byte -> 6-byte; round-trip byte equality.
@(test)
test_color_fmt_convert_6_to_8_and_back :: proc(t: ^testing.T) {
	r, g, b: u16 = 0x1111, 0x2222, 0x3333
	for in_fmt in _formats_6 {
		for out_fmt in _formats_8 {
			pix := _make_pixel_6(in_fmt, r, g, b)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 8)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 32-bit 3-channel (RGB32/BGR32/32F) conversion and round-trip.
@(test)
test_color_fmt_convert_12_to_12 :: proc(t: ^testing.T) {
	r, g, b: u32 = 0x11111111, 0x22222222, 0x33333333
	for in_fmt in _formats_12 {
		for out_fmt in _formats_12 {
			if in_fmt == out_fmt do continue
			pix := _make_pixel_12(in_fmt, r, g, b)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 12)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 32-bit 4-channel (RGBA32/BGRA32/ARGB32/ABGR32 and 32F) conversion and round-trip.
@(test)
test_color_fmt_convert_16_to_16 :: proc(t: ^testing.T) {
	r, g, b, a: u32 = 0x11111111, 0x22222222, 0x33333333, 0x44444444
	for in_fmt in _formats_16 {
		for out_fmt in _formats_16 {
			if in_fmt == out_fmt do continue
			pix := _make_pixel_16(in_fmt, r, g, b, a)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 16)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 16-byte -> 12-byte -> 16-byte; full alpha so round-trip must be byte-identical.
@(test)
test_color_fmt_convert_16_to_12_and_back :: proc(t: ^testing.T) {
	r, g, b: u32 = 0x11111111, 0x22222222, 0x33333333
	for in_fmt in _formats_16 {
		// Integer formats use 0xFFFFFFFF for alpha; 32F use 1.0f (0x3F800000) to match re-added alpha
		is_32f :=
			in_fmt == .RGBA32F || in_fmt == .BGRA32F || in_fmt == .ARGB32F || in_fmt == .ABGR32F
		a: u32 = 0x3F800000 if is_32f else 0xFFFFFFFF
		for out_fmt in _formats_12 {
			pix := _make_pixel_16(in_fmt, r, g, b, a)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 12)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				testing.expect_value(t, mem.compare(back, pixels), 0)
			}
		}
	}
}

// 12-byte -> 16-byte -> 12-byte; round-trip byte equality for RGB (back[:12] vs pixels).
@(test)
test_color_fmt_convert_12_to_16_and_back :: proc(t: ^testing.T) {
	r, g, b: u32 = 0x11111111, 0x22222222, 0x33333333
	for in_fmt in _formats_12 {
		for out_fmt in _formats_16 {
			pix := _make_pixel_12(in_fmt, r, g, b)
			pixels := pix[:]
			result := color_fmt_convert(pixels, in_fmt, out_fmt)
			testing.expect(t, result != nil)
			if result == nil do continue
			defer delete(result)
			testing.expect_value(t, len(result), 16)

			back := color_fmt_convert(result, out_fmt, in_fmt)
			testing.expect(t, back != nil)
			if back != nil {
				defer delete(back)
				// back is 16 bytes (with added alpha), pixels is 12; compare RGB only
				testing.expect_value(t, mem.compare(back[:12], pixels), 0)
			}
		}
	}
}

// Unknown/Gray, empty input, unsupported bpp pair: must return nil.
@(test)
test_color_fmt_convert_nil_cases :: proc(t: ^testing.T) {
	pixels: [4]byte = {0x11, 0x22, 0x33, 0x44}
	testing.expect(t, color_fmt_convert(pixels[:], .Unknown, .RGBA) == nil)
	testing.expect(t, color_fmt_convert(pixels[:], .RGBA, .RGBA) == nil) // same
	testing.expect(t, color_fmt_convert(pixels[:], .RGBA, .Unknown) == nil)
	testing.expect(t, color_fmt_convert(pixels[:], .Gray, .RGBA) == nil) // gray not supported
	testing.expect(t, color_fmt_convert(pixels[:], .RGBA, .Gray) == nil)
	testing.expect(t, color_fmt_convert(pixels[:], .RGBA, .RGBA16) == nil) // 4 vs 8 bpp not supported
	testing.expect(t, color_fmt_convert([]byte{}, .RGBA, .BGRA) == nil) // empty
}
