shader_type spatial;
render_mode diffuse_burley;
// Asteroids drawn in one MultiMesh: rock colour from noise in object space, each rock tumbles slowly (the rotation axis and
// speed come from the instance's custom data, so a thousand rocks cost one draw call and no script).
uniform vec3 tint_a : source_color = vec3(0.32, 0.30, 0.28);
uniform vec3 tint_b : source_color = vec3(0.16, 0.15, 0.15);
uniform float glow_amount = 0.0;    // lava-lit rocks
uniform vec3 glow_color : source_color = vec3(1.0, 0.3, 0.1);
varying vec3 v_obj;

float h13(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vn(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
mat3 axis_rot(vec3 a, float t) {
	a = normalize(a);
	float c = cos(t); float s = sin(t); float k = 1.0 - c;
	return mat3(vec3(c + a.x * a.x * k, a.x * a.y * k + a.z * s, a.x * a.z * k - a.y * s),
		vec3(a.x * a.y * k - a.z * s, c + a.y * a.y * k, a.y * a.z * k + a.x * s),
		vec3(a.x * a.z * k + a.y * s, a.y * a.z * k - a.x * s, c + a.z * a.z * k));
}
void vertex() {
	vec3 axis = INSTANCE_CUSTOM.xyz;
	if (dot(axis, axis) > 0.0001) {
		mat3 r = axis_rot(axis, TIME * INSTANCE_CUSTOM.w);
		VERTEX = r * VERTEX;
		NORMAL = r * NORMAL;
	}
	v_obj = VERTEX * 0.8 + vec3(INSTANCE_CUSTOM.w * 13.0);
}
void fragment() {
	float n = vn(v_obj * 2.0) * 0.6 + vn(v_obj * 7.0) * 0.3 + vn(v_obj * 23.0) * 0.1;
	ALBEDO = mix(tint_b, tint_a, n);
	ROUGHNESS = 0.92;
	METALLIC = 0.05;
	EMISSION = glow_color * glow_amount * smoothstep(0.62, 0.8, n);
}
