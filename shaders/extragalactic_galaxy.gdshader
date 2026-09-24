shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// EXTRAGALACTIC GALAXY BILLBOARD / IMPOSTOR SHADER
// Kozmolojik ölçekte (yüz binlerce ila milyonlarca Işık Yılı) serpiştirilmiş
// derin uzay galaksilerini prosedürel Hubble morfolojisiyle çizer.
// Sarmal kolları, karanlık toz şeritlerini ve parlak çekirdekleri beyaz
// patlamaya (blowout) uğratmadan net bir kontrastla sunar.
// ─────────────────────────────────────────────────────────────────────────────

uniform float u_brightness_boost : hint_range(0.5, 5.0) = 1.85;
uniform float u_min_pixel_size : hint_range(1.0, 30.0) = 3.5;

varying vec4 v_tint_color;
varying float v_morphology;
varying float v_arm_param;
varying float v_num_arms;
varying float v_angular_ratio;
varying float v_apparent_flux;
varying float v_inclination_ratio;

void vertex() {
	v_tint_color = COLOR;
	
	// INSTANCE_CUSTOM:
	// x: Galaksi yarıçapı (LY)
	// y: Morfoloji tipi (0 = Sarmal, 1 = Eliptik, 2 = Düzensiz, 3 = Merceksi)
	// z: Kol sıkılığı / Basıklık
	// w: Kol sayısı / Eksenel asimetri
	float gal_radius_ly = INSTANCE_CUSTOM.x;
	v_morphology = INSTANCE_CUSTOM.y;
	v_arm_param = INSTANCE_CUSTOM.z;
	v_num_arms = INSTANCE_CUSTOM.w;
	
	// Kamera uzayında merkez ve mesafe
	vec3 view_center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_dist = max(length(view_center), 1.0);
	
	float min_size_ly = cam_dist * (u_min_pixel_size * 0.0006);
	float final_radius = max(gal_radius_ly, min_size_ly * 0.5);
	vec3 view_direction = normalize(-view_center);
	vec3 disk_normal_view = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	// Gerçek disk yöneliminden görünen basıklığı çıkar. Geometri kameraya dönük
	// kalırken şekil yüz yüze bakışta daire, kenar bakışta ince elips olur.
	v_inclination_ratio = clamp(abs(dot(disk_normal_view, view_direction)), 0.16, 1.0);
	
	// Galaksi açısal çözünürlük oranı: (1.0 = tam detaylı sarmal galaksi, 0.0 = alt-piksel uzak nokta)
	v_angular_ratio = clamp((gal_radius_ly - min_size_ly * 0.15) / max(min_size_ly * 0.70, 0.001), 0.0, 1.0);
	
	// SpaceEngine Fotometrik Parlaklık Koruması:
	v_apparent_flux = clamp(sqrt(v_angular_ratio) * 1.3, 0.40, 1.15);
	
	// Quad her mesafede kameraya dönük kalır. Diskin 3B yönelimi yukarıdaki
	// analitik elips izdüşümünde korunur; böylece yandan bakınca düzlem kaybolmaz.
	vec3 billboard_view_pos = view_center + vec3(VERTEX.x * final_radius * 2.0, VERTEX.y * final_radius * 2.0, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(billboard_view_pos, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	vec2 projected_uv = vec2(uv.x, uv.y / v_inclination_ratio);
	float r = length(projected_uv);
	
	if (r > 1.0) {
		discard;
	}
	
	float intensity = 0.0;
	vec3 col = v_tint_color.rgb;
	
	if (v_morphology < 0.5) {
		// 0: SARMAL GALAKSİ (Spiral: Sa, Sb, Sc, SB)
		// Parlak çekirdek + Logaritmik spiral kollar + Karanlık Toz Şeritleri + Genç Mavi Yıldız Düğümleri
		float core = exp(-r * 8.5) * 1.6;
		float angle = atan(projected_uv.y, projected_uv.x);
		float twist = v_arm_param * 5.2;
		float log_r = log(r + 0.025);
		float arm_pattern = cos(v_num_arms * angle - twist * log_r);
		
		// Sarmal kollar (Yüksek kontrastlı belirgin bantlar)
		float arm_mask = smoothstep(0.02, 0.78, arm_pattern) * exp(-r * 2.2);
		
		// Karanlık toz şeritleri (Sarmal kolların iç kenarlarındaki soğuk gaz ve toz - Işığı emer)
		float dust_lane = smoothstep(-0.45, 0.05, arm_pattern) * smoothstep(0.04, 0.40, r);
		
		// Genç mavi yıldız oluşum düğümleri (OB dernekleri)
		float knots = pow(max(sin(arm_pattern * 5.0 + r * 26.0), 0.0), 3.5) * arm_mask * 0.8;
		
		intensity = core + arm_mask * 1.45 * dust_lane + knots * 0.65;
		intensity = max(intensity, 0.0);
		
		// Çekirdek sıcak sarı/kehribar, kollar berrak mavi-beyaz genç yıldızlar
		vec3 core_col = vec3(1.0, 0.88, 0.65);
		vec3 arm_col = mix(v_tint_color.rgb, vec3(0.45, 0.80, 1.0), knots);
		col = mix(core_col, arm_col, smoothstep(0.08, 0.42, r));
	} else if (v_morphology < 1.5) {
		// 1: ELİPTİK GALAKSİ (Elliptical: E0 - E7)
		// de Vaucouleurs R^(1/4) profili + Merkezi çekirdek + Küresel yıldız kümesi halesi
		float axis_ratio = clamp(v_arm_param, 0.35, 1.0);
		vec2 ellip_uv = vec2(projected_uv.x, projected_uv.y / axis_ratio);
		float r_ellip = length(ellip_uv);
		if (r_ellip > 1.0) discard;
		
		float core = exp(-r_ellip * 9.0) * 1.8;
		float profile = exp(-3.6 * pow(r_ellip, 0.36)) * 1.4;
		// İnce küresel küme (globular cluster) tanecik dokusu
		float clusters = (sin(ellip_uv.x * 32.0 + ellip_uv.y * 24.0) * sin(ellip_uv.y * 36.0)) * 0.08 * smoothstep(0.1, 0.6, r_ellip);
		intensity = core + profile + clusters;
		col = mix(vec3(1.0, 0.92, 0.75), vec3(1.0, 0.82, 0.55), smoothstep(0.05, 0.5, r_ellip));
	} else if (v_morphology < 2.5) {
		// 2: DÜZENSİZ / CÜCE GALAKSİ (Irregular: LMC/SMC benzeri)
		// Kaotik gaz filamentleri ve aktif mavi/mor yıldız oluşum düğümleri
		float noise_wave = sin(projected_uv.x * 9.0 + projected_uv.y * 7.0) * cos(projected_uv.y * 12.0 - projected_uv.x * 5.0);
		float knots = pow(max(sin(projected_uv.x * 16.0 + projected_uv.y * 14.0), 0.0), 3.0) * 0.45;
		float clumpy = exp(-r * 3.2) * (0.85 + 0.35 * noise_wave) + knots;
		intensity = clumpy * 1.5;
		col = mix(vec3(0.50, 0.78, 1.0), vec3(1.0, 0.55, 0.75), abs(noise_wave));
	} else {
		// 3: MERCEKSİ GALAKSİ (Lenticular: S0 - Sombrero / Centaurus A Tipi)
		// Parlak çekirdek + İnce merceksi disk + Diski ikiye bölen KARANLIK TOZ KUŞAĞI
		float core = exp(-r * 8.0) * 1.9;
		vec2 disk_uv = vec2(projected_uv.x, projected_uv.y / 0.32); // Eğimli basık disk
		float r_disk = length(disk_uv);
		float disk = exp(-r_disk * 2.5) * 1.2;
		// Diski boydan boya kesen belirgin karanlık toz bandı
		float dust_lane = smoothstep(0.015, 0.085, abs(projected_uv.y)) * smoothstep(0.04, 0.60, r);
		intensity = core + disk * dust_lane;
		col = mix(vec3(1.0, 0.90, 0.72), vec3(0.92, 0.88, 0.80), smoothstep(0.08, 0.45, r));
	}
	
	// SpaceEngine PSF (Point Spread Function) Çekirdeği
	float psf_core = exp(-r * r * 5.0) * 1.8 + exp(-r * 8.5) * 1.2;
	vec3 psf_col = mix(v_tint_color.rgb, vec3(1.0, 0.95, 0.85), 0.5);
	
	// Çözünmüş morfoloji ile noktasal PSF arasında mesafeye bağlı pürüzsüz geçiş
	float resolve_curve = smoothstep(0.04, 0.40, v_angular_ratio);
	float blended_intensity = mix(psf_core, intensity, resolve_curve);
	vec3 blended_color = mix(psf_col, col, resolve_curve);
	
	// Dış sınırları pürüzsüz söndür (Soft edge falloff)
	float edge_fade = smoothstep(1.0, 0.60, r);
	
	// Parlaklık sıkıştırması (HDR Tone-mapping) - Aşırı beyaz patlamayı (blowout) önler
	float raw_val = blended_intensity * edge_fade * u_brightness_boost * v_apparent_flux;
	float tonemapped = raw_val / (1.0 + raw_val * 0.26);
	
	ALBEDO = blended_color * tonemapped;
	ALPHA = clamp(tonemapped * v_tint_color.a, 0.0, 1.0);
}
