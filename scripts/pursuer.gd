class_name Pursuer
extends Node3D
## "ÉL": un coche negro, sin luces, con dos ojos rojos, que te sigue.
##
## No conduce de verdad: va exactamente por el mismo camino que has hecho tú,
## a `gap` metros por detrás. Ese hueco crece si vas más rápido que él y se
## encoge si vas más lento (por ejemplo, después de chocar). Si llega a 0, te
## ha alcanzado. Como es "sobrenatural", atraviesa todo.

signal caught

@export var start_gap := 170.0     ## metros de ventaja al aparecer
@export var max_gap := 230.0       ## por mucho que corras, no se queda más atrás que esto
@export var catch_gap := 5.0       ## a esta distancia te ha alcanzado

var target: PlayerCar
var active := false
var speed_kmh := 90.0              ## velocidad a la que te persigue (la pone Main)
var gap := 170.0

var _trail: PackedVector3Array = []    # puntos por los que ha pasado el jugador
var _trail_d: PackedFloat32Array = []  # metros recorridos al llegar a cada punto
var _total := 0.0
var _model: Node3D
var _beams: SpotLight3D
var _eyes_mat: StandardMaterial3D
var _growl: AudioStreamPlayer3D


func _ready() -> void:
	_model = CarFactory.build_simple(Color(0.012, 0.012, 0.014), false)
	add_child(_model)
	# Los ojos: dos puntitos rojos donde deberían estar los faros.
	_eyes_mat = CarFactory.glow(Color(1.0, 0.05, 0.03), 9.0, false)
	for side: float in [-1.0, 1.0]:
		CarFactory.add_box(_model, Vector3(0.12, 0.06, 0.05), Vector3(0.6 * side, 0.7, -CarFactory.LENGTH * 0.5 - 0.04), _eyes_mat)
	# Largas que se encienden cuando está muy cerca y te ciegan por detrás.
	_beams = SpotLight3D.new()
	_beams.position = Vector3(0.0, 1.0, -2.4)
	_beams.light_color = Color(1.0, 0.85, 0.8)
	_beams.light_energy = 0.0
	_beams.spot_range = 60.0
	_beams.spot_angle = 30.0
	add_child(_beams)
	# Su motor: un gruñido grave que suena desde donde está.
	_growl = AudioStreamPlayer3D.new()
	_growl.stream = Sfx.engine_loop()
	_growl.pitch_scale = 0.45
	_growl.unit_size = 18.0
	_growl.max_db = 4.0
	_growl.volume_db = -4.0
	add_child(_growl)
	visible = false


## Empieza la persecución.
func start() -> void:
	active = true
	gap = start_gap
	visible = true
	_growl.play()


func stop() -> void:
	active = false
	_growl.stop()


## 0 = lejos, 1 = encima. Main lo usa para el miedo y el latido.
func closeness() -> float:
	if not active:
		return 0.0
	return clampf(1.0 - (gap - catch_gap) / 110.0, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_record()
	if not active:
		return
	gap = minf(gap + (target.speed - speed_kmh / 3.6) * delta, max_gap)
	if gap <= catch_gap and not target.destroyed:
		stop()
		caught.emit()
		return
	_place(_total - gap)
	var near := closeness()
	_beams.light_energy = 0.0 if near < 0.55 else (near - 0.55) * 60.0
	_eyes_mat.emission_energy_multiplier = 6.0 + near * 14.0 + randf() * 3.0


## Apunta por dónde va pasando el jugador (un punto cada medio metro).
func _record() -> void:
	var p := target.global_position
	if _trail.is_empty():
		_trail.append(p)
		_trail_d.append(0.0)
		return
	var step := p.distance_to(_trail[_trail.size() - 1])
	if step < 0.5:
		return
	_total += step
	_trail.append(p)
	_trail_d.append(_total)
	# Lo que queda muy atrás ya no sirve.
	if _trail.size() > 1400:
		_trail = _trail.slice(400)
		_trail_d = _trail_d.slice(400)


## Coloca el coche en el punto del camino que está a `d` metros del principio.
func _place(d: float) -> void:
	if _trail.size() < 2:
		return
	var i := _trail_d.bsearch(d)
	i = clampi(i, 1, _trail.size() - 1)
	var a := _trail[i - 1]
	var b := _trail[i]
	var span := maxf(_trail_d[i] - _trail_d[i - 1], 0.001)
	var t := clampf((d - _trail_d[i - 1]) / span, 0.0, 1.0)
	var pos := a.lerp(b, t)
	var dir := b - a
	global_position = pos
	if dir.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.3)
