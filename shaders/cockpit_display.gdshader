shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 tint : source_color = vec3(0.15, 0.7, 0.85);
uniform float power = 0.3;
uniform float panel_kind = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float grid = step(0.96, fract(UV.x * 16.0)) + step(0.96, fract(UV.y * 8.0));
	float ring = 1.0 - smoothstep(0.008, 0.025, abs(length(p * vec2(1.0, 0.62)) - 0.46));
	float horizon = 1.0 - smoothstep(0.005, 0.017, abs(p.y - sin(TIME * 0.25 + p.x) * 0.07));
	float cross = (1.0 - smoothstep(0.007, 0.017, abs(p.x))) * step(abs(p.y), 0.12);
	float readout = step(0.20, UV.x) * step(UV.x, 0.82) * step(0.88, fract(UV.y * 7.0));
	readout *= step(UV.x, 0.3 + fract(floor(UV.y * 7.0) * 0.618 + power * 0.05) * 0.5);
	float detail = mix(ring + horizon + cross, readout, step(0.5, panel_kind));
	ALBEDO = vec3(0.008, 0.018, 0.026) + tint * (grid * 0.045 + detail * 0.7);
	EMISSION = tint * detail * 0.35;
}
