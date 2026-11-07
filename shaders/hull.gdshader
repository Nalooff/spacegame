shader_type spatial;
render_mode cull_disabled;
// Hull of a ship module. Flat shading is computed here from screen-space derivatives, so the mesh needs
// NO normals and NO per-vertex colours: it is just positions + indices (cheap even with millions of vertices).
// Set per module by HullRenderer: colours / pattern (the designer's PAINT), damage, and the DIRECTION MARK.
//
// DIRECTION MARK: modules that point somewhere (thruster exhaust, barrel muzzle, turret mount) get a glowing end cap
// in a signal colour that paint cannot hide, so another player can read from a distance where the guns and the
// thrusters point.

uniform vec4 base_color : source_color = vec4(0.55, 0.58, 0.65, 1.0);
uniform vec4 accent_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform int pattern = 0;           // 0 solid, 1 stripes, 2 checker, 3 hazard, 4 two-tone
uniform float pattern_scale = 1.0; // metres of one stripe / square
uniform vec3 mark_center = vec3(0.0);
uniform vec3 mark_axis = vec3(0.0); // unit vector the mark points along (zero = no mark)
uniform float mark_len = 1.0;       // half length of the module along the axis
uniform vec4 mark_color : source_color = vec4(1.0, 0.4, 0.1, 1.0);
uniform float damage = 0.0;        // 0 = new, 1 = nearly destroyed (darkens the module)
uniform float highlight = 0.0;

varying vec3 v_pos;                // position in ship space (the meshes are built in ship space)

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n; // always face the camera (works for either winding)
	}
	NORMAL = n;
	vec3 col = base_color.rgb;
	float s = max(pattern_scale, 0.05);
	float k = 0.0;
	if (pattern == 1) {
		k = step(0.5, fract((v_pos.x + v_pos.y * 0.5 + v_pos.z) / (2.0 * s)));
	} else if (pattern == 2) {
		vec3 c = floor(v_pos / s);
		k = mod(c.x + c.y + c.z, 2.0);
	} else if (pattern == 3) {
		k = step(0.5, fract((v_pos.x + v_pos.y + v_pos.z) / (2.0 * s)));
	} else if (pattern == 4) {
		k = step(0.0, dot(v_pos - mark_center, vec3(0.0, 1.0, 0.0)));
	}
	col = mix(col, accent_color.rgb, k);
	vec3 burnt = vec3(0.12, 0.05, 0.04);
	vec3 emis = vec3(0.0);
	if (dot(mark_axis, mark_axis) > 0.25) {
		float t = dot(v_pos - mark_center, mark_axis) / max(mark_len, 0.01);
		float m = smoothstep(0.55, 0.8, t);
		col = mix(col, mark_color.rgb, m);
		emis = mark_color.rgb * m * 1.2;
	}
	ALBEDO = mix(mix(col, burnt, damage * 0.8), vec3(1.0), highlight);
	EMISSION = emis * (1.0 - damage);
	METALLIC = 0.3;
	ROUGHNESS = 0.55;
}
