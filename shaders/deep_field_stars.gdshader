shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// GPU DEEP-FIELD REAL STAR LAYER SHADER (AŞAMA 7B)
//
// 2.500 LY ila 25.000 LY mantıksal galaktik mesafede bulunan 25k–100k yıldızın
// GPU üzerinde sıfır CPU döngüsüyle gerçek mesafe bazlı paralaks üreterek
// çizilmesini sağlar.
// ─────────────────────────────────────────────────────────────────────────────

uniform vec3 u_player_gal_ly = vec3(0.0);
uniform vec3 u_anchor_pos_ly = vec3(0.0);
uniform float u_render_dist_min = 11500.0; // 1150 km (Mid-Field katmanının hemen arkası)
uniform float u_render_dist_max = 16500.0; // 1650 km (Far plane 2000 km'nin güvenli önü)
uniform float u_star_pixel_size = 0.50;

uniform float u_layer_opacity = 1.0;
varying vec4 v_color;

void vertex() {
	// QuadMesh tepe noktası XY ofseti (Boyut 1.0, merkez 0,0)
	vec2 quad_uv_offset = VERTEX.xy;
	
	// MultiMesh INSTANCE_CUSTOM:
	// xyz = Yıldızın deterministik mantıksal galaktik koordinatı (Işık Yılı)
	// w   = Yıldız boyutu ve parlaklık varyasyon çarpanı
	vec3 star_local_ly = INSTANCE_CUSTOM.xyz;
	float size_factor = INSTANCE_CUSTOM.w;
	
	// Oyuncunun anlık galaktik konumuna göre yıldızlararası bağıl vektör
	vec3 rel_gal_ly = (u_anchor_pos_ly + star_local_ly) - u_player_gal_ly;
	float dist_ly = length(rel_gal_ly);
	vec3 dir = rel_gal_ly / max(dist_ly, 0.0001);
	
	// Mesafe Sönümlemesi ve Anti-Popping (Aşama 7B):
	// Mid-Field (150-2500 LY) ile Deep-Field (2500-25000 LY) arasında kusursuz geçiş:
	float fade_in = smoothstep(2300.0, 2700.0, dist_ly);
	float fade_out = (1.0 - smoothstep(22000.0, 25000.0, dist_ly));
	float dist_fade = fade_in * fade_out;
	
	// Mantıksal galaktik mesafeyi (2.500 - 25.000 LY) güvenli render mesafesine haritala
	float t_dist = clamp((dist_ly - 2500.0) / (25000.0 - 2500.0), 0.0, 1.0);
	float depth_curve = pow(t_dist, 0.42);
	float render_dist = mix(u_render_dist_min, u_render_dist_max, t_dist);
	
	// Perspektif piksel boyutu: İğne ucu mikro kozmik fon tozu (0.3 - 0.7 px)
	float clamped_factor = clamp(size_factor, 0.6, 1.15);
	float base_scale = render_dist * 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y) * 0.95 * u_star_pixel_size * clamped_factor;
	base_scale *= mix(0.80, 0.30, depth_curve);
	
	// Kameraya bakan küresel billboard yönelimi (GPU-side)
	vec3 right_world = INV_VIEW_MATRIX[0].xyz;
	vec3 up_world = INV_VIEW_MATRIX[1].xyz;
	vec3 billboard_offset = (right_world * quad_uv_offset.x + up_world * quad_uv_offset.y) * base_scale;
	
	// Son render-space tepe konumu
	VERTEX = dir * render_dist + billboard_offset;
	
	// Renk, parlaklık ve derin galaktik fon sönümlemesi
	vec3 tuned_color = COLOR.rgb * mix(0.75, 0.30, depth_curve);
	v_color = vec4(tuned_color, COLOR.a * dist_fade * u_layer_opacity * mix(0.65, 0.30, depth_curve));
}

void fragment() {
	// Dairesel radyal maske
	vec2 uv_centered = UV - vec2(0.5);
	float dist_sq = dot(uv_centered, uv_centered) * 4.0;
	if (dist_sq > 1.0) {
		discard;
	}
	
	// Derin galaktik fon için narin iğne ucu parıltısı
	float core_intensity = exp(-dist_sq * 32.0) * 1.0;
	float halo_intensity = exp(-dist_sq * 6.5) * 0.20;
	
	vec3 star_chroma = v_color.rgb;
	vec3 core_color = mix(star_chroma, vec3(1.0, 1.0, 1.0), clamp(core_intensity * 0.30, 0.0, 0.40));
	
	ALBEDO = core_color * core_intensity + star_chroma * halo_intensity * 1.2;
	ALPHA = v_color.a * (1.0 - smoothstep(0.70, 1.0, dist_sq));
}
