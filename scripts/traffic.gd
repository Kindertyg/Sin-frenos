class_name Traffic
extends Node3D
## Tráfico: unos cuantos coches que circulan en línea recta por las calles.
## No se crean y destruyen: hay un grupo fijo ("pool") y, cuando uno queda
## lejos o fuera del camino del jugador, se recoloca por delante entre la niebla.
##
## También detecta los "casi choques": pasar rozando un coche sin tocarlo.

signal near_miss(car: Knockable)

@export var max_cars := 22
@export var lane_offset := 3.0          ## metros desde el centro de la calle hasta su carril
@export var min_speed_kmh := 40.0
@export var max_speed_kmh := 75.0
@export var near_miss_gap := 3.3        ## distancia lateral (entre centros) que cuenta como "casi"
@export var spawn_near := 210.0         ## distancia mínima a la que aparecen (que no se vea)
@export var spawn_far := 330.0

var target: PlayerCar
var city: City            ## para saber qué calles están cortadas
var active := false       ## Main lo enciende al empezar a conducir
var density := 0.6        ## parte del grupo que está en uso (sube con el nivel)

var _cars: Array[Knockable] = []
var _in_use: Array[bool] = []
var _prev_side: Array[float] = []   # lado (delante/detrás) del jugador respecto a cada coche
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i in max_cars:
		var car := Knockable.new()
		car.penalty = 0.28
		car.mass = 900.0
		car.add_box_collider(Vector3(CarFactory.WIDTH, 1.2, CarFactory.LENGTH), Vector3(0.0, 0.7, 0.0))
		car.add_child(CarFactory.build_simple(CarFactory.random_paint(_rng), true))
		add_child(car)
		_cars.append(car)
		_in_use.append(false)
		_prev_side.append(0.0)
		_retire(i)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var player := target.global_position
	var heading := _player_heading()
	var wanted := roundi(max_cars * density) if active else 0
	var used := 0
	var free_slot := -1

	for i in _cars.size():
		if not _in_use[i]:
			free_slot = i
			continue
		var car := _cars[i]
		var to_car := car.global_position - player
		to_car.y = 0.0
		var dist := to_car.length()

		if car.knocked:
			# Coche siniestrado: se queda un rato y luego vuelve al grupo.
			var age := Time.get_ticks_msec() / 1000.0 - car.knocked_at
			if dist > 150.0 or (age > 8.0 and dist > 60.0):
				_retire(i)
			continue

		# Si la calle está cortada más adelante, se queda parado antes del cruce.
		if city != null and car.cruise_velocity != Vector3.ZERO:
			if city.closure_ahead(car.global_position, car.cruise_velocity.normalized(), 60.0) < 31.0:
				car.cruise_velocity = Vector3.ZERO
		car.global_position += car.cruise_velocity * delta
		used += 1
		# Lejos y fuera del camino del jugador: ya no pinta nada ahí.
		var in_front := to_car.dot(heading) / maxf(dist, 0.01)
		if dist > 380.0 or (dist > 190.0 and in_front < 0.3) or (dist > 110.0 and in_front < -0.5):
			_retire(i)
			continue
		# Seguro extra: si la física no ha detectado el toque, lo vemos por distancia.
		var local := car.global_transform.affine_inverse() * player
		if absf(local.x) < 1.7 and absf(local.z) < 4.0 and not target.destroyed:
			target.hit_prop(car, target.vel)
			continue
		# Casi choque: el jugador pasa de estar delante a detrás del coche (o al
		# revés) muy cerca de su costado, yendo rápido.
		var side := signf(local.z)
		if _prev_side[i] != 0.0 and side != _prev_side[i] and absf(local.x) < near_miss_gap and target.speed_kmh > 70.0:
			near_miss.emit(car)
		_prev_side[i] = side

	if used < wanted and free_slot >= 0:
		_try_spawn(free_slot, player, heading)


func _player_heading() -> Vector3:
	if target.speed > 3.0:
		return target.vel.normalized()
	return -target.global_transform.basis.z


## Intenta colocar un coche por delante del jugador, en el carril de una calle.
func _try_spawn(i: int, player: Vector3, heading: Vector3) -> void:
	var right := Vector3(-heading.z, 0.0, heading.x)
	var p := player + heading * _rng.randf_range(spawn_near, spawn_far) + right * _rng.randf_range(-130.0, 130.0)
	var dir := Vector3.ZERO
	var north_south := _rng.randf() < 0.5
	if north_south:
		p.x = City.snap_to_road(p.x)
		dir.z = 1.0 if _rng.randf() < 0.5 else -1.0
	else:
		p.z = City.snap_to_road(p.z)
		dir.x = 1.0 if _rng.randf() < 0.5 else -1.0
	# Ni dentro de un tramo cortado ni a punto de llegar a uno.
	if city != null and (city.is_inside_closure(p, north_south) or city.closure_ahead(p, dir, 80.0) < 80.0):
		return
	# Circulan por la derecha.
	p += Vector3(-dir.z, 0.0, dir.x) * lane_offset
	p.y = 0.0
	if p.distance_to(player) < spawn_near - 20.0:
		return
	for j in _cars.size():
		if _in_use[j] and _cars[j].global_position.distance_to(p) < 16.0:
			return

	var car := _cars[i]
	car.reset_as_kinematic()
	car.cruise_velocity = dir * _rng.randf_range(min_speed_kmh, max_speed_kmh) / 3.6
	car.global_position = p
	car.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	car.reset_physics_interpolation()
	car.visible = true
	_in_use[i] = true
	_prev_side[i] = 0.0


## Devuelve el coche al grupo: invisible, sin colisión y aparcado bajo tierra.
func _retire(i: int) -> void:
	var car := _cars[i]
	car.reset_as_kinematic()
	car.collision_layer = 0
	car.cruise_velocity = Vector3.ZERO
	car.visible = false
	car.global_position = Vector3(0.0, -200.0 - i * 10.0, 0.0)
	car.reset_physics_interpolation()
	_in_use[i] = false
