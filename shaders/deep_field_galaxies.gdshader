shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// GPU DEEP COSMOLOGICAL GALAXY FIELD SHADER
// 180.000 LY ila 60.000.000 LY mesafedeki on binlerce galaksiyi GPU üzerinde
// sıfır CPU yüküyle, gerçek 3D paralaks ve dinamik açısal LOD ile çizer.
// Uzaktayken noktasal parlama; yaklaşıldıkça orantılı olarak büyüyen sarmal kollar.
// ─────────────────────────────────────────────────────────────────────────────

uniform vec3 u_observer_pos_ly = vec3(0.0);
uniform vec3 u_anchor_pos_ly = vec3(0.0);
uniform float u_render_dist_min = 35000.0;
uniform float u_render_dist_max = 240000.0;
uniform float u_galaxy_pixel_size : hint_range(0.5, 8.0) = 2.4;
uniform float u_layer_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float u_brightness_boost : hint_range(0.5, 4.0) = 1.6;

varying vec4 v_color;
varying float v_morph_type;
varying float v_lod_ratio;
varying float v_dist_fade;

void vertex() {
	vec2 quad_uv_offset = VERTEX.xy;
	
	// MultiMesh INSTANCE_CUSTOM:
	// xyz = Galaksinin deterministik mantıksal koordinatı (Işık Yılı)
	// w   = Morfoloji ve göreceli çap faktörü
	vec3 gal_local_ly = INSTANCE_CUSTOM.xyz;
	float gal_param = INSTANCE_CUSTOM.w;
	v_morph_type = floor(gal_param);
	
	// Galaksinin astrofiziksel yarıçapı (25.000 LY ila 120.000 LY)
	float size_norm = clamp(fract(gal_param) * 10.0, 0.15, 1.2);
	float gal_radius_ly = size_norm * 90000.0;
	
	// Gözlemcinin mutlak kozmik konumuna göre bağıl vektör
	vec3 rel_gal_ly = (u_anchor_pos_ly + gal_local_ly) - u_observer_pos_ly;
	float dist_ly = length(rel_gal_ly);
	vec3 dir = rel_gal_ly / max(dist_ly, 0.0001);
	
	// Kozmik mesafe sönümlemesi (aşırı uzaklarda 55M LY'de söner)
	v_dist_fade = 1.0 - smoothstep(45000000.0, 60000000.0, dist_ly);
	
	// Mantıksal mesafeyi logaritmik olarak güvenli render kabuğuna eşle (35k - 240k birim)
	float t_dist = clamp((dist_ly - 30000.0) / (60000000.0 - 30000.0), 0.0, 1.0);
	float depth_curve = pow(t_dist, 0.38);
	float render_dist = mix(u_render_dist_min, u_render_dist_max, depth_curve);
	
	// AÇISAL ÇÖZÜNÜRLÜK VE YAKLAŞTIKÇA BÜYÜME (LOD):
	// Yaklaştıkça galaksi gerçek açısal boyutuna göre devasa sarmal bir diske dönüşür!
	float angular_rad = gal_radius_ly / max(dist_ly, gal_radius_ly * 0.75);
	float visual_scale = render_dist * angular_rad;
	float min_pixel_scale = render_dist * 0.00125 * u_galaxy_pixel_size;
	if (v_morph_type > 0.5 && v_morph_type < 1.5) {
		min_pixel_scale *= 1.25;
	}
	float final_scale = clamp(max(visual_scale, min_pixel_scale), min_pixel_scale, render_dist * 0.45);
	
	// Çözünürlük LOD faktörü:
	// 0.0 = Uzak noktasal iğne ucu (PSF), 1.0 = Yakında tam çözünmüş sarmal kollar ve detay
	v_lod_ratio = clamp((visual_scale - min_pixel_scale) / max(min_pixel_scale * 1.5, 0.001), 0.0, 1.0);
	
	// Kameraya bakan küresel billboard
	vec3 right_world = INV_VIEW_MATRIX[0].xyz;
	vec3 up_world = INV_VIEW_MATRIX[1].xyz;
	vec3 billboard_offset = (right_world * quad_uv_offset.x + up_world * quad_uv_offset.y) * final_scale;
	
	VERTEX = dir * render_dist + billboard_offset;
	
	// Derin uzay parlaklık ve kontrast ayarı
	float depth_attenuation = mix(1.0, 0.40, depth_curve);
	v_color = vec4(COLOR.rgb * depth_attenuation, COLOR.a * v_dist_fade * u_layer_opacity);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r_sq = dot(uv, uv);
	if (r_sq > 1.0) {
		discard;
	}
	float r = sqrt(r_sq);
	
	float intensity = 0.0;
	vec3 tint = v_color.rgb;
	
	if (v_morph_type < 0.5) {
		// SARMAL GALAKSİ (Spiral: Sa, Sb, Sc)
		float core = exp(-r * 7.5) * 1.6;
		float angle = atan(uv.y, uv.x);
		float arms = cos(2.0 * angle - 3.8 * log(r + 0.035));
		float arm_glow = smoothstep(0.08, 0.78, arms) * exp(-r * 2.5) * 1.3;
		float dust = smoothstep(-0.4, 0.1, arms) * smoothstep(0.04, 0.35, r);
		intensity = core + arm_glow * dust;
		tint = mix(vec3(1.0, 0.90, 0.70), tint, smoothstep(0.08, 0.45, r));
	} else if (v_morph_type < 1.5) {
		// ELİPTİK GALAKSİ (Elliptical)
		float profile = exp(-3.2 * pow(r, 0.40));
		intensity = profile * 1.9;
		tint = mix(tint, vec3(1.0, 0.84, 0.58), 0.5);
	} else if (v_morph_type < 2.5) {
		// DÜZENSİZ GALAKSİ (Irregular)
		float clumpy = exp(-r * 3.2) * (0.85 + 0.35 * sin(uv.x * 8.0 + uv.y * 5.0));
		intensity = clumpy * 1.45;
	} else {
		// MERCEKSİ GALAKSİ (Lenticular)
		float core = exp(-r * 7.0) * 1.6;
		float disk = exp(-r * 2.8) * 0.65;
		intensity = core + disk;
	}
	
	// Noktasal ışıma (PSF)
	float psf = exp(-r_sq * 12.0) * 1.5 + exp(-r * 4.5) * 0.4;
	
	// LOD geçişi: Uzakta noktasal parıltı, yaklaştıkça tam çözünmüş sarmal disk
	float resolve_curve = smoothstep(0.05, 0.45, v_lod_ratio);
	float final_intensity = mix(psf, intensity, resolve_curve) * u_brightness_boost;
	
	// Dış kenar yumuşatma
	float edge = smoothstep(1.0, 0.55, r);
	
	// HDR sıkıştırması
	float tonemapped = final_intensity / (1.0 + final_intensity * 0.25);
	
	ALBEDO = tint * tonemapped * edge;
	ALPHA = clamp(v_color.a * edge * tonemapped, 0.0, 1.0);
}
