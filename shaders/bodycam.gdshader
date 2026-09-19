shader_type canvas_item;
render_mode unshaded;

// Bodycam / Unrecord-like post processing applied to the 3D frame.
//
// The 3D world is rendered into a SubViewport and this shader runs on the
// SubViewportContainer, so TEXTURE is the rendered frame. That works on the
// Compatibility (GLES3) renderer used on low-end Android GPUs, unlike
// hint_screen_texture, which is not supported there.
//
// Effects: fisheye (wide angle bulge), chromatic aberration, sensor grain,
// scanlines, rolling shutter bar, horizontal tear glitches, exposure wobble,
// desaturation and a heavy vignette.

uniform sampler2D grain_tex : filter_linear, repeat_enable;

uniform float fisheye : hint_range(0.0, 0.6) = 0.26;
uniform float chroma : hint_range(0.0, 0.02) = 0.0035;
uniform float noise_amount : hint_range(0.0, 0.5) = 0.07;
uniform float scanline_amount : hint_range(0.0, 0.5) = 0.05;
uniform float vignette_amount : hint_range(0.0, 2.0) = 1.0;
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.22;
uniform float shake : hint_range(0.0, 2.0) = 0.0;
uniform float exposure : hint_range(0.5, 2.0) = 1.06;
uniform float saturation : hint_range(0.0, 2.0) = 0.9;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Wide-angle bulge. The sample point is pulled towards the centre, so the UV
// always stays inside the frame and no black corners can appear.
vec2 fisheye_uv(vec2 uv, float k) {
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	c *= 1.0 - k * r2 - k * 0.25 * r2 * r2;
	return c + 0.5;
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;

	// --- horizontal tear lines (digital artefacts) ---
	float band = floor(uv.y * 110.0);
	float tear = step(0.994, hash12(vec2(band, floor(t * 10.0))));
	uv.x += tear * glitch_amount * 0.03 * (hash12(vec2(band, floor(t * 10.0) + 1.0)) - 0.5);

	// --- lens + handheld micro shake ---
	uv = fisheye_uv(uv, fisheye);
	uv += vec2(sin(t * 33.0), cos(t * 27.0)) * 0.0022 * shake;
	uv = clamp(uv, vec2(0.0015), vec2(0.9985));

	// --- chromatic aberration, stronger towards the edges ---
	vec2 dir = uv - 0.5;
	float edge = length(dir);
	float ca = chroma * (0.35 + edge * 2.6);
	vec3 col;
	col.r = texture(TEXTURE, clamp(uv + dir * ca, vec2(0.0), vec2(1.0))).r;
	col.g = texture(TEXTURE, uv).g;
	col.b = texture(TEXTURE, clamp(uv - dir * ca, vec2(0.0), vec2(1.0))).b;

	// --- sensor grain from the generated noise texture (cheap, no per-pixel rng) ---
	vec2 gu = uv * vec2(4.0, 2.5) + vec2(fract(t * 7.0), fract(t * 5.0));
	float g = texture(grain_tex, gu).r - 0.5;
	col += g * noise_amount * (1.0 + shake);

	// --- scanlines + rolling shutter bar ---
	float scan = sin(uv.y * 520.0) * 0.5 + 0.5;
	col *= 1.0 - scanline_amount * scan;
	float roll = smoothstep(0.0, 0.09, abs(fract(uv.y - t * 0.13) - 0.5));
	col *= 0.93 + 0.07 * roll;

	// --- block glitch flash on strong shake ---
	float blk = step(0.9975, hash12(vec2(floor(uv.y * 40.0), floor(t * 6.0))));
	col += blk * glitch_amount * 0.25 * shake;

	// --- exposure wobble, grade, warm tungsten tint ---
	col *= exposure * (1.0 + 0.025 * sin(t * 1.7) + 0.05 * shake);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	col = mix(col, col * vec3(1.04, 1.0, 0.95), 0.6);

	// --- vignette ---
	float vig = smoothstep(0.85, 0.22, edge * vignette_amount);
	col *= mix(0.3, 1.0, vig);

	COLOR = vec4(col, 1.0);
}
