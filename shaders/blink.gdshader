shader_type spatial;
// Luz que parpadea (antenas de los rascacielos, vallas de obra).

uniform vec3 color : source_color = vec3(1.0, 0.08, 0.04);
uniform float speed = 0.8;      // parpadeos por segundo
uniform float energy = 4.0;

varying flat float phase;

void vertex() {
	// Cada luz empieza en un momento distinto según dónde está.
	phase = fract(MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.11);
}

void fragment() {
	float on = step(0.5, fract(TIME * speed + phase));
	ALBEDO = color * 0.12;
	EMISSION = color * energy * on;
}
