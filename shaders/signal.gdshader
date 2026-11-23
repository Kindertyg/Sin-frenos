shader_type spatial;
// Semáforo: tres luces (roja arriba, ámbar, verde abajo) que van cambiando
// solas con el tiempo. "phase" desplaza el ciclo: las dos calles de un cruce
// usan 0.0 y 0.5 para que una esté en verde cuando la otra está en rojo.

uniform float phase = 0.0;
uniform float cycle = 18.0;   // segundos que dura una vuelta completa

varying vec3 l_pos;
varying flat vec3 b_size;

void vertex() {
	b_size = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	l_pos = VERTEX * b_size;
}

void fragment() {
	float t = fract(TIME / cycle + phase);
	float lit_slot = t < 0.45 ? 2.0 : (t < 0.5 ? 1.0 : 0.0);   // 0 rojo, 1 ámbar, 2 verde

	float v = 1.0 - (l_pos.y / b_size.y + 0.5);    // 0 arriba .. 1 abajo
	float slot = floor(v * 3.0);
	float slot_h = b_size.y / 3.0;
	float across = b_size.x > b_size.z ? l_pos.x : l_pos.z;
	vec2 from_center = vec2(across, (fract(v * 3.0) - 0.5) * slot_h);
	float lamp = step(length(from_center), 0.15);

	vec3 color = vec3(1.0, 0.05, 0.03);
	if (slot > 1.5) {
		color = vec3(0.1, 1.0, 0.4);
	} else if (slot > 0.5) {
		color = vec3(1.0, 0.6, 0.05);
	}
	float on = lamp * step(abs(slot - lit_slot), 0.5);
	ALBEDO = mix(vec3(0.01), color * 0.08, lamp);
	EMISSION = color * on * 3.5;
	ROUGHNESS = 0.6;
}
