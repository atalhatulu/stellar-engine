shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// 3D VOLUMETRIC PROCEDURAL NEBULA SHADER (No Man's Sky Tarzı Renk Cümbüşü)
// ─────────────────────────────────────────────────────────────────────────────

uniform vec3 nebula_tint_core : source_color = vec3(0.9, 0.3, 0.95); // İç çekirdek parlak tonu
uniform vec3 nebula_tint_edge : source_color = vec3(0.15, 0.5, 0.9);  // Dış gaz tülü zıt tonu
uniform float density : hint_range(0.1, 5.0) = 1.3;
uniform float noise_scale : hint_range(0.1, 10.0) = 1.6;
uniform float softness : hint_range(0.1, 2.0) = 0.9;
uniform float alpha_fade : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_coord;

// Hızlı 3D Hash
vec3 hash33(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
}

// 3D Gradyan Gürültüsü
float noise3d(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	
	return mix(
		mix(
			mix(dot(hash33(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0)),
			    dot(hash33(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0)), u.x),
			mix(dot(hash33(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0)),
			    dot(hash33(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0)), u.x), u.y),
		mix(
			mix(dot(hash33(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0)),
			    dot(hash33(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0)), u.x),
			mix(dot(hash33(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0)),
			    dot(hash33(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// 3 Katmanlı FBM Fraktal
float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.55;
	float freq = 1.0;
	for (int i = 0; i < 3; i++) {
		total += noise3d(p * freq) * amp;
		freq *= 2.1;
		amp *= 0.45;
	}
	return total;
}

void vertex() {
	// MultiMesh Küresel Billboard (Spherical Billboard): Her duman parçası her açıdan kameraya döner
	mat4 mat_world = MODEL_MATRIX;
	vec3 scale = vec3(
		length(mat_world[0].xyz),
		length(mat_world[1].xyz),
		length(mat_world[2].xyz)
	);
	
	mat4 mat_rot = mat4(
		INV_VIEW_MATRIX[0] * scale.x,
		INV_VIEW_MATRIX[1] * scale.y,
		INV_VIEW_MATRIX[2] * scale.z,
		mat_world[3]
	);
	
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_rot;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_coord = (mat_world * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 2D UV'den radyal dairesel yumuşatma maskesi
	vec2 center_rel = UV - vec2(0.5);
	float dist_sq = dot(center_rel, center_rel) * 4.0;
	if (dist_sq > 1.0) {
		discard;
	}
	
	// Küresel hacim yumuşatması
	float radial_fade = smoothstep(1.0, 0.0, dist_sq);
	
	// Örnekleme konumu (world_coord ve UV)
	vec3 sample_pos = (world_coord * 0.00001 + vec3(center_rel * 2.0, 0.0)) * noise_scale;
	
	float n = fbm(sample_pos + vec3(1.2, 3.4, 5.6));
	float gas = smoothstep(-0.25, 0.55, n) * radial_fade * density;
	
	// No Man's Sky Çift-Ton Renk Gradyanı: İç çekirdek ile dış gaz kollarını kaynaştır
	float core_weight = pow(radial_fade, 1.4);
	vec3 dual_tint = mix(nebula_tint_edge, nebula_tint_core, core_weight);
	vec3 col = COLOR.rgb * dual_tint;
	
	// Kamera yakınlık yumuşatması (Near clipping engelleme)
	float cam_dist = length(VERTEX);
	float near_fade = smoothstep(5.0, 40.0, cam_dist);
	
	ALBEDO = col * gas * 2.4;
	ALPHA = clamp(gas * near_fade * COLOR.a * alpha_fade, 0.0, 1.0);
}
