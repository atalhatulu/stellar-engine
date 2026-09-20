shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// ACCRETION DISK SHADER (GERÇEKÇİ / SÖNDÜRÜLMÜŞ)
// Şatafatı azaltılmış, fiziksel olarak dengeli akresyon diski
// ─────────────────────────────────────────────────────────────────────────────

uniform vec4 u_inner_color : source_color = vec4(1.3, 1.1, 0.85, 0.9); // Yumuşak akkor altın
uniform vec4 u_mid_color   : source_color = vec4(1.1, 0.5, 0.2, 0.7);  // Doğal turuncu gaz
uniform vec4 u_outer_color : source_color = vec4(0.6, 0.15, 0.08, 0.3); // Koyu kızıl toz sınırı
uniform float u_inner_radius = 0.22;
uniform float u_outer_radius = 0.96;
uniform float u_spin_speed = 0.35;
uniform float u_doppler_intensity = 0.45; // Relativistik Doppler asimetrisi
uniform float u_brightness = 0.85; // Söndürülmüş genel parlaklık

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 4; ++i) {
		v += a * noise(p);
		p = rot * p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float dist = length(uv);
	
	if (dist < u_inner_radius || dist > u_outer_radius) {
		discard;
	}
	
	float angle = atan(uv.y, uv.x);
	float kepler_speed = u_spin_speed * pow(u_inner_radius / max(dist, 0.01), 1.25);
	float anim_angle = angle - TIME * kepler_speed;
	
	vec2 polar_uv = vec2(dist * 7.0, anim_angle * 3.0);
	float gas = fbm(polar_uv);
	gas = smoothstep(0.2, 0.8, gas);
	
	float t = clamp((dist - u_inner_radius) / (u_outer_radius - u_inner_radius), 0.0, 1.0);
	vec4 base_color = mix(u_inner_color, u_mid_color, smoothstep(0.0, 0.4, t));
	base_color = mix(base_color, u_outer_color, smoothstep(0.4, 1.0, t));
	
	float doppler = 1.0 + (uv.x / max(dist, 0.01)) * u_doppler_intensity;
	
	float edge_fade = smoothstep(u_inner_radius, u_inner_radius + 0.05, dist)
	                * (1.0 - smoothstep(u_outer_radius - 0.12, u_outer_radius, dist));
	
	vec3 final_rgb = base_color.rgb * (0.6 + 0.6 * gas) * doppler * u_brightness;
	float final_alpha = base_color.a * edge_fade * (0.5 + 0.5 * gas);
	
	ALBEDO = final_rgb * final_alpha;
}
