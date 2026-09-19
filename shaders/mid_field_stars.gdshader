shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// GPU MID-FIELD STAR LAYER SHADER (AŞAMA 7A)
//
// 20.000 yıldızın pozisyon, paralaks ve sönümlenme hesaplamalarını tek bir
// GPU vertex shader çağrısında çözer. CPU döngüsü sıfırdır (0.0 ms).
// ─────────────────────────────────────────────────────────────────────────────

uniform vec3 u_player_gal_ly = vec3(0.0);
uniform vec3 u_anchor_pos_ly = vec3(0.0);
uniform float u_render_dist_min = 7500.0;  // 750 km (Güvenli render alanı)
uniform float u_render_dist_max = 11500.0; // 1150 km (Arka planın hemen önü)
uniform float u_star_pixel_size = 0.85;

uniform float u_layer_opacity = 1.0;
varying vec4 v_color;

void vertex() {
	// QuadMesh tepe noktası XY ofseti (Boyut 1.0, merkez 0,0)
	vec2 quad_uv_offset = VERTEX.xy;
	
	// MultiMesh INSTANCE_CUSTOM: xyz = Yıldızın mantıksal galaktik koordinatı (Işık Yılı)
	// w = Boyut/parlaklık varyasyon çarpanı
	vec3 star_local_ly = INSTANCE_CUSTOM.xyz;
	float size_factor = INSTANCE_CUSTOM.w;
	
	// Oyuncunun anlık galaktik konumuna göre yıldızlararası bağıl vektör
	vec3 rel_gal_ly = (u_anchor_pos_ly + star_local_ly) - u_player_gal_ly;
	float dist_ly = length(rel_gal_ly);
	vec3 dir = rel_gal_ly / max(dist_ly, 0.0001);
	
	// Mesafe Sönümlemesi (Kusursuz Çapraz Geçiş / Anti-Popping):
	// 0 - 120 LY    : %0 görünürlük (Yakın havuz aktifken çakışmayı önler)
	// 120 - 180 LY  : Yakın havuz sönerken Mid-Field pürüzsüzce açılır (Kesintisiz Geçiş)
	// 180 - 2300 LY : %100 normal görünürlük
	// 2300 - 2600 LY: Yumuşak fade-out
	float fade_in = smoothstep(120.0, 180.0, dist_ly);
	float fade_out = (1.0 - smoothstep(2300.0, 2600.0, dist_ly));
	float dist_fade = fade_in * fade_out;
	
	// Mantıksal galaktik mesafeyi güvenli render mesafesine haritala
	float t_dist = clamp((dist_ly - 120.0) / (2500.0 - 120.0), 0.0, 1.0);
	float depth_curve = pow(t_dist, 0.45);
	float render_dist = mix(u_render_dist_min, u_render_dist_max, t_dist);
	
	// Perspektif piksel boyutu: Yakın yıldızları asla bastırmayan zarif arka plan ölçeği (0.6 - 1.5 px)
	float clamped_factor = clamp(size_factor, 0.5, 1.8);
	float base_scale = render_dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y) * 1.05 * u_star_pixel_size * clamped_factor;
	base_scale *= mix(1.0, 0.45, depth_curve);
	
	// Kameraya bakan küresel billboard yönelimi (GPU-side)
	vec3 right_world = INV_VIEW_MATRIX[0].xyz;
	vec3 up_world = INV_VIEW_MATRIX[1].xyz;
	vec3 billboard_offset = (right_world * quad_uv_offset.x + up_world * quad_uv_offset.y) * base_scale;
	
	// Son render-space tepe konumu
	VERTEX = dir * render_dist + billboard_offset;
	
	// Renk, parlaklık ve mesafe derinlik sönümlemesi
	vec3 tuned_color = COLOR.rgb * mix(0.95, 0.45, depth_curve);
	v_color = vec4(tuned_color, COLOR.a * dist_fade * u_layer_opacity * mix(0.95, 0.55, depth_curve));
}

void fragment() {
	// Dairesel radyal maske
	vec2 uv_centered = UV - vec2(0.5);
	float dist_sq = dot(uv_centered, uv_centered) * 4.0;
	if (dist_sq > 1.0) {
		discard;
	}
	
	// Orta mesafe zarif nokta ışıması (Yakın fenerleri gölgelemez)
	float core_intensity = exp(-dist_sq * 28.0) * 1.2;
	float halo_intensity = exp(-dist_sq * 5.5) * 0.35;
	
	vec3 star_chroma = v_color.rgb;
	vec3 core_color = mix(star_chroma, vec3(1.0, 1.0, 1.0), clamp(core_intensity * 0.35, 0.0, 0.45));
	
	ALBEDO = core_color * core_intensity + star_chroma * halo_intensity * 1.6;
	ALPHA = v_color.a * (1.0 - smoothstep(0.70, 1.0, dist_sq));
}
