class_name ChaseCamera
extends Camera3D
## La cámara. Dos modos (se cambia con la tecla C):
##  - Primera persona: los ojos del conductor, dentro de la cabina. La cabeza
##    se va hacia los lados en las curvas y mira hacia donde giras.
##  - Tercera persona: persigue al coche desde atrás.
## En el título y al explotar siempre da vueltas alrededor del coche ("orbit").

@export var first_person := true

@export_group("Primera persona")
@export var fp_fov := 80.0
@export var fp_speed_fov := 20.0       ## grados que se añaden a tope de velocidad
@export var look_into_turn := 0.16     ## cuánto mira la cabeza hacia la curva
@export var head_lean := 0.05          ## cuánto se inclina la cabeza en las curvas

@export_group("Tercera persona")
@export var distance := 7.2            ## metros por detrás del coche
@export var height := 2.8
@export var look_height := 1.2         ## altura del punto al que mira
@export var turn_lag := 4.0            ## rapidez con la que se coloca detrás al girar
@export var base_fov := 65.0
@export var speed_fov := 22.0

var target: PlayerCar
var shake := 0.0      ## sacudida puntual (un golpe); se apaga sola
var rumble := 0.0     ## vibración continua (la pone Main en cada frame)
var boost_kick := 0.0 ## empujón del nitro: abre el campo de visión
var orbit := false    ## true: da vueltas alrededor del coche (título y explosión)

var _yaw := 0.0
var _orbit_angle := 0.0
var _orbit_distance := 9.0
var _lean := 0.0
var _look := 0.0
var _bob := 0.0


func _ready() -> void:
	near = 0.05
	far = 600.0
	fov = base_fov
	# La movemos en _process con la posición ya suavizada del coche.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Empieza a dar vueltas alrededor del coche. `offset` = desde qué lado empieza.
func start_orbit(offset := 0.0, orbit_distance := 9.0) -> void:
	orbit = true
	_orbit_angle = _yaw + offset
	_orbit_distance = orbit_distance


## Vuelve a perseguir al coche.
func stop_orbit() -> void:
	orbit = false
	_yaw = _orbit_angle


## Coloca la cámara de golpe (sin transición) en su sitio.
func snap() -> void:
	if target == null:
		return
	_yaw = target.rotation.y
	_follow(0.0)


func _process(delta: float) -> void:
	if target != null:
		_follow(delta)


func _follow(delta: float) -> void:
	var xf := target.get_global_transform_interpolated()
	var ratio := clampf(target.speed_kmh / target.max_speed_kmh, 0.0, 1.0)
	shake = move_toward(shake, 0.0, delta * 2.5)
	var amount := shake + rumble
	boost_kick = move_toward(boost_kick, 1.0 if target.boosting else 0.0, delta * 3.0)
	var smooth := clampf(6.0 * delta, 0.0, 1.0)

	if first_person and not orbit and not target.destroyed:
		_yaw = target.rotation.y
		# La cabeza se va hacia fuera de la curva y mira hacia dentro.
		# (girando a la izquierda, steer > 0 y la inercia empuja la cabeza a la derecha)
		_lean = lerpf(_lean, clampf(target.steer * ratio + target.slip * 0.012, -1.0, 1.0), smooth)
		_look = lerpf(_look, target.steer * look_into_turn - clampf(target.slip * 0.012, -0.25, 0.25), smooth)
		_bob += delta * (4.0 + ratio * 14.0)
		var head := PlayerCar.HEAD + Vector3(_lean * head_lean, sin(_bob) * 0.006 * ratio, 0.0)
		var t := Transform3D(xf.basis, xf * head)
		t = t.rotated_local(Vector3.UP, _look)
		t = t.rotated_local(Vector3.BACK, _lean * 0.05)
		t = t.rotated_local(Vector3.RIGHT, -0.04)
		global_transform = t
		var wanted_fov := fp_fov + fp_speed_fov * ratio + boost_kick * 14.0
		fov = lerpf(fov, wanted_fov, clampf(5.0 * delta, 0.0, 1.0))
		h_offset = randf_range(-1.0, 1.0) * amount * 0.025
		v_offset = randf_range(-1.0, 1.0) * amount * 0.025
		return

	var dist := distance + ratio * 2.2
	var angle := _yaw
	if orbit:
		_orbit_angle += delta * 0.22
		angle = _orbit_angle
		dist = _orbit_distance
	else:
		_yaw = lerp_angle(_yaw, target.rotation.y, 1.0 - exp(-turn_lag * delta))
		angle = _yaw

	var focus := xf.origin + Vector3.UP * look_height
	var wanted := xf.origin + Vector3(sin(angle), 0.0, cos(angle)) * dist + Vector3.UP * (height + ratio * 0.3)

	# Que la cámara no se meta dentro de los edificios: lanzamos un rayo desde
	# el coche hasta donde queremos ponerla y, si choca, la acercamos.
	var query := PhysicsRayQueryParameters3D.create(focus, wanted, Layers.WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_pos: Vector3 = hit["position"]
		wanted = focus.lerp(hit_pos, 0.85)

	global_position = wanted
	var ahead := Vector3.ZERO
	if not orbit:
		ahead = -xf.basis.z * (2.0 + ratio * 4.0)
	look_at(focus + ahead)

	fov = lerpf(fov, base_fov + speed_fov * ratio + boost_kick * 10.0, clampf(4.0 * delta, 0.0, 1.0))
	h_offset = randf_range(-1.0, 1.0) * amount * 0.12
	v_offset = randf_range(-1.0, 1.0) * amount * 0.12
