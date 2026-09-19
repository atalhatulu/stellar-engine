shader_type canvas_item;
render_mode blend_add;
uniform float intensity = 0.0;
uniform float warp = 0.0;
uniform float phase = 0.0;
uniform float cockpit_view = 0.0;
uniform float aspect = 1.7778;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float radius = length(p);
	float power = clamp(intensity, 0.0, 1.5);
	// Hızlandıkça görüntünün radyal eğilip bükülmesi (uzay-zaman bükülmesi girdabı)
	float twist = (warp * 0.35 + power * 0.18) * smoothstep(0.08, 0.9, radius);
	float angle = (atan(p.y, p.x) + twist) / 6.2831853 + 0.5;
	vec3 light = vec3(0.0);
	// Two fixed-cost depths: short distant points and longer foreground trails.
	for (int i = 0; i < 2; i++) {
		float layer = float(i);
		float cells = mix(260.0, 170.0, layer);
		float angular = angle * cells;
		float lane = floor(angular);
		float seed = hash(lane + layer * 531.0);
		float center = 0.20 + hash(lane + 91.0) * 0.60;
		float width = 0.012 + 0.022 * power;
		float aa = max(fwidth(angular), 0.001);
		float ray = 1.0 - smoothstep(width, width + aa, abs(fract(angular) - center));
		float head = fract(seed + phase * (1.0 + layer));
		float behind = fract(head - radius * (0.65 + layer * 0.20));
		float tail = mix(0.012, 0.15, power) + warp * (0.10 + layer * 0.10);
		float trail = pow(1.0 - smoothstep(0.0, tail, behind), 1.6);
		float selected = smoothstep(0.76 - power * 0.42, 0.82 - power * 0.42, seed);
		vec3 tint = mix(vec3(0.35, 0.60, 1.0), vec3(0.82, 0.94, 1.0), seed);
		light += tint * ray * trail * selected * (0.55 + layer * 0.35);
	}
	float peripheral = smoothstep(0.18, 0.68, radius);
	float cockpit_mask = mix(1.0, 1.0 - smoothstep(0.50, 0.62, UV.y), cockpit_view);
	// Restrained peripheral blue glow; preserve the stars and the central target.
	vec3 halo = vec3(0.016, 0.033, 0.070) * warp * warp * peripheral * peripheral;
	COLOR = vec4((light * power * 1.3 + halo) * peripheral * cockpit_mask, 1.0);
}
