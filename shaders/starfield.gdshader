shader_type sky;

// No Man's Sky Tarzı Prosedürel Nebula ve Kozmik Uzay Gökyüzü Shader'ı
uniform vec3 deep_space_color : source_color = vec3(0.012, 0.010, 0.024);
uniform vec3 nebula_color_purple : source_color = vec3(0.18, 0.05, 0.28);
uniform vec3 nebula_color_teal : source_color = vec3(0.02, 0.16, 0.24);
uniform vec3 nebula_color_gold : source_color = vec3(0.28, 0.12, 0.04);
uniform float nebula_density : hint_range(0.0, 2.0) = 1.0;

// Hızlı ve dengeli 3D hash fonksiyonu
vec3 hash33(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return -1.0 + 2.0 * fract((p.xxy + p.yxx) * p.zyx);
}

// 3D Gradyan Gürültüsü (Simplex benzeri yumuşak geçiş)
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

// 4 Katmanlı FBM (Fractal Brownian Motion)
float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	for (int i = 0; i < 4; i++) {
		total += noise3d(p * frequency) * amplitude;
		frequency *= 2.15;
		amplitude *= 0.48;
	}
	return total;
}

// Hızlı mikro yıldız katmanı üretici
float star_layer(vec3 dir, float cell_size, float threshold) {
	vec3 p = dir * cell_size;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	
	vec3 h = hash33(id);
	float star_rand = h.x * 0.5 + 0.5;
	if (star_rand > threshold) {
		vec3 center = (h - 0.5) * 0.45;
		float d = length(f - center);
		float size = 0.09 * (star_rand - threshold) / (1.0 - threshold);
		return smoothstep(size, 0.0, d);
	}
	return 0.0;
}

void sky() {
	vec3 dir = EYEDIR;
	float tilt = 0.35;
	vec3 rotated = dir;
	rotated.yz = mat2(vec2(cos(tilt), -sin(tilt)), vec2(sin(tilt), cos(tilt))) * dir.yz;
	
	// Galaktik Samanyolu Diski ve Toz Şeritleri
	float band = exp(-pow(abs(rotated.y) / 0.16, 2.0));
	float structure = fbm(rotated * 4.5);
	float dust = smoothstep(-0.1, 0.25, fbm(rotated * 12.0));
	float core = pow(max(dot(rotated, normalize(vec3(0.6, 0.0, -0.8))), 0.0), 10.0);
	
	// Galaksi çekirdeği ve spiral kol ışıması (Sadece kozmik arka plan tozu)
	vec3 starlight = mix(vec3(0.035, 0.045, 0.06), vec3(0.10, 0.075, 0.05), core);
	vec3 galactic_disc = starlight * band * (0.35 + structure * 0.75) * (1.0 - dust * 0.7);
	
	COLOR = vec3(0.0005, 0.0010, 0.0018) + galactic_disc * 0.12;
}

