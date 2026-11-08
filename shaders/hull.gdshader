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
// FINISH (ship-wide, from ShipDesign.finish): surface look and weathering
uniform float metal = 0.3;
uniform float rough = 0.55;
uniform float gloss = 0.0;         // clear coat
uniform float wear = 0.0;          // 0..1 grime, rust, scuffs
uniform float panels = 0.0;        // 0..1 strength of plate lines
uniform float rivets = 0.0;        // 0 / 1
uniform float panel_size = 2.0;    // metres of one plate
uniform float ship_size = 20.0;    // longest side, metres

varying vec3 v_pos;                // position in ship space (the meshes are built in ship space)

float h31(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

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
	float met = metal;
	float rgh = rough;
	// plate lines, rivets and per-plate tone, triplanar on the dominant axis (all in ship space = no stretching)
	if (panels > 0.01 || rivets > 0.5 || wear > 0.01) {
		vec3 an = abs(normalize(cross(dFdx(v_pos), dFdy(v_pos))));
		vec2 uvp = an.x > an.y && an.x > an.z ? v_pos.yz : (an.y > an.z ? v_pos.xz : v_pos.xy);
		float S = max(panel_size, 0.1);
		vec2 g = uvp / S;
		float row = floor(g.y);
		g.x += h21(vec2(row, 3.7)) * 1.0;                // bricks: every row is shifted
		vec2 cell = floor(g);
		vec2 fr = fract(g);
		float aa = max(fwidth(g.x), fwidth(g.y));
		float fade = 1.0 - smoothstep(0.12, 0.45, aa);   // plates smaller than a few pixels fade out (no moire)
		float edge = min(min(fr.x, 1.0 - fr.x), min(fr.y, 1.0 - fr.y));
		float lw = max(0.012, aa * 0.8);
		float line = 1.0 - smoothstep(lw * 0.5, lw * 1.5, edge);
		float tone = h21(cell + 11.0);
		if (panels > 0.01) {
			col *= 1.0 + (tone - 0.5) * 0.2 * panels * fade;
			col = mix(col, col * 0.35, line * panels * fade);
			rgh = mix(rgh, rgh + 0.2, line * panels * fade);
		}
		if (rivets > 0.5) {
			vec2 r1 = vec2(fr.x < 0.5 ? 0.06 : 0.94, (floor(fr.y * 6.0) + 0.5) / 6.0);
			vec2 r2 = vec2((floor(fr.x * 6.0) + 0.5) / 6.0, fr.y < 0.5 ? 0.06 : 0.94);
			float d = min(length((fr - r1)), length((fr - r2)));
			float rv = (1.0 - smoothstep(0.012, 0.012 + aa, d)) * fade * smoothstep(0.0, 0.05, 0.2 - aa);
			col = mix(col, col * 1.45 + 0.04, rv);
			met = mix(met, 0.8, rv);
		}
		if (wear > 0.01) {
			float f0 = 6.0 / max(ship_size, 1.0);
			float f1 = 1.0 / S;
			float n = vn3(v_pos * f0) * 0.5 + vn3(v_pos * f0 * 4.3) * 0.3 + vn3(v_pos * f1 * 1.7) * 0.2;
			float grime = smoothstep(0.62 - wear * 0.32, 0.95 - wear * 0.2, n) * wear;
			float streak = vn3(vec3(v_pos.x * f1 * 2.0, v_pos.y * f1 * 0.12, v_pos.z * f1 * 2.0));
			float st = smoothstep(0.62, 0.9, streak) * wear * 0.8;
			float rust = smoothstep(0.72 - wear * 0.1, 0.95, vn3(v_pos * f1 * 0.9 + 7.0)) * wear;
			col = mix(col, vec3(0.06, 0.055, 0.05), clamp(grime * 0.75 + st * 0.6, 0.0, 0.9));
			col = mix(col, vec3(0.38, 0.17, 0.07), rust * 0.65);
			float scuff = line * wear * fade * step(0.5, h21(cell + 4.0)); // worn bright edges on some plates
			col = mix(col, col * 1.6 + 0.05, scuff * 0.5);
			rgh = clamp(rgh + grime * 0.35 + rust * 0.3, 0.0, 1.0);
			met = clamp(met - grime * 0.4 - rust * 0.3, 0.0, 1.0);
		}
	}
	ALBEDO = mix(mix(col, burnt, damage * 0.8), vec3(1.0), highlight);
	EMISSION = emis * (1.0 - damage);
	METALLIC = met;
	ROUGHNESS = rgh;
	CLEARCOAT = gloss;
	CLEARCOAT_ROUGHNESS = 0.08;
}
