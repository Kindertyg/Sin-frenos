shader_type spatial;
// Fachada de edificio: dibuja ventanas sobre un cubo liso, sin texturas.
// Cada edificio es un cubo de 1x1x1 escalado, así que su escala ES su tamaño
// en metros; con eso repartimos las ventanas para que encajen justas.

uniform vec3 wall_color : source_color = vec3(0.22, 0.235, 0.29);
uniform float window_energy = 0.9;

varying vec3 l_pos;          // posición dentro del edificio, en metros
varying vec3 l_nrm;          // hacia dónde mira la cara
varying flat vec3 b_size;    // tamaño del edificio
varying flat float b_seed;   // número al azar distinto para cada edificio

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void vertex() {
	b_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	l_pos = VERTEX * b_size;
	l_nrm = NORMAL;
	b_seed = hash21(MODEL_MATRIX[3].xz * 0.37 + vec2(b_size.y, MODEL_MATRIX[3].y));
}

void fragment() {
	vec3 an = abs(l_nrm);
	// Cada edificio tiene un tono un poco distinto.
	vec3 albedo = wall_color * (0.55 + 0.9 * b_seed) * mix(vec3(1.0, 0.92, 0.85), vec3(0.85, 0.95, 1.1), fract(b_seed * 7.3));
	vec3 emission = vec3(0.0);
	float rough = 0.9;

	if (an.y < 0.5) {
		// Es una pared (no el tejado).
		bool side_x = an.x > 0.5;
		float face_w = side_x ? b_size.z : b_size.x;
		float u = (side_x ? l_pos.z : l_pos.x) + face_w * 0.5;   // metros desde la esquina
		float v = l_pos.y + b_size.y * 0.5;                      // metros desde el suelo
		float cols = max(1.0, floor(face_w / 3.2));
		float rows = max(1.0, floor(b_size.y / 3.4));
		vec2 g = vec2(u / face_w * cols, v / b_size.y * rows);
		vec2 id = floor(g);       // qué ventana es
		vec2 f = fract(g);        // posición dentro de su hueco (0..1)
		float face_id = side_x ? 1.0 : 2.0;
		face_id += l_nrm.x + l_nrm.z > 0.0 ? 0.0 : 4.0;
		float r = hash21(id + vec2(b_seed * 91.7, face_id * 13.1));

		if (id.y < 0.5) {
			// Planta baja: algunos edificios tienen escaparates iluminados.
			float shop = step(0.55, fract(b_seed * 3.1));
			float glass = step(0.06, f.x) * step(f.x, 0.94) * step(0.12, f.y) * step(f.y, 0.78);
			float lit = step(0.45, r) * shop;
			vec3 shop_col = mix(vec3(1.0, 0.7, 0.35), vec3(0.4, 0.8, 1.0), step(0.7, fract(r * 5.7)));
			albedo = mix(albedo, vec3(0.015, 0.02, 0.03), glass);
			emission = shop_col * glass * lit * window_energy * 0.5;
			rough = mix(rough, 0.2, glass);
		} else {
			float glass = step(0.24, f.x) * step(f.x, 0.76) * step(0.3, f.y) * step(f.y, 0.74);
			// Unos edificios casi a oscuras y otros con muchas luces.
			float lit_ratio = mix(0.04, 0.4, b_seed * b_seed);
			float lit = step(1.0 - lit_ratio, r);
			vec3 warm = vec3(1.0, 0.55, 0.18);
			vec3 cold = vec3(0.4, 0.68, 1.0);
			float is_cold = step(0.8, fract(r * 7.31));
			// Las azuladas parpadean un poco, como una tele encendida.
			float tv = mix(1.0, 0.75 + 0.25 * sin(TIME * 9.0 + r * 80.0) * sin(TIME * 2.3 + r * 40.0), is_cold);
			albedo = mix(albedo, vec3(0.015, 0.02, 0.03), glass);
			emission = mix(warm, cold, is_cold) * glass * lit * (0.5 + 0.9 * fract(r * 3.7)) * tv * window_energy;
			rough = mix(rough, 0.2, glass);
		}
	}

	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = rough;
}
