shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 atmosphere_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec4 sunset_color : source_color = vec4(1.0, 0.45, 0.15, 1.0);
uniform float glow_intensity : hint_range(0.0, 10.0) = 2.2;
uniform float fresnel_power : hint_range(0.1, 10.0) = 3.2;
uniform vec3 sun_direction; // Normalized world-space direction from planet to Sun

void fragment() {
	// Fresnel etkisi (gezegen kenar tülü)
	float ndotv = abs(dot(NORMAL, VIEW));
	float fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), fresnel_power);
	
	// Dünya normalini hesapla
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (!FRONT_FACING) {
		normal_world = -normal_world;
	}
	
	// Güneş açısı ve terminatör saçılması (Rayleigh gün batımı halkası)
	float sun_factor = dot(normal_world, sun_direction);
	float sun_mask = clamp(sun_factor, 0.0, 1.0);
	sun_mask = mix(0.06, 1.0, sun_mask);
	
	// Gün doğumu/batımı geçiş halkası (terminator band)
	float twilight = pow(clamp(1.0 - abs(sun_factor), 0.0, 1.0), 3.0) * smoothstep(-0.15, 0.45, sun_factor);
	vec3 final_color = mix(atmosphere_color.rgb, sunset_color.rgb, twilight * 0.75);
	
	ALBEDO = final_color * glow_intensity;
	ALPHA = fresnel * atmosphere_color.a * (sun_mask + twilight * 0.4);
}


