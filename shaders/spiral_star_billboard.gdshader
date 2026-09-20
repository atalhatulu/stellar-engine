shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// ─────────────────────────────────────────────────────────────────────────────
// PROCEDURAL SPIRAL STAR BILLBOARD SHADER (GPU-GÜVENLİ VE GELİŞMİŞ LOD)
// 100.000 yıldızın tamamını mesafeden bağımsız olarak parlak, net ve canlı
// gösterir. Yıldızların alt-pikselde sönmesini engelleyen kararlı açısal LOD.
// ─────────────────────────────────────────────────────────────────────────────

uniform float u_base_scale = 1.35;
uniform float u_glow_boost = 1.45;
uniform float u_distance_lod_scale = 0.00036;

varying vec4 v_color;
varying float v_brightness;
varying float v_is_giant;

void vertex() {
	v_color = COLOR;
	
	// INSTANCE_CUSTOM:
	// x: normalize yarıçap (R / R_sun)
	// y: faz
	// z: parlaklık
	// w: dev yıldız bayrağı
	float norm_radius = INSTANCE_CUSTOM.x;
	v_brightness = INSTANCE_CUSTOM.z;
	v_is_giant = INSTANCE_CUSTOM.w;
	
	// Kamera mesafesi ve her örneğin kamera uzayındaki merkezi
	vec3 view_center = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float cam_dist = length(view_center);
	
	// Uzaklık bazlı kararlı açısal boyutlandırma:
	// Yıldız mesafesi arttıkça boyutu mesafeyle orantılı ölçeklenir.
	// Böylece GPU rasterization aşamasında piksel altı (sub-pixel) kalıp kaybolmaz.
	float angular_size = cam_dist * u_distance_lod_scale * norm_radius * u_base_scale;
	if (v_is_giant > 0.5) {
		angular_size *= 1.45;
	}
	float final_size = clamp(angular_size, 0.002, 32.0);
	
	// Tam Küresel Billboard (Kamera uzayında doğrudan düzleme yasla)
	vec3 view_pos = view_center + vec3(VERTEX.x * final_size, VERTEX.y * final_size, 0.0);
	POSITION = PROJECTION_MATRIX * vec4(view_pos, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r_sq = dot(uv, uv);
	if (r_sq > 1.0) {
		discard;
	}
	float r = sqrt(r_sq);
	
	// Merkezde parlak iğne ucu çekirdek + difüzyon halesi
	float core = exp(-r * 4.8);
	float halo = pow(clamp(1.0 - r, 0.0, 1.0), 2.5) * 0.40;
	
	// Dev yıldızlar için 4 kollu kırınım ışıması (Diffraction Spike)
	float spikes = 0.0;
	if (v_is_giant > 0.5) {
		float arm_x = max(0.0, 1.0 - abs(uv.y) * 12.0) * max(0.0, 1.0 - abs(uv.x));
		float arm_y = max(0.0, 1.0 - abs(uv.x) * 12.0) * max(0.0, 1.0 - abs(uv.y));
		spikes = (arm_x + arm_y) * 0.55;
	}
	
	float intensity = (core * 1.6 + halo + spikes) * v_brightness * u_glow_boost;
	vec3 star_rgb = v_color.rgb * intensity;
	
	ALBEDO = star_rgb;
	ALPHA = clamp(intensity, 0.0, 1.0);
}
