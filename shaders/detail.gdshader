shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;
// All DETAILS of a ship (windows, lights, hatches, stripes, scorch marks, boxes, antennas...) in a few meshes.
// Every detail is a quad (or a small solid). Which one it is and what it looks like is decided HERE, per pixel, from
// the vertex data written by DetailRenderer:
//   UV = place inside the quad 0..1      UV2 = (kind, seed)         COLOR = main colour (a = opacity)
//   CUSTOM0 = (second colour rgb, width / height)                   CUSTOM1 = (module index or -1, option)
// A small texture holds the state of every module (R = still there, G = damage) so that details vanish with the
// module they were put on and darken with it.

uniform sampler2D state_tex : filter_nearest;
uniform int state_count = 1;
uniform float night = 0.0;          // 0..1 how much the lit windows glow (the game sets it from the scene)
uniform float selected = -1.0;      // detail seed that the builder highlights

varying vec2 v_uv;
varying vec2 v_ks;
varying vec3 v_c2;
varying float v_aspect;
varying float v_opt;
varying float v_dmg;
varying vec3 v_n;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h21(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn(vec2 x) {
	vec2 i = floor(x); vec2 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}
float box(vec2 p, vec2 b) { vec2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }

void vertex() {
	v_uv = UV;
	v_ks = UV2;
	v_c2 = CUSTOM0.rgb;
	v_aspect = max(CUSTOM0.a, 0.05);
	v_opt = CUSTOM1.y;
	v_n = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	float mi = CUSTOM1.x;
	float alive = 1.0;
	v_dmg = 0.0;
	if (mi >= 0.0 && int(mi) < state_count) {
		vec4 st = texelFetch(state_tex, ivec2(int(mi), 0), 0);
		alive = st.r;
		v_dmg = st.g;
	}
	if (alive < 0.5) {
		VERTEX = vec3(0.0);        // the module is gone: collapse the detail to nothing
	} else if (UV2.x < 15.5 || UV2.x > 18.5) {
		// flat details float a hair above the hull; the lift grows with distance so they never z-fight
		float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		VERTEX += NORMAL * (0.006 + dist * 0.0004);
	}
}

void fragment() {
	float kind = floor(v_ks.x + 0.5);
	float seed = v_ks.y;
	vec2 uv = v_uv - 0.5;
	vec2 p = vec2(uv.x * v_aspect, uv.y);          // p.y in -0.5..0.5, p.x in -aspect/2..aspect/2 (square pixels)
	float ax = v_aspect * 0.5;
	vec3 col = COLOR.rgb;
	vec3 c2 = v_c2;
	float a = COLOR.a;
	float metallic = 0.2;
	float rough = 0.6;
	vec3 emis = vec3(0.0);
	float aa = max(fwidth(uv.y), 0.0005);
	float mask = 1.0;

	if (kind < 0.5) {                                  // WINDOW
		float d = box(p, vec2(ax - 0.06, 0.44));
		mask = 1.0 - smoothstep(-aa, aa, d);
		float frame = smoothstep(-0.1, -0.02, d);
		vec3 glass = col * (0.6 + 0.8 * uv.y);
		float lit = step(1.0 - v_opt, h11(seed * 7.13 + 1.7));
		emis = c2 * lit * (0.8 + night * 1.2) * (1.0 - frame);
		col = mix(glass, col * 2.5 + vec3(0.04), frame * 0.7);
		metallic = 0.5; rough = 0.12;
	} else if (kind < 1.5) {                            // PORTHOLE
		float d = length(p) - 0.44;
		mask = 1.0 - smoothstep(-aa, aa, d);
		float ring = smoothstep(-0.1, -0.04, d);
		float lit = step(1.0 - v_opt, h11(seed * 3.31 + 9.2));
		emis = c2 * lit * (0.8 + night * 1.2) * (1.0 - ring);
		col = mix(col, vec3(0.45, 0.47, 0.5), ring);
		metallic = 0.6; rough = 0.2;
	} else if (kind < 2.5) {                            // HATCH / port: frame, door, handle
		float d = box(p, vec2(ax - 0.04, 0.46));
		mask = 1.0 - smoothstep(-aa, aa, d);
		float inner = 1.0 - smoothstep(-aa, aa, box(p, vec2(ax - 0.14, 0.36)));
		col = mix(c2, col, inner);
		col = mix(col, col * 0.45, smoothstep(-0.03, 0.0, d) * (1.0 - inner));
		float handle = 1.0 - smoothstep(-aa, aa, box(p - vec2(ax * 0.4, 0.0), vec2(0.04, 0.1)));
		col = mix(col, vec3(0.8, 0.7, 0.2), handle * inner);
		metallic = 0.5;
	} else if (kind < 3.5) {                            // LIGHT: glowing dot with halo
		float d = length(p);
		float core = 1.0 - smoothstep(0.12, 0.2, d);
		float halo = (1.0 - smoothstep(0.0, 0.5, d)) * 0.5;
		mask = clamp(core + halo, 0.0, 1.0);
		float blink = v_opt > 0.5 ? step(0.0, sin(TIME * 4.0 + seed)) : 1.0;
		emis = col * (core * 3.0 + halo * 1.5) * blink;
		col = mix(col, vec3(1.0), core * 0.5);
	} else if (kind < 4.5) {                            // PANEL: plate with a border and corner screws
		float d = box(p, vec2(ax - 0.03, 0.47));
		mask = 1.0 - smoothstep(-aa, aa, d);
		float edge = smoothstep(-0.06, 0.0, d);
		col = mix(col, c2, edge);
		float sc = 1.0 - smoothstep(0.03, 0.05, length(abs(p) - vec2(ax - 0.12, 0.36)));
		col = mix(col, vec3(0.7), sc);
		col *= 0.9 + 0.2 * h11(seed);
		metallic = 0.6; rough = 0.4;
	} else if (kind < 5.5) {                            // VENT: dark slots
		float d = box(p, vec2(ax - 0.04, 0.46));
		mask = 1.0 - smoothstep(-aa, aa, d);
		float slats = smoothstep(0.3, 0.5, abs(fract(uv.y * 6.0 + 0.5) - 0.5) * 2.0);
		col = mix(col, c2, slats * 0.9 * step(-0.0, -d - 0.06));
		col = mix(col, c2 * 0.7, smoothstep(-0.06, 0.0, d));
	} else if (kind < 6.5) {                            // GRILLE: mesh
		float d = box(p, vec2(ax - 0.04, 0.46));
		mask = 1.0 - smoothstep(-aa, aa, d);
		vec2 g = abs(fract(p * 9.0) - 0.5);
		float m = smoothstep(0.32, 0.4, min(g.x, g.y) * 2.0 + 0.0);
		float holes = step(0.2, min(g.x, g.y));
		col = mix(c2, col, 1.0 - holes);
		col = mix(col, c2 * 0.5, smoothstep(-0.06, 0.0, d));
		metallic = 0.7;
	} else if (kind < 7.5) {                            // STRIPE: livery band, soft ends
		mask = 1.0 - smoothstep(-aa, aa, box(p, vec2(ax, 0.5)) );
		rough = 0.5;
	} else if (kind < 8.5) {                            // CHEVRON: V shape
		float v = abs(p.x) * 1.2 - p.y * 0.8;
		float band = abs(v - 0.05) - 0.12;
		mask = (1.0 - smoothstep(-aa * 2.0, aa * 2.0, band)) * (1.0 - smoothstep(0.42, 0.5, abs(p.x))) * step(abs(p.y), 0.48);
	} else if (kind < 9.5) {                            // STAR (5 points)
		float ang = atan(p.x, p.y);
		float r = length(p);
		float k = 0.5 + 0.5 * cos(ang * 5.0);
		float rad = mix(0.2, 0.48, pow(k, 1.6));
		mask = 1.0 - smoothstep(-aa * 2.0, aa * 2.0, r - rad);
		rough = 0.5;
	} else if (kind < 10.5) {                           // ROUNDEL: ring + centre
		float r = length(p);
		mask = 1.0 - smoothstep(-aa, aa, r - 0.48);
		float ring = smoothstep(0.3 - aa, 0.3 + aa, r) ;
		float centre = 1.0 - smoothstep(0.12 - aa, 0.12 + aa, r);
		col = mix(c2, col, ring);
		col = mix(col, c2, centre);
	} else if (kind < 11.5) {                           // WARNING triangle with bar and dot
		vec2 q = vec2(p.x, -p.y + 0.0);
		float tri = max(abs(q.x) * 1.73205 + q.y * 1.0 - 0.45, -q.y - 0.4);
		mask = 1.0 - smoothstep(-aa, aa, tri);
		float inner = 1.0 - smoothstep(-aa, aa, tri + 0.1);
		float bar = 1.0 - smoothstep(-aa, aa, box(p - vec2(0.0, 0.03), vec2(0.04, 0.14)));
		float dot_ = 1.0 - smoothstep(-aa, aa, length(p - vec2(0.0, -0.17)) - 0.05);
		col = mix(c2, col, 1.0 - inner * 0.0);
		col = mix(col, c2, clamp(bar + dot_, 0.0, 1.0) * inner);
	} else if (kind < 12.5) {                           // SCORCH: soft dark blast mark
		float r = length(p * vec2(1.0, 1.0)) * 2.0;
		float n = vn(p * 7.0 + seed * 3.0);
		float m = 1.0 - smoothstep(0.2, 1.0, r + (n - 0.5) * 0.7);
		mask = m * (0.55 + 0.45 * v_opt);
		col = mix(c2, col, smoothstep(0.0, 0.6, r));
		rough = 0.9; metallic = 0.0;
	} else if (kind < 13.5) {                           // STREAK: dirt running down
		float n = vn(vec2(p.x * 14.0 + seed * 5.0, p.y * 2.5));
		float width = (0.5 - abs(p.x) / max(ax, 0.01) * 0.5) ;
		float along = smoothstep(-0.5, 0.2, uv.y) * (1.0 - smoothstep(0.1, 0.5, -uv.y + 0.0) * 0.0);
		float m = smoothstep(0.35, 0.8, n) * smoothstep(0.0, 0.5, 1.0 - abs(p.x) / max(ax, 0.01)) * smoothstep(-0.5, 0.0, uv.y);
		mask = m * v_opt;
		rough = 0.95; metallic = 0.0;
	} else if (kind < 14.5) {                           // SCRATCH: thin bright lines
		float m = 0.0;
		for (int i = 0; i < 5; i++) {
			float fi = float(i) + seed * 11.0;
			vec2 dir = normalize(vec2(h11(fi) - 0.3, h11(fi + 3.0) - 0.5));
			vec2 o = vec2(h11(fi + 5.0) - 0.5, h11(fi + 7.0) - 0.5) * 0.6;
			vec2 q = p - o;
			float t = dot(q, dir);
			float dd = abs(dot(q, vec2(-dir.y, dir.x)));
			m = max(m, (1.0 - smoothstep(0.0, 0.012 + aa, dd)) * step(abs(t), 0.15 + 0.2 * h11(fi + 9.0)));
		}
		mask = m * v_opt;
		metallic = 0.9; rough = 0.3;
	} else if (kind < 15.5) {                           // DOCK_MARK: ring with cross
		float r = length(p);
		float ring = (1.0 - smoothstep(0.05, 0.05 + aa * 2.0, abs(r - 0.4)));
		float cross_ = (1.0 - smoothstep(0.0, 0.03 + aa, min(abs(p.x), abs(p.y)))) * step(r, 0.47);
		float inner = 1.0 - smoothstep(-aa, aa, r - 0.18);
		mask = clamp(ring + cross_ * 0.0 + (1.0 - smoothstep(0.0, 0.03 + aa, min(abs(p.x), abs(p.y)))) * step(r, 0.47) * step(0.22, r) , 0.0, 1.0);
		col = mix(col, c2, step(0.3, r) * 0.0 + inner);
		mask = max(mask, inner * 0.0);
	} else {                                            // solids (BOX, CYLINDER, ANTENNA) and TEXT backing: lit by their own normal
		float edge = smoothstep(0.0, 0.08, min(min(v_uv.x, 1.0 - v_uv.x), min(v_uv.y, 1.0 - v_uv.y)));
		col *= 0.75 + 0.25 * edge;
		if (kind > 17.5) {
			col = mix(col, c2, step(0.92, v_uv.y) * 0.9);     // antenna tip
			emis = c2 * step(0.92, v_uv.y) * 1.5;
		} else {
			float groove = step(0.94, fract(v_uv.y * 4.0));
			col *= 1.0 - 0.25 * groove;
		}
		metallic = 0.6; rough = 0.45;
	}

	col = mix(col, vec3(0.12, 0.05, 0.04), v_dmg * 0.8);
	if (abs(seed - selected) < 0.01) {
		float pulse = 0.5 + 0.5 * sin(TIME * 6.0);
		emis += vec3(1.0, 0.9, 0.2) * (0.6 + pulse);
		mask = max(mask, 0.25);
	}
	ALBEDO = col;
	EMISSION = emis * (1.0 - v_dmg);
	METALLIC = metallic;
	ROUGHNESS = rough;
	ALPHA = clamp(mask * a, 0.0, 1.0);
	if (ALPHA < 0.02) { discard; }
	NORMAL = normalize(v_n);
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
}
