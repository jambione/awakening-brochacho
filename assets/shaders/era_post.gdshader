// era_post.gdshader — full-screen post-process for the evolving-era visual system.
//
// Applied via EraManager on a full-screen ColorRect in a high CanvasLayer.
// Each uniform is tweened by EraManager when the era advances.
//
// Pipeline per fragment:
//   1. Pixelation  — snap UV to blocks of pixel_size screen pixels
//   2. Dither      — 2×2 ordered dither offsets colour before quantisation
//   3. Quantise    — nearest-palette-entry colour reduction
//   4. Scanlines   — darken every other row
//   5. Flicker     — Atari-style per-frame brightness noise

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform int   pixel_size         : hint_range(1, 8)    = 1;
uniform int   palette_size       : hint_range(2, 32)   = 4;
uniform vec4  palette[32];
uniform float quantize_strength  : hint_range(0.0, 1.0) = 1.0;
uniform float dither_strength    : hint_range(0.0, 1.0) = 0.0;
uniform float scanline_strength  : hint_range(0.0, 1.0) = 0.0;
uniform float flicker_strength   : hint_range(0.0, 1.0) = 0.0;
uniform float time_val           = 0.0;

// 2×2 Bayer ordered dither — returns offset in [-0.5, 0.25].
float dither2x2(vec2 p) {
	int x = int(mod(p.x, 2.0));
	int y = int(mod(p.y, 2.0));
	if (x == 0 && y == 0) return -0.50;
	if (x == 1 && y == 0) return  0.00;
	if (x == 0 && y == 1) return  0.25;
	return -0.25;
}

// Find the nearest colour in the active palette.
vec3 nearest_palette(vec3 col) {
	float best_dist = 1e6;
	vec3  best_col  = palette[0].rgb;
	for (int i = 0; i < palette_size; i++) {
		vec3  d    = col - palette[i].rgb;
		float dist = dot(d, d);
		if (dist < best_dist) {
			best_dist = dist;
			best_col  = palette[i].rgb;
		}
	}
	return best_col;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// --- Pixelation: snap to blocks of pixel_size screen pixels ---
	if (pixel_size > 1) {
		vec2  sz = vec2(textureSize(screen_texture, 0));
		float ps = float(pixel_size);
		uv = (floor(uv * sz / ps) * ps + ps * 0.5) / sz;
	}

	vec4 col = texture(screen_texture, uv);

	// --- Ordered dither (before quantisation so edges blend between entries) ---
	if (dither_strength > 0.0) {
		col.rgb += vec3(dither2x2(FRAGCOORD.xy) * dither_strength * 0.35);
		col.rgb  = clamp(col.rgb, 0.0, 1.0);
	}

	// --- Palette quantisation ---
	if (quantize_strength > 0.0) {
		vec3 q  = nearest_palette(col.rgb);
		col.rgb = mix(col.rgb, q, quantize_strength);
	}

	// --- Scanlines: darken every other row ---
	if (scanline_strength > 0.0) {
		float dark = mod(floor(FRAGCOORD.y), 2.0);
		col.rgb *= 1.0 - dark * scanline_strength * 0.45;
	}

	// --- Atari-style per-frame brightness flicker ---
	if (flicker_strength > 0.0) {
		float f = sin(time_val * 47.0) * 0.5 + 0.5;
		col.rgb *= 1.0 - flicker_strength * 0.2 * f;
	}

	COLOR = col;
}
