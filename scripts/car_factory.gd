class_name CarFactory
## Fabrica coches (y cualquier otra cosa) con cajas y cilindros, para no
## necesitar modelos 3D. El morro del coche mira hacia -Z, que es "adelante"
## en Godot.

const LENGTH := 4.3
const WIDTH := 1.86
const WHEEL_RADIUS := 0.36

## Colores de pintura para el tráfico y los coches aparcados.
const PAINTS: Array[Color] = [
	Color(0.5, 0.07, 0.07), Color(0.08, 0.17, 0.42), Color(0.42, 0.43, 0.45),
	Color(0.06, 0.06, 0.07), Color(0.55, 0.4, 0.08), Color(0.1, 0.28, 0.2),
	Color(0.68, 0.68, 0.65), Color(0.26, 0.1, 0.36),
]

static var _box: BoxMesh
static var _wheel: CylinderMesh
static var _axle: CylinderMesh
static var _materials := {}


## Un cubo de 1x1x1 compartido: cada pieza lo reutiliza cambiándole la escala.
static func unit_box() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
	return _box


## Añade una caja de tamaño `size` centrada en `pos` (posición local de `parent`).
static func add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_box()
	mi.material_override = mat
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)
	return mi


## Material liso. Se guarda en caché para que todos los objetos iguales lo compartan.
static func flat(color: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var key := "f%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		m.metallic = metallic
		_materials[key] = m
	return _materials[key]


## Material que brilla (faros, neones...). Con `shared = false` devuelve uno
## propio, para poder cambiarle el brillo sin afectar a los demás.
static func glow(color: Color, energy := 3.0, shared := true) -> StandardMaterial3D:
	var key := "g%s_%.2f" % [color.to_html(), energy]
	if shared and _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if shared:
		_materials[key] = m
	return m


static func random_paint(rng: RandomNumberGenerator) -> Color:
	return PAINTS[rng.randi() % PAINTS.size()]


## Coche detallado (el del jugador): ruedas sueltas que giran y luces propias.
## Devuelve el nodo con dos "metas": "wheels" (los 4 pivotes; los 2 primeros son
## los delanteros) y "tail_material" (el material de los pilotos traseros).
static func build(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	_add_body(root, color)

	var head := glow(Color(1.0, 0.95, 0.82), 4.0)
	var tail := glow(Color(1.0, 0.04, 0.03), 2.0, false)
	for side: float in [-1.0, 1.0]:
		add_box(root, Vector3(0.44, 0.16, 0.06), Vector3(0.6 * side, 0.68, -LENGTH * 0.5 - 0.02), head)
		add_box(root, Vector3(0.44, 0.14, 0.06), Vector3(0.6 * side, 0.7, LENGTH * 0.5 + 0.02), tail)

	if _wheel == null:
		_wheel = CylinderMesh.new()
		_wheel.top_radius = WHEEL_RADIUS
		_wheel.bottom_radius = WHEEL_RADIUS
		_wheel.height = 0.26
		_wheel.radial_segments = 14
		_wheel.rings = 1
	var tire := flat(Color(0.015, 0.015, 0.015), 0.9)
	var rim := flat(Color(0.45, 0.45, 0.48), 0.3, 0.8)
	var wheels: Array[Node3D] = []
	for z_side: float in [-1.0, 1.0]:        # -1 = eje delantero
		for x_side: float in [-1.0, 1.0]:
			var pivot := Node3D.new()        # gira con el volante
			pivot.position = Vector3((WIDTH * 0.5 - 0.06) * x_side, WHEEL_RADIUS, 1.36 * z_side)
			root.add_child(pivot)
			var spinner := Node3D.new()      # gira al rodar
			pivot.add_child(spinner)
			var wheel := MeshInstance3D.new()
			wheel.mesh = _wheel
			wheel.material_override = tire
			wheel.rotation.z = PI * 0.5      # el cilindro viene de pie: lo tumbamos
			spinner.add_child(wheel)
			add_box(spinner, Vector3(0.3, 0.46, 0.1), Vector3.ZERO, rim)   # llanta: se ve girar
			wheels.append(pivot)
	root.set_meta("wheels", wheels)
	root.set_meta("tail_material", tail)
	return root


## Coche sencillo (tráfico y aparcados): menos piezas para que haya muchos.
static func build_simple(color: Color, lights_on: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Visual"
	_add_body(root, color)

	var head: Material = glow(Color(1.0, 0.95, 0.82), 4.0) if lights_on else flat(Color(0.2, 0.2, 0.18), 0.2)
	var tail: Material = glow(Color(1.0, 0.04, 0.03), 3.0) if lights_on else flat(Color(0.16, 0.02, 0.02), 0.2)
	for side: float in [-1.0, 1.0]:
		add_box(root, Vector3(0.44, 0.16, 0.06), Vector3(0.6 * side, 0.68, -LENGTH * 0.5 - 0.02), head)
		add_box(root, Vector3(0.44, 0.14, 0.06), Vector3(0.6 * side, 0.7, LENGTH * 0.5 + 0.02), tail)

	# Un solo cilindro por eje hace de las dos ruedas.
	if _axle == null:
		_axle = CylinderMesh.new()
		_axle.top_radius = WHEEL_RADIUS
		_axle.bottom_radius = WHEEL_RADIUS
		_axle.height = WIDTH + 0.06
		_axle.radial_segments = 10
		_axle.rings = 1
	var tire := flat(Color(0.015, 0.015, 0.015), 0.9)
	for z_side: float in [-1.0, 1.0]:
		var axle := MeshInstance3D.new()
		axle.mesh = _axle
		axle.material_override = tire
		axle.rotation.z = PI * 0.5
		axle.position = Vector3(0.0, WHEEL_RADIUS, 1.36 * z_side)
		root.add_child(axle)
	return root


static func _add_body(root: Node3D, color: Color) -> void:
	var paint := flat(color, 0.35, 0.55)
	var dark := flat(Color(0.1, 0.1, 0.11), 0.6)
	var glass := flat(Color(0.02, 0.03, 0.045), 0.08, 0.6)
	add_box(root, Vector3(WIDTH, 0.5, LENGTH), Vector3(0.0, 0.6, 0.0), paint)           # carrocería
	add_box(root, Vector3(WIDTH - 0.22, 0.48, 2.15), Vector3(0.0, 1.07, 0.3), glass)    # cabina
	add_box(root, Vector3(WIDTH - 0.18, 0.07, 1.9), Vector3(0.0, 1.33, 0.3), paint)     # techo
	add_box(root, Vector3(WIDTH + 0.04, 0.2, 0.2), Vector3(0.0, 0.42, -LENGTH * 0.5), dark)   # parachoques
	add_box(root, Vector3(WIDTH + 0.04, 0.2, 0.2), Vector3(0.0, 0.42, LENGTH * 0.5), dark)
