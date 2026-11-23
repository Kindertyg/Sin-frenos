class_name City
extends Node3D
## Ciudad infinita.
##
## El mundo se divide en trozos cuadrados ("chunks"). Cada trozo es una manzana
## con sus edificios en el centro, y las calles pasan por sus bordes. Solo
## existen los trozos cercanos al jugador: al avanzar se crean los de delante y
## se borran los que quedan atrás (la niebla tapa el borde).
##
## Lo que hay en cada trozo se decide con números "al azar" sacados de sus
## coordenadas, así que si vuelves al mismo sitio encuentras lo mismo.

const CHUNK := 80.0          # distancia entre calles (m)
const ROAD_HALF := 10.0      # media anchura de la calzada
const SIDEWALK := 3.0        # anchura de la acera
const BLOCK_HALF := CHUNK * 0.5 - ROAD_HALF - SIDEWALK   # media anchura de la zona de edificios
const LAMP_HEIGHT := 7.5
const CLOSURE_INSET := 15.0   # del centro del cruce al muro de una calle cortada

const NEON_COLORS: Array[Color] = [
	Color(1.0, 0.1, 0.55), Color(0.1, 0.85, 1.0), Color(1.0, 0.25, 0.1),
	Color(0.35, 1.0, 0.4), Color(0.7, 0.3, 1.0), Color(1.0, 0.75, 0.15),
]
# Los cuatro lados de una manzana (hacia dónde mira cada uno).
const SIDES: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]

@export var view_radius := 4                              ## trozos cargados alrededor del jugador
@export var chunks_per_frame := 2                         ## trozos nuevos por frame (para no dar tirones)
@export var world_seed := 2024                            ## cambia este número y sale otra ciudad
@export_range(0.0, 1.0) var plaza_chance := 0.1           ## manzanas que son plaza abierta
@export_range(0.0, 1.0) var parked_density := 0.5         ## cuántos coches aparcados
@export_range(0.0, 1.0) var roadworks_chance := 0.1       ## lados de manzana con obras
@export_range(0.0, 1.0) var closure_chance := 0.75        ## calles cortadas (0 = ninguna, 1 = todas las posibles)

var target: Node3D

## Corriente de la ciudad: 1 = normal, 0 = apagón total. La cambia set_power().
static var power := 1.0

var _chunks := {}                  # Vector2i -> Node3D
var _queue: Array[Vector2i] = []   # trozos pendientes de crear, del más cercano al más lejano
var _center := Vector2i(999999, 999999)

# Recursos compartidos por todos los trozos.
var _ground_mesh: PlaneMesh
var _building_mat: ShaderMaterial
var _neon_mat: ShaderMaterial
var _signal_mats: Array[ShaderMaterial] = []
var _blink_red: ShaderMaterial
var _blink_amber: ShaderMaterial
var _block_shape: BoxShape3D
var _monument_shape: BoxShape3D
var _closure_shape: BoxShape3D
var _concrete: StandardMaterial3D
var _closure_glow: StandardMaterial3D
var _closure_white: StandardMaterial3D
var _metal: StandardMaterial3D
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D


## Calle más cercana a una coordenada (sirve para X y para Z).
static func snap_to_road(v: float) -> float:
	return roundf((v - CHUNK * 0.5) / CHUNK) * CHUNK + CHUNK * 0.5


static func world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / CHUNK), roundi(pos.z / CHUNK))


func _ready() -> void:
	power = 1.0
	_ground_mesh = PlaneMesh.new()
	_ground_mesh.size = Vector2(CHUNK, CHUNK)
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = preload("res://shaders/ground.gdshader")
	ground_mat.set_shader_parameter("chunk", CHUNK)
	ground_mat.set_shader_parameter("road_half", ROAD_HALF)
	ground_mat.set_shader_parameter("sidewalk", SIDEWALK)
	_ground_mesh.material = ground_mat

	_building_mat = ShaderMaterial.new()
	_building_mat.shader = preload("res://shaders/building.gdshader")
	_neon_mat = ShaderMaterial.new()
	_neon_mat.shader = preload("res://shaders/neon.gdshader")
	for phase: float in [0.0, 0.5]:
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/signal.gdshader")
		m.set_shader_parameter("phase", phase)
		_signal_mats.append(m)
	_blink_red = ShaderMaterial.new()
	_blink_red.shader = preload("res://shaders/blink.gdshader")
	_blink_amber = ShaderMaterial.new()
	_blink_amber.shader = preload("res://shaders/blink.gdshader")
	_blink_amber.set_shader_parameter("color", Color(1.0, 0.55, 0.05))
	_blink_amber.set_shader_parameter("speed", 1.6)

	_block_shape = BoxShape3D.new()
	_block_shape.size = Vector3(BLOCK_HALF * 2.0, 60.0, BLOCK_HALF * 2.0)
	_monument_shape = BoxShape3D.new()
	_monument_shape.size = Vector3(8.0, 12.0, 8.0)
	_closure_shape = BoxShape3D.new()
	_closure_shape.size = Vector3((ROAD_HALF + SIDEWALK) * 2.0, 2.0, 1.0)
	_concrete = CarFactory.flat(Color(0.45, 0.45, 0.47), 0.85)
	_closure_glow = CarFactory.glow(Color(1.0, 0.12, 0.06), 1.8)
	_closure_white = CarFactory.glow(Color(1.0, 0.95, 0.9), 0.9)
	_metal = CarFactory.flat(Color(0.16, 0.16, 0.18), 0.5, 0.6)
	_lamp_on = CarFactory.glow(Color(1.0, 0.6, 0.25), 2.5)
	_lamp_off = CarFactory.flat(Color(0.2, 0.17, 0.14))

	# Suelo físico infinito. El coche no lo necesita (no tiene gravedad):
	# solo lo usan los restos que salen volando.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.GROUND
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	add_child(floor_body)


func _process(_delta: float) -> void:
	if target == null:
		return
	var here := world_to_chunk(target.global_position)
	if here != _center:
		_center = here
		_refresh()
	for i in chunks_per_frame:
		if _queue.is_empty():
			break
		var key: Vector2i = _queue.pop_front()
		if not _chunks.has(key):
			_chunks[key] = _build_chunk(key)


## Crea de golpe todos los trozos alrededor del jugador (al empezar la partida).
func prewarm() -> void:
	_center = world_to_chunk(target.global_position)
	_refresh()
	while not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		_chunks[key] = _build_chunk(key)


## Borra los trozos lejanos y apunta los que faltan por crear.
func _refresh() -> void:
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - _center.x), absi(key.y - _center.y)) > view_radius + 1:
			_chunks[key].queue_free()
			_chunks.erase(key)
	_queue.clear()
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			var key := _center + Vector2i(dx, dz)
			if not _chunks.has(key):
				_queue.append(key)
	var center := _center
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())


func _is_plaza(key: Vector2i) -> bool:
	return (hash(Vector3i(key.x, key.y, world_seed)) & 0xffff) / 65535.0 < plaza_chance


func _build_chunk(key: Vector2i) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + world_seed

	var root := Node3D.new()
	root.position = Vector3(key.x * CHUNK, 0.0, key.y * CHUNK)
	# Nada de esto se mueve: no hace falta suavizar su movimiento.
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	var ground := MeshInstance3D.new()
	ground.mesh = _ground_mesh
	root.add_child(ground)

	var plaza := _is_plaza(key)
	if plaza:
		_build_plaza(root)
	else:
		_build_block(root, rng)

	for normal: Vector3 in SIDES:
		var tangent := Vector3(-normal.z, 0.0, normal.x)   # dirección a lo largo de ese lado
		if rng.randf() < 0.85:
			_add_lamp(root, rng, normal, tangent)
		if not plaza and rng.randf() < 0.6:
			_add_neon(root, rng, normal, tangent)
		if rng.randf() < roadworks_chance:
			_add_roadworks(root, rng, normal, tangent)
		else:
			_add_parked_cars(root, rng, normal, tangent)
	_add_signal(root, key)

	# Calles cortadas. Cada trozo se ocupa de la calle de su lado +X y de la
	# de su lado +Z; el muro va en los dos extremos del tramo.
	var half := CHUNK * 0.5
	if is_closed_ns(key.x, key.y - 1):
		for end: float in [-1.0, 1.0]:
			_add_closure(root, Vector3(half, 0.0, end * (half - CLOSURE_INSET)), false)
	if is_closed_ew(key.x - 1, key.y):
		for end: float in [-1.0, 1.0]:
			_add_closure(root, Vector3(end * (half - CLOSURE_INSET), 0.0, half), true)

	add_child(root)
	return root


# ---------------------------------------------------------------- manzanas

func _build_block(root: Node3D, rng: RandomNumberGenerator) -> void:
	# Colisión: toda la manzana es un único bloque sólido (rápido y sin huecos).
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _block_shape
	cs.position.y = _block_shape.size.y * 0.5
	body.add_child(cs)
	root.add_child(body)

	# La manzana se reparte en solares, y cada solar lleva un edificio.
	var widths := _split(BLOCK_HALF * 2.0, _lot_count(rng), rng)
	var depths := _split(BLOCK_HALF * 2.0, _lot_count(rng), rng)
	var z := -BLOCK_HALF
	for depth in depths:
		var x := -BLOCK_HALF
		for width in widths:
			_add_building(root, rng, Vector3(x + width * 0.5, 0.0, z + depth * 0.5), width, depth)
			x += width
		z += depth


func _lot_count(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.2:
		return 1
	return 2 if r < 0.75 else 3


## Reparte `total` metros en `parts` trozos de tamaño parecido pero no igual.
func _split(total: float, parts: int, rng: RandomNumberGenerator) -> Array[float]:
	var sizes: Array[float] = []
	var sum := 0.0
	for i in parts:
		var w := rng.randf_range(0.7, 1.3)
		sizes.append(w)
		sum += w
	for i in parts:
		sizes[i] = sizes[i] / sum * total
	return sizes


func _add_building(root: Node3D, rng: RandomNumberGenerator, center: Vector3, sx: float, sz: float) -> void:
	var h := rng.randf_range(9.0, 24.0)
	if rng.randf() < 0.3:
		h = rng.randf_range(30.0, 70.0)        # rascacielos
	CarFactory.add_box(root, Vector3(sx, h, sz), center + Vector3.UP * h * 0.5, _building_mat)

	var top := h
	var top_size := Vector2(sx, sz)
	# Algunos llevan encima una torre más estrecha.
	if rng.randf() < 0.35 and minf(sx, sz) > 14.0:
		var th := rng.randf_range(8.0, 34.0)
		top_size = Vector2(sx * rng.randf_range(0.45, 0.8), sz * rng.randf_range(0.45, 0.8))
		CarFactory.add_box(root, Vector3(top_size.x, th, top_size.y), center + Vector3.UP * (h + th * 0.5), _building_mat)
		top = h + th

	# Trastos de azotea.
	if rng.randf() < 0.6:
		var s := rng.randf_range(2.0, 4.0)
		var off := Vector3(rng.randf_range(-0.25, 0.25) * top_size.x, top + 0.8, rng.randf_range(-0.25, 0.25) * top_size.y)
		CarFactory.add_box(root, Vector3(s, 1.6, s), center + off, _metal)
	# Los más altos llevan antena con luz roja.
	if top > 42.0:
		var mast := rng.randf_range(5.0, 11.0)
		CarFactory.add_box(root, Vector3(0.25, mast, 0.25), center + Vector3.UP * (top + mast * 0.5), _metal)
		CarFactory.add_box(root, Vector3(0.5, 0.5, 0.5), center + Vector3.UP * (top + mast), _blink_red)


func _build_plaza(root: Node3D) -> void:
	# Plaza abierta: se puede cruzar con el coche. En el centro, un monumento.
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _monument_shape
	cs.position.y = _monument_shape.size.y * 0.5
	body.add_child(cs)
	root.add_child(body)
	var stone := CarFactory.flat(Color(0.3, 0.3, 0.33), 0.6)
	var teal := Color(0.2, 0.9, 0.8)
	CarFactory.add_box(root, Vector3(8.0, 0.9, 8.0), Vector3(0.0, 0.45, 0.0), stone)
	CarFactory.add_box(root, Vector3(4.5, 11.0, 4.5), Vector3(0.0, 6.4, 0.0), stone)
	CarFactory.add_box(root, Vector3(4.7, 0.4, 4.7), Vector3(0.0, 12.1, 0.0), CarFactory.glow(teal, 2.5))
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var light := OmniLight3D.new()
		_setup_light(light, teal, 6.0, 22.0)
		light.position = Vector3(corner.x * 7.0, 3.0, corner.y * 7.0)
		root.add_child(light)


# ------------------------------------------------------- cosas de la calle

func _setup_light(light: OmniLight3D, color: Color, energy: float, light_range: float) -> void:
	light.light_color = color
	light.set_meta("base_energy", energy)
	light.light_energy = energy * power
	light.add_to_group("city_light")
	light.omni_range = light_range
	light.omni_attenuation = 1.0
	# Sin sombras y apagándose a lo lejos: así puede haber muchas luces.
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 130.0
	light.distance_fade_length = 40.0


## Apagones: baja (o sube) la luz de farolas, neones y ventanas de toda la ciudad.
func set_power(p: float) -> void:
	power = p
	_building_mat.set_shader_parameter("window_energy", 0.9 * p)
	_neon_mat.set_shader_parameter("energy", 3.0 * p)
	_lamp_on.emission_energy_multiplier = 2.5 * p
	for light in get_tree().get_nodes_in_group("city_light"):
		if not light is FlickerLight:
			light.light_energy = float(light.get_meta("base_energy", 1.0)) * p


func _add_lamp(root: Node3D, rng: RandomNumberGenerator, normal: Vector3, tangent: Vector3) -> void:
	var arm_len := 4.5
	var base := normal * (BLOCK_HALF + 0.5) + tangent * rng.randf_range(-18.0, 18.0)
	var head := base + normal * arm_len + Vector3.UP * (LAMP_HEIGHT - 0.1)
	var broken := rng.randf() < 0.18
	CarFactory.add_box(root, Vector3(0.2, LAMP_HEIGHT, 0.2), base + Vector3.UP * LAMP_HEIGHT * 0.5, _metal)
	CarFactory.add_box(root, _box_along(normal, arm_len, 0.12, 0.12), base + normal * arm_len * 0.5 + Vector3.UP * LAMP_HEIGHT, _metal)
	CarFactory.add_box(root, _box_along(normal, 0.9, 0.12, 0.45), head, _lamp_off if broken else _lamp_on)
	if broken:
		return
	var sodium := Color(1.0, 0.6, 0.28)
	var light: OmniLight3D
	if rng.randf() < 0.1:
		var flicker := FlickerLight.new()
		flicker.base_energy = 8.5
		light = flicker
	else:
		light = OmniLight3D.new()
	_setup_light(light, sodium, 8.5, 27.0)
	light.position = head - Vector3.UP * 0.5
	root.add_child(light)


func _add_neon(root: Node3D, rng: RandomNumberGenerator, normal: Vector3, tangent: Vector3) -> void:
	var color: Color = NEON_COLORS[rng.randi() % NEON_COLORS.size()]
	var s := rng.randf_range(-BLOCK_HALF + 5.0, BLOCK_HALF - 5.0)
	var length := rng.randf_range(4.0, 8.0)
	var sign_mesh: MeshInstance3D
	var pos: Vector3
	if rng.randf() < 0.55:
		# Cartel vertical que sobresale de la fachada: se ve al ir por la calle.
		pos = normal * (BLOCK_HALF + 0.65) + tangent * s + Vector3.UP * (4.0 + length * 0.5)
		sign_mesh = CarFactory.add_box(root, _box_along(normal, 1.1, length, 0.22), pos, _neon_mat)
	else:
		# Cartel horizontal pegado a la pared.
		pos = normal * (BLOCK_HALF + 0.14) + tangent * s + Vector3.UP * rng.randf_range(4.6, 7.0)
		sign_mesh = CarFactory.add_box(root, _box_along(normal, 0.22, 1.2, length), pos, _neon_mat)
	sign_mesh.set_instance_shader_parameter("neon_color", color)
	if rng.randf() < 0.6:
		var light := OmniLight3D.new()
		_setup_light(light, color, 7.0, 18.0)
		light.position = Vector3(pos.x, 3.5, pos.z) + normal * 2.0
		root.add_child(light)


func _add_parked_cars(root: Node3D, rng: RandomNumberGenerator, normal: Vector3, tangent: Vector3) -> void:
	var count := 0
	var r := rng.randf()
	if r < parked_density * 0.5:
		count = 2
	elif r < parked_density * 1.3:
		count = 1
	var s := rng.randf_range(-19.0, 12.0)
	for i in count:
		var car := Knockable.new()
		car.penalty = 0.28
		car.mass = 900.0
		car.add_box_collider(Vector3(CarFactory.WIDTH, 1.2, CarFactory.LENGTH), Vector3(0.0, 0.7, 0.0))
		car.add_child(CarFactory.build_simple(CarFactory.random_paint(rng), false))
		# Pegado al bordillo y paralelo a la calle.
		car.position = normal * (BLOCK_HALF + SIDEWALK + 1.15) + tangent * (s + i * 6.0)
		car.rotation.y = atan2(-tangent.x, -tangent.z) + (PI if rng.randf() < 0.5 else 0.0)
		root.add_child(car)


func _add_roadworks(root: Node3D, rng: RandomNumberGenerator, normal: Vector3, tangent: Vector3) -> void:
	# Obras: dos filas de vallas cortando el carril exterior y un contenedor en medio.
	var s := rng.randf_range(-12.0, 12.0)
	var curb := BLOCK_HALF + SIDEWALK
	var across := atan2(-normal.z, normal.x)   # giro que pone el eje X de la valla cruzando la calle
	var board := CarFactory.glow(Color(1.0, 0.45, 0.05), 0.5)
	for row: float in [-7.0, 7.0]:
		for i in 3:
			var barrier := Knockable.new()
			barrier.penalty = 0.06
			barrier.mass = 40.0
			barrier.add_box_collider(Vector3(1.5, 1.0, 0.3), Vector3(0.0, 0.5, 0.0))
			CarFactory.add_box(barrier, Vector3(1.5, 0.3, 0.08), Vector3(0.0, 0.8, 0.0), board)
			CarFactory.add_box(barrier, Vector3(1.3, 0.6, 0.3), Vector3(0.0, 0.3, 0.0), _metal)
			CarFactory.add_box(barrier, Vector3(0.18, 0.18, 0.18), Vector3(0.0, 1.05, 0.0), _blink_amber)
			barrier.position = normal * (curb + 1.0 + i * 1.7) + tangent * (s + row)
			barrier.rotation.y = across
			root.add_child(barrier)
	var skip := Knockable.new()
	skip.penalty = 0.22
	skip.mass = 500.0
	skip.add_box_collider(Vector3(2.0, 1.5, 3.6), Vector3(0.0, 0.75, 0.0))
	CarFactory.add_box(skip, Vector3(2.0, 1.4, 3.6), Vector3(0.0, 0.8, 0.0), CarFactory.flat(Color(0.3, 0.2, 0.04), 0.7, 0.3))
	skip.position = normal * (curb + 1.6) + tangent * s
	skip.rotation.y = atan2(-tangent.x, -tangent.z)
	root.add_child(skip)


## Semáforo colgado de un cable en el cruce de la esquina (+X, +Z) del trozo.
func _add_signal(root: Node3D, key: Vector2i) -> void:
	# El cable va de la esquina de un edificio a la del de enfrente, en diagonal.
	# Si en una diagonal hay una plaza (sin edificios), probamos con la otra.
	var angle := -PI * 0.25
	if _is_plaza(key) or _is_plaza(key + Vector2i(1, 1)):
		if _is_plaza(key + Vector2i(1, 0)) or _is_plaza(key + Vector2i(0, 1)):
			return
		angle = PI * 0.25
	var cross := Vector3(CHUNK * 0.5, 0.0, CHUNK * 0.5)
	var wire_len := (CHUNK * 0.5 - BLOCK_HALF) * 2.0 * sqrt(2.0)
	var wire := CarFactory.add_box(root, Vector3(wire_len, 0.05, 0.05), cross + Vector3.UP * 8.4, _metal)
	wire.rotation.y = angle
	CarFactory.add_box(root, Vector3(0.55, 1.5, 0.55), cross + Vector3.UP * 7.6, _metal)
	for side: float in [-1.0, 1.0]:
		# Caras que ven los coches de la calle norte-sur, y las de la este-oeste.
		CarFactory.add_box(root, Vector3(0.42, 1.3, 0.06), cross + Vector3(0.0, 7.6, 0.3 * side), _signal_mats[0])
		CarFactory.add_box(root, Vector3(0.06, 1.3, 0.42), cross + Vector3(0.3 * side, 7.6, 0.0), _signal_mats[1])


# ------------------------------------------------------------ calles cortadas
#
# Algunas calles están cortadas por un muro de obra: obligan a girar, que es lo
# difícil cuando no puedes frenar. Para que el juego sea justo, los cortes
# siguen un patrón (se repite cada 5 calles) en el que NINGÚN cruce tiene más
# de una salida cortada, así que siempre quedan al menos dos caminos libres.
# `closure_chance` decide cuántos de esos cortes posibles existen de verdad.
#
# Un "cruce" (i, j) está en x = CHUNK * (i + 0.5), z = CHUNK * (j + 0.5).

## ¿Está cortado el tramo norte-sur de la calle i, entre los cruces j y j+1?
func is_closed_ns(i: int, j: int) -> bool:
	return posmod(j, 5) == posmod(2 * i, 5) and _closure_roll(i, j, 1)


## ¿Está cortado el tramo este-oeste de la calle j, entre los cruces i e i+1?
func is_closed_ew(i: int, j: int) -> bool:
	return posmod(i, 5) == posmod(3 + 3 * j, 5) and _closure_roll(i, j, 2)


func _closure_roll(i: int, j: int, axis: int) -> bool:
	return (hash(Vector4i(i, j, axis, world_seed)) & 0xffff) / 65535.0 < closure_chance


## Distancia hasta la próxima calle cortada si sigues recto desde `pos` en la
## dirección `dir`. Devuelve INF si no hay ninguna cerca o no vas por una calle.
func closure_ahead(pos: Vector3, dir: Vector3, max_dist := 300.0) -> float:
	var half := CHUNK * 0.5
	var north_south := absf(dir.z) > 0.8
	if not north_south and absf(dir.x) < 0.8:
		return INF                                   # en diagonal: está girando
	# "across" cruza la calle de lado a lado; "along" avanza por ella.
	var across := pos.x if north_south else pos.z
	var along := pos.z if north_south else pos.x
	var forward := signf(dir.z if north_south else dir.x)
	var road := roundi((across - half) / CHUNK)
	if absf(across - (road * CHUNK + half)) > ROAD_HALF + SIDEWALK:
		return INF                                   # no está sobre una calle
	var first := floori((along - half) / CHUNK)      # tramo en el que está ahora
	for step in 5:
		var seg := first + step * int(forward)
		var closed := is_closed_ns(road, seg) if north_south else is_closed_ew(seg, road)
		if not closed:
			continue
		# El muro que encuentra primero es el del extremo por el que entra.
		var seg_start := seg * CHUNK + half
		var wall := seg_start + CLOSURE_INSET if forward > 0.0 else seg_start + CHUNK - CLOSURE_INSET
		var d := (wall - along) * forward
		if d > 0.0 and d < max_dist:
			return d
	return INF


## Hacia qué lado conviene girar ante el corte que hay a `dist` metros yendo
## en la dirección `dir`: -1 = izquierda, 1 = derecha, 0 = da igual. Elige el
## lado por el que se tarda más en encontrar otro corte.
func best_turn(pos: Vector3, dir: Vector3, dist: float) -> int:
	var ahead := Vector3(0.0, 0.0, signf(dir.z)) if absf(dir.z) > 0.8 else Vector3(signf(dir.x), 0.0, 0.0)
	# El cruce donde hay que girar está justo antes del muro.
	var crossing := pos + ahead * (dist - CLOSURE_INSET)
	crossing.x = snap_to_road(crossing.x)
	crossing.z = snap_to_road(crossing.z)
	var right := Vector3(-ahead.z, 0.0, ahead.x)
	var free_right := closure_ahead(crossing + right, right, 1000.0)
	var free_left := closure_ahead(crossing - right, -right, 1000.0)
	if free_right == free_left:
		return 0
	return 1 if free_right > free_left else -1


## ¿Está `pos` dentro de un tramo cortado? (para no poner tráfico ahí)
func is_inside_closure(pos: Vector3, north_south: bool) -> bool:
	var half := CHUNK * 0.5
	var across := pos.x if north_south else pos.z
	var along := pos.z if north_south else pos.x
	var road := roundi((across - half) / CHUNK)
	var seg := floori((along - half) / CHUNK)
	return is_closed_ns(road, seg) if north_south else is_closed_ew(seg, road)


## Muro de obra que cierra la calle de lado a lado. `turned` lo gira 90 grados
## (para las calles este-oeste).
func _add_closure(root: Node3D, pos: Vector3, turned: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.position = pos
	if turned:
		body.rotation.y = PI * 0.5
	var cs := CollisionShape3D.new()
	cs.shape = _closure_shape
	cs.position.y = _closure_shape.size.y * 0.5
	body.add_child(cs)
	var width := _closure_shape.size.x
	CarFactory.add_box(body, Vector3(width, 1.1, 0.8), Vector3(0.0, 0.55, 0.0), _concrete)
	CarFactory.add_box(body, Vector3(width, 0.45, 0.12), Vector3(0.0, 1.45, 0.0), _closure_glow)   # franja roja luminosa
	for k in range(-2, 3):
		CarFactory.add_box(body, Vector3(0.35, 0.35, 0.35), Vector3(k * 5.0, 1.95, 0.0), _blink_amber)
	# Panel alto de franjas rojas y blancas, para verlo desde lejos.
	for k in 6:
		var stripe := _closure_glow if k % 2 == 0 else _closure_white
		CarFactory.add_box(body, Vector3(2.0, 2.0, 0.15), Vector3(-5.0 + k * 2.0, 3.6, 0.0), stripe)
	for side: float in [-1.0, 1.0]:
		CarFactory.add_box(body, Vector3(0.25, 2.6, 0.25), Vector3(side * 6.2, 1.3, 0.0), _metal)
	var light := OmniLight3D.new()
	_setup_light(light, Color(1.0, 0.12, 0.06), 7.0, 24.0)
	# Las calles cortadas siguen iluminadas en los apagones (si no, sería injusto).
	light.remove_from_group("city_light")
	light.light_energy = 7.0
	light.position.y = 3.2
	body.add_child(light)
	root.add_child(body)


## Tira toda la ciudad y la vuelve a crear (por si cambias la semilla o algún
## ajuste con el juego en marcha).
func rebuild() -> void:
	for key: Vector2i in _chunks.keys():
		_chunks[key].queue_free()
	_chunks.clear()
	prewarm()


## Tamaño de una caja alineada con un lado de la manzana: `depth` metros en la
## dirección en la que sale de la fachada, `up` de alto y `wide` a lo largo de ella.
func _box_along(normal: Vector3, depth: float, up: float, wide: float) -> Vector3:
	if absf(normal.x) > 0.5:
		return Vector3(depth, up, wide)
	return Vector3(wide, up, depth)
