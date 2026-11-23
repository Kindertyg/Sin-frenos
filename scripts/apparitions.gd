class_name Apparitions
extends Node3D
## "Sombras": figuras altas y negras, con ojos blancos, que aparecen de pie en
## mitad de la calle, por delante del coche. Te miran mientras te acercas.
## Unas se desvanecen justo antes de que llegues; otras se quedan y, si las
## atraviesas, revientan en humo negro y te frenan un poco.

signal scared(hit: bool)   ## hit = true si la has atravesado

@export var min_wait := 7.0
@export var max_wait := 15.0

var target: PlayerCar
var city: City
var active := false
var rate := 1.0             ## más alto = salen más a menudo (sube con el nivel)

var _figures: Array[Node3D] = []
var _state: Array[int] = []        # 0 escondida, 1 de pie
var _vanish_at: Array[float] = []  # se desvanece a esta distancia (0 = no se va)
var _burst: CPUParticles3D
var _wait := 6.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var black := CarFactory.flat(Color(0.0, 0.0, 0.0), 1.0)
	var eyes := CarFactory.glow(Color(1.0, 1.0, 0.95), 9.0)
	for i in 3:
		var f := Node3D.new()
		# Cuerpo flaco y demasiado alto, brazos que llegan a las rodillas.
		CarFactory.add_box(f, Vector3(0.45, 1.5, 0.25), Vector3(0.0, 1.35, 0.0), black)
		CarFactory.add_box(f, Vector3(0.12, 0.9, 0.12), Vector3(-0.08, 0.45, 0.0), black)
		CarFactory.add_box(f, Vector3(0.12, 0.9, 0.12), Vector3(0.08, 0.45, 0.0), black)
		for side: float in [-1.0, 1.0]:
			var arm := CarFactory.add_box(f, Vector3(0.09, 1.4, 0.09), Vector3(0.3 * side, 1.25, 0.0), black)
			arm.rotation.z = 0.08 * side
		CarFactory.add_box(f, Vector3(0.3, 0.38, 0.28), Vector3(0.0, 2.3, 0.0), black)
		for side: float in [-1.0, 1.0]:
			CarFactory.add_box(f, Vector3(0.06, 0.03, 0.02), Vector3(0.07 * side, 2.33, -0.15), eyes)
		f.visible = false
		add_child(f)
		_figures.append(f)
		_state.append(0)
		_vanish_at.append(0.0)

	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = 40
	_burst.lifetime = 1.2
	_burst.explosiveness = 1.0
	_burst.local_coords = false
	_burst.direction = Vector3.UP
	_burst.spread = 180.0
	_burst.initial_velocity_min = 2.0
	_burst.initial_velocity_max = 9.0
	_burst.gravity = Vector3(0.0, 1.0, 0.0)
	_burst.damping_min = 3.0
	_burst.damping_max = 5.0
	_burst.scale_amount_min = 0.6
	_burst.scale_amount_max = 1.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = black
	_burst.mesh = mesh
	add_child(_burst)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var player := target.global_position
	for i in _figures.size():
		if _state[i] != 1:
			continue
		var f := _figures[i]
		var to_player := player - f.global_position
		to_player.y = 0.0
		var d := to_player.length()
		# Siempre te está mirando.
		f.rotation.y = atan2(-to_player.x, -to_player.z)
		var local := target.global_transform.affine_inverse() * f.global_position
		if local.z > 15.0 or d > 260.0:
			_hide(i)                                   # ya ha quedado atrás
		elif _vanish_at[i] > 0.0 and d < _vanish_at[i]:
			_hide(i)
			scared.emit(false)
		elif absf(local.x) < 1.4 and absf(local.z) < 2.6:
			_burst.global_position = f.global_position + Vector3.UP * 1.3
			_burst.restart()
			_burst.emitting = true
			_hide(i)
			scared.emit(true)

	if not active:
		return
	_wait -= delta * rate
	if _wait <= 0.0:
		_wait = randf_range(min_wait, max_wait)
		_spawn(player)


func _spawn(player: Vector3) -> void:
	var free := _state.find(0)
	if free < 0 or target.speed < 10.0:
		return
	# Por delante, en la calle por la que vas, en uno de los carriles.
	var heading := target.vel.normalized()
	var p := player + heading * randf_range(75.0, 110.0)
	var lane: float = [-3.0, 0.0, 0.0, 3.0][randi() % 4]
	if absf(heading.z) > absf(heading.x):
		p.x = City.snap_to_road(p.x) + lane
	else:
		p.z = City.snap_to_road(p.z) + lane
	p.y = 0.0
	var f := _figures[free]
	f.global_position = p
	f.visible = true
	_state[free] = 1
	# La mitad se esfuma al acercarte (a 18-35 m); las demás se quedan.
	_vanish_at[free] = randf_range(18.0, 35.0) if randf() < 0.5 else 0.0


func _hide(i: int) -> void:
	_figures[i].visible = false
	_state[i] = 0
