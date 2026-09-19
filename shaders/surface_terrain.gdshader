shader_type spatial;
render_mode cull_back;
uniform vec4 soil : source_color = vec4(0.29,0.31,0.35,1.0);
uniform vec4 rock : source_color = vec4(0.13,0.15,0.19,1.0);
varying vec3 world_pos;
varying vec3 world_normal;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
	vec3 cell=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(cell),hash(cell+vec3(1,0,0)),f.x),mix(hash(cell+vec3(0,1,0)),hash(cell+vec3(1,1,0)),f.x),f.y),mix(mix(hash(cell+vec3(0,0,1)),hash(cell+vec3(1,0,1)),f.x),mix(hash(cell+vec3(0,1,1)),hash(cell+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
	float slope=1.0-clamp(world_normal.y,0.0,1.0);
	float broad=noise(world_pos*0.065);
	float grain=noise(world_pos*3.0);
	ALBEDO=mix(soil.rgb,rock.rgb,smoothstep(0.07,0.4,slope)+broad*0.18)*(0.8+broad*0.27+grain*0.13);
	ROUGHNESS=0.92;
}
