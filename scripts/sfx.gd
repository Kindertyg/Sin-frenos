class_name Sfx
## Sonidos fabricados con matemáticas (ondas y ruido), para no necesitar
## archivos de audio. Cada sonido se calcula una sola vez y se guarda en caché.

const RATE := 22050   # muestras por segundo

static var _cache := {}


## Motor: varias ondas sumadas (armónicos) que se repiten en bucle.
## Luego el juego le cambia el tono según la velocidad.
static func engine_loop() -> AudioStreamWAV:
	if _cache.has("engine"):
		return _cache["engine"]
	var n := RATE
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in range(1, 7):
			s += sin(TAU * 60.0 * k * t + k * 0.7) / k
		s *= 0.75 + 0.25 * sin(TAU * 30.0 * t)   # un temblor grave
		buf[i] = s * 0.3
	_cache["engine"] = _to_stream(buf, RATE, n)
	return _cache["engine"]


## Ruido en bucle. "rain" = lluvia (siseo suave); "skid" = chirrido de ruedas.
static func noise_loop(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var n := int(RATE * 1.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var fast := 0.0
	var slow := 0.0
	var phase := 0.0
	for i in n:
		var white := randf_range(-1.0, 1.0)
		if kind == "skid":
			# Un tono agudo cuya frecuencia baila con el ruido.
			slow += 0.002 * (white - slow)
			phase += TAU * (1500.0 + slow * 9000.0) / RATE
			fast += 0.5 * (white - fast)
			buf[i] = sin(phase) * 0.35 + fast * 0.25
		elif kind == "nitro":
			# Siseo fuerte y agudo.
			fast += 0.8 * (white - fast)
			slow += 0.1 * (white - slow)
			buf[i] = (fast - slow) * 0.8
		else:
			# Ruido filtrado: nos quedamos con la banda media.
			fast += 0.35 * (white - fast)
			slow += 0.04 * (white - slow)
			buf[i] = (fast - slow) * 0.6
	# Fundimos el final con el principio para que el bucle no haga "clic".
	var fade := 3000
	for i in fade:
		var w := float(i) / fade
		buf[i] = buf[i] * w + buf[n - fade + i] * (1.0 - w)
	_cache[kind] = _to_stream(buf, RATE, n - fade)
	return _cache[kind]


## Pitido de la bomba.
static func beep() -> AudioStreamWAV:
	if _cache.has("beep"):
		return _cache["beep"]
	var n := int(RATE * 0.09)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 400.0) * exp(-t * 28.0)
		buf[i] = (sin(TAU * 1400.0 * t) + 0.4 * sin(TAU * 2800.0 * t)) * env * 0.5
	_cache["beep"] = _to_stream(buf, RATE)
	return _cache["beep"]


## Golpe contra algo.
static func crash() -> AudioStreamWAV:
	if _cache.has("crash"):
		return _cache["crash"]
	var n := int(RATE * 0.4)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += 0.3 * (randf_range(-1.0, 1.0) - lp)
		var thump := sin(TAU * 95.0 * t) * exp(-t * 16.0)
		buf[i] = tanh((lp * exp(-t * 12.0) * 1.8 + thump) * 1.5) * 0.8
	_cache["crash"] = _to_stream(buf, RATE)
	return _cache["crash"]


## La explosión: ruido que se va apagando y oscureciendo, más un golpe grave.
static func explosion() -> AudioStreamWAV:
	if _cache.has("explosion"):
		return _cache["explosion"]
	var n := int(RATE * 2.4)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += lerpf(0.5, 0.04, clampf(t / 1.2, 0.0, 1.0)) * (randf_range(-1.0, 1.0) - lp)
		phase += TAU * (36.0 + 70.0 * exp(-t * 6.0)) / RATE
		var boom := sin(phase) * exp(-t * 2.6)
		buf[i] = tanh((lp * 2.4 * exp(-t * 2.0) + boom) * 1.6) * 0.9
	_cache["explosion"] = _to_stream(buf, RATE)
	return _cache["explosion"]


## Trueno lejano.
static func thunder() -> AudioStreamWAV:
	if _cache.has("thunder"):
		return _cache["thunder"]
	var rate := 11025
	var n := int(rate * 3.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		lp += 0.06 * (randf_range(-1.0, 1.0) - lp)
		var rumble := 0.6 + 0.4 * sin(t * 9.0) * sin(t * 3.1)
		buf[i] = tanh(lp * 6.0 * rumble * minf(1.0, t * 8.0) * exp(-t * 1.1)) * 0.8
	_cache["thunder"] = _to_stream(buf, rate)
	return _cache["thunder"]


## Latido del corazón: "pum-pum" grave.
static func heartbeat() -> AudioStreamWAV:
	if _cache.has("heart"):
		return _cache["heart"]
	var n := int(RATE * 0.45)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for hit: float in [0.0, 0.17]:
			var u := t - hit
			if u >= 0.0:
				var amp := 1.0 if hit == 0.0 else 0.7
				s += sin(TAU * (48.0 + 30.0 * exp(-u * 30.0)) * u) * exp(-u * 18.0) * amp
		buf[i] = tanh(s * 1.8) * 0.9
	_cache["heart"] = _to_stream(buf, RATE)
	return _cache["heart"]


## Zumbido de tensión: notas graves desafinadas entre sí que "laten" despacio.
static func drone_loop() -> AudioStreamWAV:
	if _cache.has("drone"):
		return _cache["drone"]
	var n := RATE * 4
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		# Frecuencias que caben un número exacto de veces en 4 s: el bucle no salta.
		for f: float in [41.0, 41.5, 61.75, 87.25, 123.5]:
			s += sin(TAU * f * t + sin(TAU * 0.25 * t) * 0.8)
		lp += 0.05 * (randf_range(-1.0, 1.0) - lp)
		buf[i] = tanh(s * 0.35 + lp * 0.6) * 0.5
	_cache["drone"] = _to_stream(buf, RATE, n)
	return _cache["drone"]


## Golpe de susto: acorde agudo disonante + ruido que crece de golpe.
static func sting() -> AudioStreamWAV:
	if _cache.has("sting"):
		return _cache["sting"]
	var n := int(RATE * 1.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t * 60.0) * exp(-t * 2.2)
		var s := 0.0
		for f: float in [880.0, 932.0, 1245.0, 1318.0, 1975.0]:
			s += sin(TAU * f * t + 3.0 * sin(TAU * 7.0 * t))
		var white := randf_range(-1.0, 1.0)
		hp = 0.9 * (hp + white - prev)     # ruido agudo
		prev = white
		buf[i] = tanh((s * 0.25 + hp * 0.5) * env * 1.6) * 0.85
	_cache["sting"] = _to_stream(buf, RATE)
	return _cache["sting"]


## Estática de radio, a trozos.
static func static_burst() -> AudioStreamWAV:
	if _cache.has("static"):
		return _cache["static"]
	var n := int(RATE * 0.7)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var gate := 1.0
	for i in n:
		if i % 600 == 0:
			gate = 1.0 if randf() < 0.7 else 0.15
		var t := float(i) / RATE
		buf[i] = randf_range(-1.0, 1.0) * gate * 0.5 * minf(1.0, (0.7 - t) * 6.0)
	_cache["static"] = _to_stream(buf, RATE)
	return _cache["static"]


## "Fiuuu" al pasar rozando un coche: ruido que sube y baja de tono.
static func whoosh() -> AudioStreamWAV:
	if _cache.has("whoosh"):
		return _cache["whoosh"]
	var n := int(RATE * 0.5)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var cut := 0.05 + 0.5 * sin(PI * t / 0.5)
		lp += cut * (randf_range(-1.0, 1.0) - lp)
		buf[i] = lp * sin(PI * t / 0.5) * 1.4
	_cache["whoosh"] = _to_stream(buf, RATE)
	return _cache["whoosh"]


## "Ding" de puntos (dos notas rápidas hacia arriba).
static func ding() -> AudioStreamWAV:
	if _cache.has("ding"):
		return _cache["ding"]
	var n := int(RATE * 0.35)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 1320.0 if t < 0.07 else 1760.0
		var u := t if t < 0.07 else t - 0.07
		buf[i] = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-u * 14.0) * 0.4
	_cache["ding"] = _to_stream(buf, RATE)
	return _cache["ding"]


## Convierte una lista de muestras (-1..1) en un sonido que Godot puede tocar.
## Si `loop_end` es mayor que 0, el sonido se repite en bucle hasta esa muestra.
static func _to_stream(samples: PackedFloat32Array, rate: int, loop_end := 0) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if loop_end > 0:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = loop_end
	return stream
