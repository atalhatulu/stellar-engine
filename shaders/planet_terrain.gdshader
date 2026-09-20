shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// ── Altitude & Slope Based Procedural Planetary Terrain Shader ─────────────
// Generates natural biomes, sharp rocky cliffs, mountain ridges, and valley floors.

uniform vec3 color_ocean_deep : source_color = vec3(0.08, 0.16, 0.12);
uniform vec3 color_lowlands   : source_color = vec3(0.16, 0.28, 0.14); // Vadiler ve yeşillik
uniform vec3 color_midlands   : source_color = vec3(0.42, 0.36, 0.28); // Dağ etekleri ve kayalıklar
uniform vec3 color_highlands  : source_color = vec3(0.80, 0.82, 0.85); // Karlı ve granit zirveler
uniform vec3 color_cliff      : source_color = vec3(0.24, 0.19, 0.15); // Dik uçurumlar

uniform float elevation_peak  : hint_range(0.0001, 0.1) = 0.0035;
uniform float cliff_threshold : hint_range(0.01, 0.6) = 0.08;
uniform float cliff_softness  : hint_range(0.01, 0.2) = 0.05;

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
    float alt_norm = clamp((v_altitude + (elevation_peak * 0.25)) / max(elevation_peak * 1.15, 0.0001), 0.0, 1.0);
    
    vec3 terrain_color;
    float is_water = 0.0;
    if (alt_norm < 0.28) {
        float t = smoothstep(0.0, 0.28, alt_norm);
        terrain_color = mix(color_ocean_deep, color_lowlands, t);
        is_water = 1.0 - smoothstep(0.18, 0.28, alt_norm);
    } else if (alt_norm < 0.65) {
        float t = smoothstep(0.28, 0.65, alt_norm);
        terrain_color = mix(color_lowlands, color_midlands, t);
    } else {
        float t = smoothstep(0.65, 1.0, alt_norm);
        terrain_color = mix(color_midlands, color_highlands, t);
    }
    
    // 3. Dik Yamaçlar ve Uçurum Kayalığı (Cliff Blending)
    float cliff_factor = smoothstep(cliff_threshold - cliff_softness, cliff_threshold + cliff_softness, slope);
    
    // Sedimanter kaya tabakaları (Strata)
    float strata = sin(v_altitude * 18000.0) * 0.12 + sin(v_altitude * 64000.0) * 0.05;
    vec3 final_cliff = color_cliff * (0.95 + strata);
    
    vec3 base_albedo = mix(terrain_color, final_cliff, cliff_factor * (1.0 - is_water * 0.8));
    
    // 4. Prosedürel Yüzey Greni ve Mikro Gölgelendirme
    vec3 seed_pos = (v_world_pos - v_planet_center) * 0.002;
    float detail_grain = noise3d(seed_pos * 8.0) * 0.12 - 0.06;
    float fine_grain = noise3d(seed_pos * 45.0) * 0.06 - 0.03;
    
    ALBEDO = clamp(base_albedo + vec3(detail_grain + fine_grain) * (1.0 - is_water * 0.7), 0.0, 1.0);
    ROUGHNESS = mix(mix(0.88, 0.68, cliff_factor), 0.12, is_water);
    METALLIC = mix(0.01, 0.04, is_water);
    SPECULAR = mix(0.18, 0.85, is_water);

    // 5. Prosedürel Yüzey Teğetsel Normal Pertürbasyonu (Kabartmalı Sırtlar ve Krater Kenarları)
    float eps = 0.015;
    float h0 = noise3d(seed_pos * 16.0);
    float hx = noise3d((seed_pos + vec3(eps, 0.0, 0.0)) * 16.0);
    float hy = noise3d((seed_pos + vec3(0.0, eps, 0.0)) * 16.0);
    float hz = noise3d((seed_pos + vec3(0.0, 0.0, eps)) * 16.0);
    vec3 grad = vec3(hx - h0, hy - h0, hz - h0) / eps;
    vec3 surface_grad = grad - norm * dot(grad, norm);
    vec3 bumped_world_norm = normalize(norm - surface_grad * (0.35 * (1.0 - is_water * 0.9)));
    NORMAL = (VIEW_MATRIX * vec4(bumped_world_norm, 0.0)).xyz;
}
