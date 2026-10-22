shader_type spatial;
render_mode cull_disabled;
// Hull of a ship module. Flat shading is computed here from screen-space derivatives, so the mesh needs
// NO normals and NO per-vertex colours: it is just positions + indices (cheap even with millions of vertices).
// base_color / damage are set per module by HullRenderer.

uniform vec4 base_color : source_color = vec4(0.55, 0.58, 0.65, 1.0);
uniform float damage = 0.0;        // 0 = new, 1 = nearly destroyed (darkens the module)
uniform float highlight = 0.0;

void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n; // always face the camera (works for either winding)
	}
	NORMAL = n;
	vec3 burnt = vec3(0.12, 0.05, 0.04);
	ALBEDO = mix(mix(base_color.rgb, burnt, damage * 0.8), vec3(1.0), highlight);
	METALLIC = 0.3;
	ROUGHNESS = 0.55;
}
