class_name Explosion
extends Node3D
## La explosión del coche: destello, llamarada, humo, chispas y trozos del
## coche volando. Se crea con Explosion.spawn(...) y se apaña sola.

var car_velocity := Vector3.ZERO
var car_color := Color(0.6, 0.1, 0.1)
var warmup := false          # ver warm_up()

var _chassis: RigidBody3D
var _fire: Node3D            # sigue al chasis (sin girar) y lleva la luz y el humo
var _light: OmniLight3D
var _light_energy := 40.0


static func spawn(parent: Node, pos: Vector3, velocity: Vector3, color: Color) -> Explosion:
	var e := Explosion.new()
	e.car_velocity = velocity
	e.car_color = color
	e.position = pos
	parent.add_child(e)
	return e


## "Calentamiento": la primera vez que la tarjeta gráfica dibuja un material
## nuevo tiene que prepararlo, y eso da un tirón. Para que el tirón no llegue
## justo al explotar, al cargar el juego dibujamos una explosión escondida bajo
## el suelo durante un instante.
static func warm_up(parent: Node, pos: Vector3) -> void:
	var e := Explosion.new()
	e.warmup = true
	e.position = pos + Vector3.DOWN * 3.0
	parent.add_child(e)
	e.get_tree().create_timer(0.5).timeout.connect(e.queue_free)


func _ready() -> void:
	# Los efectos se animan por frame, no por física: sin interpolación.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var burnt := CarFactory.flat(Color(0.05, 0.045, 0.04), 0.9)

	# Lo que queda del coche: sale despedido hacia arriba dando vueltas.
	_chassis = _make_piece(Vector3(CarFactory.WIDTH, 0.5, CarFactory.LENGTH * 0.9), burnt, 600.0)
	_chassis.position = Vector3(0.0, 0.7, 0.0)
	_chassis.linear_velocity = car_velocity * 0.6 + Vector3.UP * 8.0
	_chassis.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-2.0, 2.0), randf_range(-5.0, 5.0))
	add_child(_chassis)

	# Trozos sueltos.
	var paint := CarFactory.flat(car_color.darkened(0.5), 0.6, 0.3)
	for i in 14:
		var size := Vector3(randf_range(0.3, 1.4), randf_range(0.06, 0.35), randf_range(0.3, 1.2))
		var piece := _make_piece(size, paint if i % 2 == 0 else burnt, 20.0)
		piece.position = Vector3(randf_range(-0.8, 0.8), randf_range(0.5, 1.4), randf_range(-1.8, 1.8))
		piece.linear_velocity = car_velocity * randf_range(0.3, 0.9) + Vector3(randf_range(-9.0, 9.0), randf_range(6.0, 17.0), randf_range(-9.0, 9.0))
		piece.angular_velocity = Vector3(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		add_child(piece)

	_fire = Node3D.new()
	_fire.position = Vector3(0.0, 0.8, 0.0)
	add_child(_fire)

	# Destello que se queda como luz de incendio.
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.25)
	_light.omni_range = 70.0
	_light.omni_attenuation = 1.0
	_light.position.y = 1.5
	_fire.add_child(_light)
	if warmup:
		_light_energy = 0.0
	else:
		create_tween().tween_property(self, "_light_energy", 9.0, 1.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	add_child(_make_fireball())
	_fire.add_child(_make_smoke())
	_fire.add_child(_make_flames())
	add_child(_make_sparks())


func _process(_delta: float) -> void:
	_fire.global_position = _chassis.get_global_transform_interpolated().origin + Vector3.UP * 0.4
	_light.light_energy = _light_energy * randf_range(0.8, 1.2)   # el fuego tiembla


func _make_piece(size: Vector3, mat: Material, mass_kg: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	body.collision_layer = Layers.DEBRIS
	body.collision_mask = Layers.WORLD | Layers.GROUND
	body.mass = mass_kg
	body.freeze = warmup      # en el calentamiento solo hay que dibujarlos
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	CarFactory.add_box(body, size, Vector3.ZERO, mat)
	return body


## Esfera de pocos polígonos para las partículas de fuego y humo.
func _puff_mesh(radius: float, mat: Material) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	mesh.material = mat
	return mesh


func _curve(from: float, to: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, from))
	c.add_point(Vector2(1.0, to))
	return c


## La llamarada: bolas de fuego que se suman unas a otras (mezcla aditiva),
## crecen y se apagan pasando de amarillo a naranja.
func _make_fireball() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position.y = 1.0
	p.one_shot = true
	p.amount = 26
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 85.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 11.0
	p.damping_min = 5.0
	p.damping_max = 7.0
	p.gravity = Vector3(0.0, 3.0, 0.0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.scale_amount_curve = _curve(0.35, 1.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	ramp.set_color(1, Color(0.3, 0.04, 0.0, 0.0))
	ramp.add_point(0.35, Color(1.0, 0.4, 0.08, 0.8))
	p.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	p.mesh = _puff_mesh(0.9, mat)
	p.emitting = true
	return p


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 3.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0.0, 1.5, 0.0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.scale_amount_curve = _curve(0.3, 1.0)
	var fade := Gradient.new()
	fade.set_color(0, Color(0.12, 0.11, 0.1, 0.7))
	fade.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	p.color_ramp = fade
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	p.mesh = _puff_mesh(0.6, mat)
	return p


func _make_flames() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.7
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.7, 0.2, 1.4)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0.0, 2.0, 0.0)
	p.scale_amount_curve = _curve(1.0, 0.1)
	p.mesh = _puff_mesh(0.4, CarFactory.glow(Color(1.0, 0.45, 0.08), 4.0))
	return p


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position.y = 1.0
	p.one_shot = true
	p.amount = 70
	p.lifetime = 1.4
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 26.0
	p.gravity = Vector3(0.0, -14.0, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.3)
	mesh.material = CarFactory.glow(Color(1.0, 0.65, 0.2), 6.0)
	p.mesh = mesh
	p.emitting = true
	return p
