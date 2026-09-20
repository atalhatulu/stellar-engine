shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ── Altitude & Slope Based Procedural Planetary Terrain Shader ─────────────
// Generates natural biomes, sharp rocky cliffs, mountain ridges, and valley floors.

uniform vec3 color_ocean_deep : source_color = vec3(0.12, 0.06, 0.04);
uniform vec3 color_lowlands   : source_color = vec3(0.55, 0.38, 0.24); // Toprak, kum ve vadi tabanı
uniform vec3 color_midlands   : source_color = vec3(0.72, 0.52, 0.35); // Yaylalar ve tepeler
uniform vec3 color_highlands  : source_color = vec3(0.92, 0.82, 0.75); // Yüksek zirveler / granit sırtlar
uniform vec3 color_cliff      : source_color = vec3(0.30, 0.20, 0.15); // Dik yamaç kayalıkları

uniform float elevation_peak  : hint_range(0.0005, 0.05) = 0.0035;
uniform float cliff_threshold : hint_range(0.05, 0.6) = 0.18;
uniform float cliff_softness  : hint_range(0.01, 0.2) = 0.08;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_planet_center;
varying float v_altitude;

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_planet_center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    v_altitude = length(VERTEX) - 1.0;
}

// Hızlı deterministik 3D fraktal gürültü (Yüzey mikro detayları ve kaya dokusu)
float hash31(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    return mix(
        mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
        mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
        f.z
    );
}

void fragment() {
    // Dünya koordinatlarında gerçek yüzey normali ve radyal yerel yukarı vektörü
    vec3 norm = normalize(v_world_normal);
    vec3 up = normalize(v_world_pos - v_planet_center);
    
    // 1. Eğim (Slope): Yüzey normali ile radyal yukarı arasındaki sapma
    float cos_angle = clamp(dot(norm, up), 0.0, 1.0);
    float slope = 1.0 - cos_angle;
    
    // 2. İrtifa Kademelendirmesi (Altitude Blending)
    float alt_norm = clamp((v_altitude + (elevation_peak * 0.3)) / max(elevation_peak * 1.3, 0.0001), 0.0, 1.0);
    
    vec3 terrain_color;
    if (alt_norm < 0.35) {
        float t = smoothstep(0.0, 0.35, alt_norm);
        terrain_color = mix(color_ocean_deep, color_lowlands, t);
    } else if (alt_norm < 0.70) {
        float t = smoothstep(0.35, 0.70, alt_norm);
        terrain_color = mix(color_lowlands, color_midlands, t);
    } else {
        float t = smoothstep(0.70, 1.0, alt_norm);
        terrain_color = mix(color_midlands, color_highlands, t);
    }
    
    // 3. Dik Yamaçlar ve Uçurum Kayalığı (Cliff Blending)
    float cliff_factor = smoothstep(cliff_threshold - cliff_softness, cliff_threshold + cliff_softness, slope);
    
    // Sedimanter kaya tabakaları (Strata)
    float strata = sin(v_altitude * 24000.0) * 0.10;
    vec3 final_cliff = color_cliff * (0.95 + strata);
    
    vec3 base_albedo = mix(terrain_color, final_cliff, cliff_factor);
    
    // 4. Prosedürel Yüzey Greni ve Mikro Gölgelendirme
    vec3 seed_pos = (v_world_pos - v_planet_center) * 0.002;
    float detail_grain = noise3d(seed_pos * 8.0) * 0.12 - 0.06;
    float fine_grain = noise3d(seed_pos * 45.0) * 0.06 - 0.03;
    
    ALBEDO = clamp(base_albedo + vec3(detail_grain + fine_grain), 0.0, 1.0);
    ROUGHNESS = mix(0.90, 0.75, cliff_factor);
    METALLIC = 0.01;
    SPECULAR = 0.20;
}
