shader_type sky;
// The whole backdrop of a map in one sky shader: deep-space colour, drifting nebula clouds, a galaxy band, three layers of
// twinkling coloured stars, up to 3 suns (disc + glow + corona: the game's lights point at the same directions) and up to 2
// planets (bands / continents / lava, atmosphere glow, rings, lit by the suns, slowly turning). Everything lives at infinity,
// so nothing can be clipped by the camera and it costs nothing in geometry.

uniform vec3 bg_low : source_color = vec3(0.004, 0.006, 0.014);
uniform vec3 bg_high : source_color = vec3(0.01, 0.012, 0.03);
uniform vec3 neb_a : source_color = vec3(0.2, 0.1, 0.4);
uniform vec3 neb_b : source_color = vec3(0.1, 0.3, 0.5);
uniform vec3 neb_c : source_color = vec3(0.6, 0.2, 0.3);
uniform float neb_amount = 0.0;     // 0 = none .. 1 = the sky is mostly cloud
uniform float neb_scale = 1.3;
uniform float neb_drift = 0.004;    // how fast the clouds move (radians/s-ish)
uniform float star_amount = 1.0;
uniform float star_bright = 1.0;
uniform float galaxy = 0.0;         // brightness of the galaxy band
uniform vec3 galaxy_normal = vec3(0.2, 1.0, 0.3);
uniform vec3 galaxy_color : source_color = vec3(0.7, 0.75, 1.0);

uniform int sun_count = 0;
uniform vec3 sun_dir[3];            // direction TOWARDS each sun
uniform vec3 sun_col[3];            // colour (HDR)
uniform float sun_size[3];          // angular radius, radians
uniform int planet_count = 0;
uniform vec3 planet_dir[2];
uniform float planet_size[2];       // angular radius, radians
uniform vec3 planet_a[2];           // main colours
uniform vec3 planet_b[2];
uniform vec3 planet_c[2];
uniform vec3 planet_atm[2];         // atmosphere colour
uniform vec4 planet_misc[2];        // x kind (0 gas, 1 rock, 2 lava, 3 ice), y has rings, z spin speed, w seed
uniform vec3 planet_ring_n[2];      // ring plane normal
uniform vec3 planet_ring_col[2];

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }
float h13(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
vec3 h33(vec3 p) { return vec3(h13(p), h13(p + 19.19), h13(p + 47.7)); }
float vn(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5; float s = 0.0;
	for (int i = 0; i < 5; i++) { s += a * vn(p); p = p * 2.03 + 11.7; a *= 0.5; }
	return s;
}

vec3 star_layer(vec3 d, float scale, float radius, float density, float seed, float t) {
	vec3 q = d * scale;
	vec3 cell = floor(q);
	float h = h13(cell + seed);
	if (h > density) { return vec3(0.0); }
	vec3 centre = cell + 0.5 + (h33(cell + seed * 3.1) - 0.5) * 0.4;
	float dist = length(q - centre);
	float mag = h13(cell * 1.7 + seed);
	float r = radius * (0.5 + mag);
	float core = smoothstep(r, 0.0, dist);
	float tw = 0.75 + 0.25 * sin(t * (1.0 + mag * 4.0) + mag * 60.0);
	vec3 tint = mix(vec3(1.0, 0.7, 0.5), vec3(0.7, 0.8, 1.0), fract(mag * 37.0));
	return tint * core * core * (0.6 + 2.0 * mag * mag) * tw;
}

vec3 sun_light_at(vec3 n) {   // light the suns put on a surface with normal n (sky space)
	vec3 l = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		if (i < sun_count) { l += sun_col[i] * 0.35 * max(dot(n, sun_dir[i]), 0.0); }
	}
	return l;
}

vec3 planet_pixel(vec3 d, int i, out float alpha, float t) {
	alpha = 0.0;
	vec3 c = normalize(planet_dir[i]);
	float ang = planet_size[i];
	float R = sin(ang);
	float b = dot(d, c);
	float disc = b * b - (1.0 - R * R);
	vec4 misc = planet_misc[i];
	vec3 col = vec3(0.0);
	float t_hit = 1.0e9;
	vec3 ringn = normalize(planet_ring_n[i]);
	// surface
	if (disc >= 0.0) {
		float t = b - sqrt(disc);
		t_hit = t;
		vec3 P = d * t;
		vec3 n = (P - c) / R;
		float spin = t * misc.z + misc.w * 10.0;
		float cs = cos(spin); float sn = sin(spin);
		vec3 nr = vec3(n.x * cs + n.z * sn, n.y, -n.x * sn + n.z * cs);
		vec3 surf;
		if (misc.x < 0.5) {                                   // gas giant: bands and storms
			float lat = nr.y;
			float warp = fbm(nr * 3.0 + vec3(0.0, t * 0.01, 0.0) + misc.w) ;
			float bands = 0.5 + 0.5 * sin(lat * 14.0 + warp * 5.0 + misc.w);
			float fine = vn(vec3(lat * 40.0, nr.x * 3.0, nr.z * 3.0) + warp * 4.0);
			surf = mix(planet_a[i], planet_b[i], bands);
			surf = mix(surf, planet_c[i], smoothstep(0.55, 0.9, fine) * 0.6);
		} else if (misc.x < 1.5) {                            // rocky: continents, caps
			float land = fbm(nr * 3.5 + misc.w);
			surf = mix(planet_a[i], planet_b[i], smoothstep(0.45, 0.6, land));
			float clouds = fbm(nr * 5.0 + vec3(t * 0.01, 0.0, misc.w * 3.0));
			surf = mix(surf, vec3(1.0), smoothstep(0.55, 0.8, clouds) * 0.65);
			surf = mix(surf, planet_c[i], smoothstep(0.82, 0.95, abs(nr.y)));
		} else if (misc.x < 2.5) {                            // lava: dark crust, glowing cracks
			float cr = fbm(nr * 6.0 + misc.w);
			float crack = smoothstep(0.02, 0.0, abs(cr - 0.5) - 0.01);
			surf = mix(planet_a[i], planet_b[i], fbm(nr * 2.0));
			surf = mix(surf, planet_c[i] * 3.0, crack);
		} else {                                              // ice
			float f = fbm(nr * 4.0 + misc.w);
			surf = mix(planet_a[i], planet_b[i], f);
			surf = mix(surf, planet_c[i], smoothstep(0.6, 0.9, vn(nr * 12.0)) * 0.5);
		}
		vec3 lit = sun_light_at(n);
		float night = 1.0 - smoothstep(0.0, 0.3, max(max(lit.r, lit.g), lit.b));
		col = surf * (lit + 0.015);
		if (misc.x > 1.5 && misc.x < 2.5) { col += planet_c[i] * night * 0.6 * smoothstep(0.5, 0.52, fbm(nr * 6.0 + misc.w)); }
		float rim = pow(1.0 - clamp(dot(n, -d), 0.0, 1.0), 3.0);
		col += planet_atm[i] * rim * (lit + 0.03) * 2.5;
		alpha = 1.0;
	} else {
		// atmosphere haze just outside the disc (on the lit side)
		float closest = acos(clamp(b, -1.0, 1.0));
		float out_d = (closest - ang) / ang;
		if (out_d < 0.12 && b > 0.0) {
			vec3 Pc = d * b;
			vec3 nn = normalize(Pc - c);
			vec3 lit = sun_light_at(nn);
			float g = exp(-out_d * 40.0);
			col = planet_atm[i] * g * (lit + 0.02) * 1.5;
			alpha = clamp(g, 0.0, 1.0);
		}
	}
	// rings
	if (misc.y > 0.5) {
		float den = dot(d, ringn);
		if (abs(den) > 0.0001) {
			float tr = dot(c, ringn) / den;
			if (tr > 0.0) {
				vec3 Pr = d * tr;
				float rr = length(Pr - c) / R;
				if (rr > 1.35 && rr < 2.5 && tr < t_hit) {
					float band = 0.7 + 0.3 * sin(rr * 26.0 + h11(floor(rr * 12.0)) * 6.0);
					float gap = smoothstep(0.0, 0.03, abs(rr - 1.95) - 0.035);
					float a = band * gap * smoothstep(1.35, 1.45, rr) * (1.0 - smoothstep(2.35, 2.5, rr)) * 0.9;
					vec3 side = sun_light_at(ringn) + sun_light_at(-ringn);
					vec3 rc = planet_ring_col[i] * (side + 0.03) * (0.8 + 0.4 * h11(floor(rr * 40.0)));
					col = mix(col, rc, a);
					alpha = max(alpha, a);
				}
			}
		}
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = mix(bg_low, bg_high, 0.5 + 0.5 * d.y);

	// galaxy band
	if (galaxy > 0.001) {
		vec3 gn = normalize(galaxy_normal);
		float lat = dot(d, gn);
		float band = exp(-lat * lat * 14.0);
		float dust = fbm(d * 6.0 + 3.0);
		col += galaxy_color * band * galaxy * (0.25 + 0.75 * fbm(d * 9.0)) * (1.0 - 0.7 * smoothstep(0.45, 0.7, dust));
	}
	// nebula: two soft layers and a ridged filament layer, drifting; coloured by position, brightened near suns
	if (neb_amount > 0.001) {
		vec3 p = d * neb_scale + vec3(TIME * neb_drift, 0.0, TIME * neb_drift * 0.6);
		float n1 = fbm(p * 1.3);
		float n2 = fbm(p * 2.7 + 7.0);
		float ridge = 1.0 - abs(fbm(p * 3.3 + 21.0) * 2.0 - 1.0);
		float dens = smoothstep(1.0 - neb_amount * 0.9, 1.0, n1 * 1.2 + n2 * 0.4) ;
		vec3 nc = mix(neb_a, neb_b, smoothstep(0.3, 0.7, n2));
		nc = mix(nc, neb_c, smoothstep(0.55, 0.9, fbm(p * 0.8 + 40.0)));
		col += nc * dens * (0.5 + 1.5 * pow(ridge, 4.0)) * neb_amount;
		for (int i = 0; i < 3; i++) {
			if (i < sun_count) { col += nc * dens * sun_col[i] * 0.02 * pow(max(dot(d, sun_dir[i]), 0.0), 3.0); }
		}
	}
	// stars (fainter where nebula is dense)
	vec3 st = star_layer(d, 90.0, 0.10, 0.12 * star_amount, 1.0, TIME)
		+ star_layer(d, 200.0, 0.14, 0.18 * star_amount, 2.0, TIME)
		+ star_layer(d, 420.0, 0.2, 0.22 * star_amount, 3.0, TIME) * 0.8;
	col += st * star_bright;

	// planets
	for (int i = 0; i < 2; i++) {
		if (i < planet_count) {
			float a;
			vec3 pc = planet_pixel(d, i, a, TIME);
			col = mix(col, pc, a);
		}
	}
	// suns: bright disc, soft glow, corona
	for (int i = 0; i < 3; i++) {
		if (i < sun_count) {
			vec3 sd = normalize(sun_dir[i]);
			float cosang = clamp(dot(d, sd), -1.0, 1.0);
			float ang = acos(cosang);
			float sz = sun_size[i];
			float disc = smoothstep(sz * 1.04, sz * 0.94, ang);
			float glow = exp(-ang / (sz * 2.2)) * 0.45 + exp(-ang / (sz * 9.0)) * 0.07;
			// rays
			vec3 up = abs(sd.y) < 0.99 ? vec3(0, 1, 0) : vec3(1, 0, 0);
			vec3 rt = normalize(cross(sd, up));
			vec3 tp = cross(rt, sd);
			float az = atan(dot(d, tp), dot(d, rt));
			float rays = pow(0.5 + 0.5 * sin(az * 7.0 + TIME * 0.05), 8.0) * exp(-ang / (sz * 6.0)) * 0.12;
			float flick = 0.97 + 0.03 * sin(TIME * 1.7 + float(i) * 2.0) + 0.02 * sin(TIME * 4.3 + float(i));
			vec3 c = sun_col[i];
			col += c * (disc * 3.0 + glow + rays) * flick;
			col = mix(col, vec3(1.0) * (c.r + c.g + c.b) * 0.5, disc * 0.5);
		}
	}
	COLOR = col;
}
