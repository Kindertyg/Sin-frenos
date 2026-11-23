shader_type spatial;
// Cartel de neón: sobre una caja oscura dibuja "letras" inventadas hechas de
// cuadraditos luminosos (cada letra es una rejilla de 3x5 al azar).

instance uniform vec4 neon_color : source_color = vec4(1.0, 0.15, 0.6, 1.0);
uniform float energy = 3.0;

varying vec3 l_pos;
varying vec3 l_nrm;
varying flat vec3 b_size;
varying flat float b_seed;

float hash21(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

void vertex() {
	b_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	l_pos = VERTEX * b_size;
	l_nrm = NORMAL;
	b_seed = hash21(MODEL_MATRIX[3].xz * 0.37 + vec2(MODEL_MATRIX[3].y, b_size.y));
}

void fragment() {
	vec3 an = abs(l_nrm);
	vec3 emission = vec3(0.0);
	// Las dos caras grandes del cartel son las perpendiculares a su lado más fino.
	bool thin_x = b_size.x < b_size.z;
	bool front = thin_x ? an.x > 0.5 : an.z > 0.5;
	if (front) {
		float w = thin_x ? b_size.z : b_size.x;
		float h = b_size.y;
		vec2 uv = vec2((thin_x ? l_pos.z : l_pos.x) + w * 0.5, l_pos.y + h * 0.5);
		bool vertical = h > w;
		float cell = vertical ? w : h;                 // cada letra es cuadrada
		float along = vertical ? uv.y : uv.x;
		float across = vertical ? uv.x : uv.y;
		float id = floor(along / cell);
		// Posición dentro de la letra, con x a lo ancho e y hacia arriba.
		vec2 g = vertical ? vec2(across / cell, fract(along / cell)) : vec2(fract(along / cell), across / cell);
		vec2 m = (g - 0.5) / 0.7 + 0.5;                // margen alrededor de la letra
		if (m.x > 0.0 && m.x < 1.0 && m.y > 0.0 && m.y < 1.0) {
			vec2 grid = m * vec2(3.0, 5.0);
			vec2 px = floor(grid);
			vec2 pf = fract(grid);
			float on = step(0.42, hash21(px + vec2(id * 7.0 + 1.0, b_seed * 31.0)));
			float dot_mask = step(0.12, pf.x) * step(pf.x, 0.88) * step(0.12, pf.y) * step(pf.y, 0.88);
			float flicker = 0.85 + 0.15 * sin(TIME * 23.0 + b_seed * 50.0);
			emission = neon_color.rgb * on * dot_mask * energy * flicker;
		}
	}
	ALBEDO = vec3(0.012);
	ROUGHNESS = 0.5;
	EMISSION = emission;
}
