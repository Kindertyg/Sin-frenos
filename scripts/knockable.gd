class_name Knockable
extends RigidBody3D
## Objeto que sale volando cuando el jugador lo golpea: coches, vallas,
## contenedores... Mientras nadie lo toca está "congelado" (freeze) y no gasta
## física. Al golpearlo se descongela y la física de Godot hace el resto.

static var _shapes := {}

var penalty := 0.3                    ## parte de su velocidad que pierde el jugador al golpearlo (0-1)
var knocked := false                  ## ¿ya ha salido volando?
var knocked_at := 0.0                 ## segundo (reloj real) en el que salió volando
var cruise_velocity := Vector3.ZERO   ## solo tráfico: velocidad a la que circula


func _init() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = Layers.PROPS
	collision_mask = 0
	# La ciudad apaga la interpolación (no se mueve); estos objetos sí la quieren.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON


## Le pone una caja de colisión. Las formas iguales se comparten.
func add_box_collider(size: Vector3, center: Vector3) -> void:
	if not _shapes.has(size):
		var shape := BoxShape3D.new()
		shape.size = size
		_shapes[size] = shape
	var cs := CollisionShape3D.new()
	cs.shape = _shapes[size]
	cs.position = center
	add_child(cs)


## Sale volando. `hit_velocity` es la velocidad de quien lo golpea y `from` su posición.
func knock(hit_velocity: Vector3, from: Vector3) -> void:
	if knocked:
		return
	knocked = true
	knocked_at = Time.get_ticks_msec() / 1000.0
	freeze = false
	# Cambia de capa: el jugador ya no vuelve a chocar con él.
	collision_layer = Layers.DEBRIS
	collision_mask = Layers.WORLD | Layers.GROUND | Layers.DEBRIS | Layers.PROPS

	var hit_speed := hit_velocity.length()
	var dir := hit_velocity / maxf(hit_speed, 0.01)
	# Lo apartamos hacia el lado en el que estaba respecto al coche.
	var side := dir.cross(Vector3.UP)
	if (global_position - from).dot(side) < 0.0:
		side = -side
	linear_velocity = dir * hit_speed * 0.8 + side * hit_speed * 0.35 + Vector3.UP * (2.5 + hit_speed * 0.12)
	angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-5.0, 5.0), randf_range(-4.0, 4.0))


## Lo deja listo para volver a circular como tráfico (lo mueve el código, no la física).
func reset_as_kinematic() -> void:
	knocked = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = Layers.PROPS
	collision_mask = 0
