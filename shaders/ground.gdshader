shader_type spatial;
// Suelo de la ciudad: asfalto mojado, líneas de la calle, pasos de peatones y
// aceras. Todo se calcula a partir de la posición en el mundo, así que el
// mismo material sirve para todos los trozos de suelo y nunca se acaba.

uniform float chunk = 80.0;       // distancia entre calles
uniform float road_half = 10.0;   // media anchura de la calzada
uniform float sidewalk = 3.0;     // anchura de la acera

varying vec3 w_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

// Ruido suave que se repite cada "period" (para no perder precisión lejos del origen).
float vnoise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 i0 = mod(i, period);
	vec2 i1 = mod(i + 1.0, period);
	float a = hash21(i0);
	float b = hash21(vec2(i1.x, i0.y));
	float c = hash21(vec2(i0.x, i1.y));
	float d = hash21(i1);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 1 dentro de una franja centrada en "center" de media anchura "half_w".
float band(float d, float center, float half_w) {
	float aa = fwidth(d) + 0.0005;
	return 1.0 - smoothstep(half_w - aa, half_w + aa, abs(d - center));
}

// Marcas blancas de una calle. d = distancia a su eje, along = posición a lo
// largo de ella, cross_d = distancia al eje de la calle que la cruza.
float white_marks(float d, float along, float cross_d) {
	float clear = step(road_half + 4.5, cross_d);                      // lejos del cruce
	float dash = step(fract(along / 9.0), 0.45);
	float lanes = band(d, road_half * 0.5, 0.08) * dash * clear;       // separación de carriles
	float edge = band(d, road_half - 0.5, 0.07) * clear;               // línea del borde
	float zebra_zone = step(road_half + 0.8, cross_d) * step(cross_d, road_half + 3.6) * step(d, road_half - 0.8);
	float zebra = zebra_zone * step(fract(d / 1.3), 0.5);              // paso de peatones
	return max(max(lanes, edge), zebra);
}

// Doble línea amarilla del centro.
float yellow_marks(float d, float cross_d) {
	return band(d, 0.22, 0.09) * step(road_half + 4.5, cross_d);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz;
	// Las calles pasan por los bordes de cada trozo. d.x = distancia al eje de
	// la calle norte-sur más cercana; d.y = a la calle este-oeste más cercana.
	vec2 local = mod(p + chunk * 0.5, chunk) - chunk * 0.5;
	vec2 d = chunk * 0.5 - abs(local);
	bool on_ns = d.x < road_half;
	bool on_ew = d.y < road_half;
	float nearest = min(d.x, d.y);

	float puddles = vnoise(p * 0.16, 64.0);
	float grain = vnoise(p * 2.3, 64.0);

	vec3 albedo;
	float rough;
	if (on_ns || on_ew) {
		// Calzada mojada: los charcos reflejan mucho (rugosidad baja).
		float puddle = smoothstep(0.5, 0.68, puddles);
		albedo = vec3(0.055, 0.058, 0.066) * (0.75 + 0.5 * grain);
		albedo = mix(albedo, vec3(0.025, 0.028, 0.036), puddle);
		rough = mix(0.42 + 0.2 * grain, 0.05, puddle);
		float white = 0.0;
		float yellow = 0.0;
		if (on_ns && !on_ew) {
			white = white_marks(d.x, p.y, d.y);
			yellow = yellow_marks(d.x, d.y);
		} else if (on_ew && !on_ns) {
			white = white_marks(d.y, p.x, d.x);
			yellow = yellow_marks(d.y, d.x);
		}
		float wear = 0.5 + 0.5 * grain;   // pintura gastada
		albedo = mix(albedo, vec3(0.45, 0.45, 0.43), white * wear);
		albedo = mix(albedo, vec3(0.5, 0.36, 0.05), yellow * wear);
		rough = mix(rough, 0.5, max(white, yellow) * 0.5);
	} else if (nearest < road_half + sidewalk) {
		// Acera con baldosas y bordillo.
		vec2 tile = fract(p / 1.5);
		float joint = min(1.0, step(tile.x, 0.04) + step(tile.y, 0.04));
		albedo = vec3(0.13, 0.13, 0.14) * (0.85 + 0.3 * grain) * (1.0 - 0.35 * joint);
		albedo = mix(albedo, vec3(0.24), band(nearest, road_half + 0.15, 0.15));
		rough = 0.7;
	} else {
		// Interior de la manzana: solo se ve en las plazas.
		vec2 tile = fract(p / 3.0);
		float joint = min(1.0, step(tile.x, 0.03) + step(tile.y, 0.03));
		albedo = vec3(0.1, 0.1, 0.115) * (0.8 + 0.4 * grain) * (1.0 - 0.4 * joint);
		rough = 0.45;
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
