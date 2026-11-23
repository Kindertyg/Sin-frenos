class_name PlayerCar
extends CharacterBody3D
## El coche del jugador.
##
## Física "arcade": no simula ruedas ni suspensión. Guarda una velocidad sobre
## el suelo (`vel`) y en cada paso la separa en dos partes: la que va hacia
## delante y la que va de lado. La de lado es el derrape, y el "agarre" decide
## lo rápido que desaparece.
##
## Extras arcade: NITRO (se gasta y se rellena con jugadas arriesgadas) y
## TURBO DE DERRAPE (derrapa con el freno de mano y suéltalo: sales disparado).

signal crashed(impact: float)                   ## golpe contra un muro (impact en m/s)
signal prop_hit(prop: Knockable, lost: float)   ## golpe contra tráfico u objetos
signal drift_boost(charge: float)               ## turbo de derrape (charge = segundos derrapando)
signal armor_used                               ## el blindaje ha aguantado un golpe

## Capa visual de la cabina. El retrovisor no la dibuja (si no, se vería a sí mismo).
const COCKPIT_LAYER := 2
## Dónde están los ojos del conductor (izquierda, altura, un poco hacia atrás).
const HEAD := Vector3(-0.36, 1.32, 0.02)

@export var body_color := Color(0.62, 0.07, 0.06)

@export_group("Motor")
@export var max_speed_kmh := 230.0
@export var engine_accel := 19.0       ## m/s² al arrancar; baja al acercarse a la máxima
@export var brake_decel := 22.0        ## m/s² al frenar
@export var coast_decel := 2.5         ## m/s² que pierde al soltar el acelerador

@export_group("Nitro")
@export var nitro_accel := 16.0        ## m/s² extra con el nitro
@export var nitro_speed_kmh := 60.0    ## velocidad máxima extra con el nitro
@export var nitro_drain := 0.32        ## parte del depósito que gasta por segundo
@export var turbo_accel := 26.0        ## m/s² del turbo de derrape
@export var drift_min_time := 0.45     ## segundos de derrape para ganar turbo

@export_group("Dirección")
@export var steer_rate := 2.15         ## giro máximo en radianes por segundo
@export var high_speed_steer := 0.5    ## parte del giro que queda a velocidad máxima
@export var steer_response := 8.0      ## rapidez con la que responde el volante
@export var grip := 9.0                ## agarre lateral normal (más = menos derrape)
@export var drift_grip := 2.0          ## agarre con el freno de mano
@export var drift_steer_boost := 1.7   ## giro extra con el freno de mano
@export var handbrake_decel := 3.0     ## m/s² que frena el freno de mano

@export_group("Choques")
@export var wall_scrape_decel := 9.0   ## m/s² que pierde mientras roza un muro
@export var wall_impact_loss := 0.016  ## parte de la velocidad perdida por cada m/s de golpe

var vel := Vector3.ZERO     # velocidad real sobre el suelo (m/s)
var speed := 0.0            # módulo de vel (m/s)
var speed_kmh := 0.0
var slip := 0.0             # velocidad lateral: cuánto está derrapando
var steer := 0.0            # volante suavizado, de -1 (derecha) a 1 (izquierda)
var destroyed := false
var nitro := 0.5            # depósito de nitro, de 0 a 1
var boosting := false       # ¿está el nitro o el turbo empujando ahora mismo?
var drift_charge := 0.0     # segundos que lleva derrapando (para el turbo)
var first_person := false
var armor := 0              # golpes que aguanta sin perder velocidad (mejora de la tienda)

# Entradas. Las rellena _read_input(); el modo de pruebas las escribe a mano.
var controls_enabled := false
var external_input := false
var throttle_in := 0.0
var brake_in := 0.0
var steer_in := 0.0
var handbrake_in := false
var nitro_in := false

var _visual: Node3D
var _roof_parts: Array[Node3D] = []   # techo, cristales y bomba de fuera: se ocultan en 1ª persona
var _wheels: Array = []
var _wheel_spin := 0.0
var _tail_mat: StandardMaterial3D
var _tail_light: OmniLight3D
var _headlight: SpotLight3D
var _road_glow: SpotLight3D
var _led_mat: StandardMaterial3D
var _bomb_light: OmniLight3D
var _led := 0.0
var _sparks: CPUParticles3D
var _smoke: CPUParticles3D
var _flames: CPUParticles3D
var _crash_cooldown := 0.0
var _warmup := 0.0
var _last_forward_speed := 0.0
var _pitch := 0.0
var _turbo_time := 0.0
var _was_handbrake := false

# Cabina (solo se ve en primera persona).
var _cockpit: Node3D
var _wheel_spin_node: Node3D
var _bomb_label: Label3D
var _passenger: Node3D
var _passenger_time := 0.0
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D


func _ready() -> void:
	# "Flotante" = sin gravedad ni suelo: todo lo que toque cuenta como muro.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	axis_lock_linear_y = true
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.PROPS
	_build()
	_build_cockpit()
	set_first_person(false)


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	if not external_input:
		_read_input()
	_crash_cooldown -= delta

	steer = move_toward(steer, steer_in, steer_response * delta)

	# Nitro: mientras se pulsa y quede depósito.
	boosting = false
	if nitro_in and nitro > 0.0 and controls_enabled:
		nitro = maxf(0.0, nitro - nitro_drain * delta)
		boosting = true
	_turbo_time -= delta
	var turbo := _turbo_time > 0.0
	var max_speed := (max_speed_kmh + (nitro_speed_kmh if boosting or turbo else 0.0)) / 3.6

	# 1) Girar. Parado no gira, y a mucha velocidad gira menos.
	var low := clampf(vel.length() / 7.0, 0.0, 1.0)
	var high := lerpf(1.0, high_speed_steer, clampf(vel.length() / (max_speed_kmh / 3.6), 0.0, 1.0))
	var boost := drift_steer_boost if handbrake_in else 1.0
	rotate_y(steer * steer_rate * low * high * boost * delta)

	# 2) Separar la velocidad en "hacia delante" (f) y "de lado" (l).
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var f := vel.dot(forward)
	var l := vel.dot(right)

	# 3) Motor, nitro, freno y rozamiento actúan sobre la parte "hacia delante".
	if throttle_in > 0.0:
		f += engine_accel * throttle_in * maxf(0.0, 1.0 - f / max_speed) * delta
	else:
		f = move_toward(f, 0.0, coast_decel * delta)
	if boosting:
		f += nitro_accel * maxf(0.0, 1.0 - f / max_speed) * delta
	if turbo:
		f += turbo_accel * maxf(0.0, 1.0 - f / max_speed) * delta
		boosting = true
	if brake_in > 0.0:
		f = move_toward(f, 0.0, brake_decel * brake_in * delta)
	if handbrake_in:
		f = move_toward(f, 0.0, handbrake_decel * delta)
	# Si te pasas de la máxima (al acabar el nitro), vuelves a ella poco a poco.
	var normal_max := max_speed_kmh / 3.6
	if not boosting and f > normal_max:
		f = move_toward(f, normal_max, 6.0 * delta)

	# 4) Agarre: la parte "de lado" se va perdiendo...
	var before := Vector2(f, l).length()
	l *= exp(-(drift_grip if handbrake_in else grip) * delta)
	# ...pero una parte de esa velocidad se recupera hacia delante,
	# para que girar no frene demasiado (con el freno de mano frena más).
	var keep := 0.5 if handbrake_in else 0.85
	f += (before - Vector2(f, l).length()) * keep * signf(f)

	# 5) Turbo de derrape: se carga derrapando y se suelta al soltar el freno de mano.
	if handbrake_in and absf(l) > 3.0 and f > 12.0:
		drift_charge += delta
	if _was_handbrake and not handbrake_in:
		if drift_charge >= drift_min_time:
			_turbo_time = clampf(drift_charge * 0.7, 0.35, 1.4)
			nitro = minf(1.0, nitro + drift_charge * 0.08)
			drift_boost.emit(drift_charge)
		drift_charge = 0.0
	_was_handbrake = handbrake_in

	# 6) Mover el coche y mirar contra qué ha chocado.
	vel = forward * f + right * l
	var pre := vel
	velocity = vel
	move_and_slide()
	_handle_collisions(pre, delta)

	vel.y = 0.0
	speed = vel.length()
	speed_kmh = speed * 3.6
	slip = vel.dot(global_transform.basis.x)
	_update_visual(delta, f)


func _process(delta: float) -> void:
	# La luz de la bomba se apaga poco a poco después de cada pitido.
	_led = move_toward(_led, 0.0, delta * 5.0)
	_led_mat.emission_energy_multiplier = 0.4 + _led * 10.0
	_bomb_light.light_energy = _led * (2.5 if first_person else 4.0)
	_flames.emitting = boosting and not destroyed

	if _passenger_time > 0.0:
		_passenger_time -= delta
		_passenger.visible = _passenger_time > 0.0

	if first_person and _mirror_cam != null:
		# El retrovisor mira hacia atrás desde dentro del coche.
		var xf := get_global_transform_interpolated()
		_mirror_cam.global_transform = xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.35, 1.3))
		_wheel_spin_node.rotation.y = -steer * 2.2


## Cambia entre cámara de dentro (cabina) y de fuera.
func set_first_person(on: bool) -> void:
	first_person = on and not destroyed
	_cockpit.visible = first_person
	for part in _roof_parts:
		part.visible = not first_person
	# La luz roja de la bomba: dentro de la cabina o encima del techo.
	_bomb_light.position = Vector3(0.25, 1.3, -0.45) if first_person else Vector3(0.0, 2.1, 0.45)
	_bomb_light.omni_range = 3.0 if first_person else 9.0
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if first_person else SubViewport.UPDATE_DISABLED


## Mejora "faros de largo alcance".
func long_beams() -> void:
	_headlight.spot_range = 150.0
	_headlight.light_energy = 45.0
	_road_glow.spot_range = 40.0
	_road_glow.light_energy = 13.0


## El retrovisor usa un ambiente más barato (sin reflejos) para no ir lento.
func set_mirror_environment(env: Environment) -> void:
	_mirror_cam.environment = env


## Texto del aparato de la bomba que hay en el salpicadero.
func set_bomb_display(text: String, urgent: bool) -> void:
	_bomb_label.text = text
	_bomb_label.modulate = Color(1.0, 0.1, 0.05) if urgent else Color(1.0, 0.35, 0.1)


## Susto: "alguien" aparece un instante en el asiento del copiloto.
func show_passenger(seconds: float) -> void:
	if not first_person:
		return
	_passenger_time = seconds
	_passenger.visible = true


## El jugador ha golpeado un objeto que sale volando. También lo llama el
## tráfico cuando detecta el toque por distancia.
func hit_prop(prop: Knockable, hit_velocity: Vector3) -> void:
	if prop.knocked or destroyed:
		return
	# Cuanto más rápido nos acercábamos (de frente es peor), más velocidad perdemos.
	var closing := (hit_velocity - prop.cruise_velocity).length()
	var lost := clampf(prop.penalty * clampf(closing / 30.0, 0.6, 1.5), 0.0, 0.6)
	if lost > 0.1 and armor > 0:
		armor -= 1
		lost = 0.0
		armor_used.emit()
	prop.knock(hit_velocity, global_position)
	vel *= 1.0 - lost
	_spark(prop.global_position + Vector3.UP * 0.6, -hit_velocity.normalized())
	prop_hit.emit(prop, lost)


## "Calentamiento": suelta unas chispas bajo el suelo y un poco de humo nada
## más cargar, para que la tarjeta gráfica prepare esos efectos y no den un
## tirón la primera vez que aparecen en plena partida.
func warm_up() -> void:
	_warmup = 0.4
	_spark(global_position + Vector3.DOWN * 2.0, Vector3.UP)


## Hace parpadear la luz roja de la bomba (se llama con cada pitido).
func bomb_blink() -> void:
	_led = 1.0


## La bomba ha explotado: el coche desaparece (la explosión la dibuja Explosion).
func destroy() -> void:
	destroyed = true
	vel = Vector3.ZERO
	speed = 0.0
	speed_kmh = 0.0
	slip = 0.0
	boosting = false
	set_first_person(false)
	_visual.visible = false
	_headlight.visible = false
	_road_glow.visible = false
	_tail_light.visible = false
	_bomb_light.visible = false
	_smoke.emitting = false
	collision_layer = 0
	collision_mask = 0


func _read_input() -> void:
	if not controls_enabled:
		throttle_in = 0.0
		brake_in = 0.0
		steer_in = 0.0
		handbrake_in = false
		nitro_in = false
		return
	throttle_in = Input.get_action_strength("accelerate")
	brake_in = Input.get_action_strength("brake")
	steer_in = Input.get_axis("steer_right", "steer_left")
	handbrake_in = Input.is_action_pressed("handbrake")
	nitro_in = Input.is_action_pressed("nitro")


func _handle_collisions(pre: Vector3, delta: float) -> void:
	var wall_impact := -1.0
	var wall_normal := Vector3.ZERO
	var wall_point := Vector3.ZERO
	var props: Array[Knockable] = []
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var other := col.get_collider()
		if other is Knockable:
			props.append(other as Knockable)
			continue
		var n := col.get_normal()
		var impact := maxf(0.0, -pre.dot(n))   # velocidad con la que íbamos contra el muro
		if impact > wall_impact:
			wall_impact = impact
			wall_normal = n
			wall_point = col.get_position()

	if wall_impact > 8.0 and armor > 0 and _crash_cooldown <= 0.0:
		# Blindaje: rebotas contra el muro sin perder velocidad.
		armor -= 1
		_crash_cooldown = 1.2   # un mismo choque no gasta dos blindajes
		var along := velocity
		if along.length() < 1.0:
			along = pre.bounce(wall_normal)
		vel = along.normalized() * pre.length()
		rotation.y = atan2(-vel.x, -vel.z)
		_spark(wall_point, wall_normal)
		armor_used.emit()
	elif wall_impact >= 0.0:
		# move_and_slide ya nos ha dejado deslizando a lo largo del muro.
		vel = velocity * clampf(1.0 - wall_impact * wall_impact_loss, 0.25, 1.0)
		vel = vel.move_toward(Vector3.ZERO, wall_scrape_decel * delta)
		# El morro se va alineando con el muro para poder salir del roce.
		if vel.length() > 2.0:
			var wanted := atan2(-vel.x, -vel.z)
			rotation.y = lerp_angle(rotation.y, wanted, clampf(5.0 * delta, 0.0, 1.0))
		if wall_impact > 2.0:
			_spark(wall_point, wall_normal)
			if wall_impact > 4.0 and _crash_cooldown <= 0.0:
				_crash_cooldown = 0.2
				drift_charge = 0.0
				crashed.emit(wall_impact)
	else:
		# Los objetos que salen volando no nos paran como un muro.
		vel = pre
	for prop in props:
		hit_prop(prop, pre)


func _spark(point: Vector3, normal: Vector3) -> void:
	_sparks.global_position = point
	_sparks.reset_physics_interpolation()
	_sparks.direction = (normal + vel.normalized() * 0.8 + Vector3.UP * 0.6).normalized()
	_sparks.restart()
	_sparks.emitting = true


func _update_visual(delta: float, forward_speed: float) -> void:
	# Ruedas: las 4 ruedan y las 2 delanteras giran con el volante.
	_wheel_spin = fmod(_wheel_spin + forward_speed * delta / CarFactory.WHEEL_RADIUS, TAU)
	for i in _wheels.size():
		var pivot: Node3D = _wheels[i]
		if i < 2:
			pivot.rotation.y = steer * 0.45
		(pivot.get_child(0) as Node3D).rotation.x = -_wheel_spin

	# La carrocería se inclina al girar y cabecea al acelerar o frenar.
	var accel := (forward_speed - _last_forward_speed) / delta
	_last_forward_speed = forward_speed
	_pitch = lerpf(_pitch, clampf(accel * 0.004, -0.06, 0.05), clampf(6.0 * delta, 0.0, 1.0))
	var roll := clampf(-slip * 0.01, -0.09, 0.09)
	_visual.rotation.z = lerpf(_visual.rotation.z, roll, clampf(8.0 * delta, 0.0, 1.0))
	_visual.rotation.x = _pitch

	# Luces de freno y humo de derrape.
	var braking := brake_in > 0.05 or handbrake_in
	_tail_mat.emission_energy_multiplier = 8.0 if braking else 2.0
	_tail_light.light_energy = 1.2 if braking else 0.3
	_warmup -= delta
	_smoke.emitting = _warmup > 0.0 or (absf(slip) > 4.0 and speed > 8.0)


func _build() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(CarFactory.WIDTH, 1.0, CarFactory.LENGTH)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.75
	add_child(cs)

	_visual = CarFactory.build(body_color)
	add_child(_visual)
	_wheels = _visual.get_meta("wheels")
	_tail_mat = _visual.get_meta("tail_material")

	# La bomba: una caja en el techo con una luz roja que parpadea.
	CarFactory.add_box(_visual, Vector3(0.55, 0.2, 0.75), Vector3(0.0, 1.46, 0.3), CarFactory.flat(Color(0.07, 0.08, 0.06), 0.7))
	CarFactory.add_box(_visual, Vector3(0.6, 0.05, 0.08), Vector3(0.0, 1.5, 0.1), CarFactory.flat(Color(0.5, 0.4, 0.05), 0.5))
	_led_mat = CarFactory.glow(Color(1.0, 0.05, 0.02), 0.4, false)
	CarFactory.add_box(_visual, Vector3(0.14, 0.12, 0.14), Vector3(0.0, 1.6, 0.45), _led_mat)
	_bomb_light = OmniLight3D.new()
	_bomb_light.light_color = Color(1.0, 0.1, 0.05)
	_bomb_light.omni_range = 9.0
	_bomb_light.light_energy = 0.0
	add_child(_bomb_light)

	# Lo que está por encima del capó (cabina, techo y bomba de fuera) estorba
	# en primera persona: lo apuntamos para ocultarlo.
	for child in _visual.get_children():
		if child is MeshInstance3D and (child as Node3D).position.y > 0.9:
			_roof_parts.append(child as Node3D)

	# Faros: un foco con sombras, colocado un poco por delante del morro.
	_headlight = SpotLight3D.new()
	# Va más alto que un faro real: así la luz cae sobre el asfalto con más
	# ángulo y la calle se ve iluminada (truco habitual en juegos).
	_headlight.position = Vector3(0.0, 1.5, -2.4)
	_headlight.rotation_degrees.x = -5.0
	_headlight.light_color = Color(1.0, 0.96, 0.86)
	_headlight.light_energy = 30.0
	_headlight.spot_range = 90.0
	_headlight.spot_angle = 36.0
	_headlight.spot_attenuation = 0.6
	_headlight.spot_angle_attenuation = 0.7
	_headlight.shadow_enabled = true
	add_child(_headlight)

	# Segundo foco, de mentira: cuelga por delante del coche y apunta al suelo.
	# Un faro real ilumina el asfalto casi de canto y apenas se nota; este
	# deja un charco de luz delante para ver por dónde vas.
	_road_glow = SpotLight3D.new()
	_road_glow.position = Vector3(0.0, 8.0, -13.0)
	_road_glow.rotation_degrees.x = -68.0
	_road_glow.light_color = Color(1.0, 0.95, 0.85)
	_road_glow.light_energy = 9.0
	_road_glow.spot_range = 32.0
	_road_glow.spot_angle = 48.0
	_road_glow.spot_attenuation = 0.5
	_road_glow.spot_angle_attenuation = 1.4
	_road_glow.light_specular = 0.2
	add_child(_road_glow)

	_tail_light = OmniLight3D.new()
	_tail_light.light_color = Color(1.0, 0.08, 0.04)
	_tail_light.omni_range = 6.0
	_tail_light.light_energy = 0.3
	_tail_light.position = Vector3(0.0, 0.7, 2.6)
	add_child(_tail_light)

	_sparks = _make_sparks()
	add_child(_sparks)
	_smoke = _make_smoke()
	add_child(_smoke)
	_flames = _make_exhaust_flames()
	add_child(_flames)


## Interior del coche: salpicadero, volante con manos, pilares, retrovisor y la
## bomba pegada con cinta al salpicadero. Todo en la capa COCKPIT_LAYER.
func _build_cockpit() -> void:
	_cockpit = Node3D.new()
	_cockpit.name = "Cabina"
	add_child(_cockpit)
	var dark := CarFactory.flat(Color(0.035, 0.035, 0.04), 0.85)
	var plastic := CarFactory.flat(Color(0.07, 0.07, 0.08), 0.6)
	var cloth := CarFactory.flat(Color(0.05, 0.045, 0.05), 0.95)

	# Las medidas están pensadas para que el parabrisas deje ver mucha calle:
	# salpicadero bajo y lejos, techo alto (más que en un coche real).
	_cockpit_box(Vector3(1.72, 0.12, 0.08), Vector3(0.0, 0.92, -0.38), dark)       # borde del salpicadero
	_cockpit_box(Vector3(1.72, 0.14, 0.5), Vector3(0.0, 0.91, -0.66), dark)        # salpicadero
	_cockpit_box(Vector3(0.5, 0.06, 0.2), Vector3(-0.36, 1.0, -0.5), plastic)      # visera del cuadro
	_cockpit_box(Vector3(1.72, 0.02, 1.9), Vector3(0.0, 0.87, 0.2), cloth)          # suelo (tapa la chapa roja)
	_cockpit_box(Vector3(1.72, 0.04, 1.6), Vector3(0.0, 1.62, 0.35), cloth)         # techo por dentro
	_cockpit_box(Vector3(1.72, 0.06, 0.08), Vector3(0.0, 1.6, -0.43), cloth)        # marco de arriba del parabrisas
	for side: float in [-1.0, 1.0]:
		# Pilares del parabrisas, finos e inclinados hacia atrás.
		var pillar := _cockpit_box(Vector3(0.07, 0.86, 0.09), Vector3(0.88 * side, 1.27, -0.66), plastic)
		pillar.rotation.x = deg_to_rad(36.0)
		_cockpit_box(Vector3(0.08, 0.18, 1.8), Vector3(0.9 * side, 0.95, 0.2), dark)  # puertas
		_cockpit_box(Vector3(0.08, 0.7, 0.1), Vector3(0.88 * side, 1.25, 0.95), plastic)  # pilar del medio

	# Brillo tenue del cuadro de mandos (verde-azulado).
	_cockpit_box(Vector3(0.16, 0.025, 0.02), Vector3(-0.36, 0.99, -0.41), CarFactory.glow(Color(0.2, 0.9, 0.8), 0.6))

	# Volante: un aro que gira con la dirección, con dos manos agarrándolo.
	# Queda abajo: solo asoma la parte de arriba, como en los juegos de coches.
	var column := Node3D.new()
	column.position = Vector3(-0.36, 0.98, -0.36)
	column.rotation.x = deg_to_rad(65.0)          # el aro mira hacia el conductor
	_cockpit.add_child(column)
	_wheel_spin_node = Node3D.new()
	column.add_child(_wheel_spin_node)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.165
	torus.outer_radius = 0.2
	torus.rings = 24
	torus.ring_segments = 8
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.material_override = CarFactory.flat(Color(0.13, 0.12, 0.12), 0.5)
	ring.layers = COCKPIT_LAYER
	_wheel_spin_node.add_child(ring)
	var spoke := _box_in(_wheel_spin_node, Vector3(0.36, 0.03, 0.05), Vector3.ZERO, plastic)
	spoke.layers = COCKPIT_LAYER
	var hub := _box_in(_wheel_spin_node, Vector3(0.11, 0.05, 0.11), Vector3.ZERO, plastic)
	hub.layers = COCKPIT_LAYER
	var glove := CarFactory.flat(Color(0.09, 0.07, 0.06), 0.9)
	for side: float in [-1.0, 1.0]:
		var hand := _box_in(_wheel_spin_node, Vector3(0.09, 0.08, 0.12), Vector3(0.18 * side, 0.02, -0.04), glove)
		hand.layers = COCKPIT_LAYER

	# La bomba, pegada al salpicadero: caja, cables y una pantalla roja.
	var bomb := Node3D.new()
	bomb.position = Vector3(0.0, 1.02, -0.7)
	bomb.rotation.y = deg_to_rad(-25.0)               # girada hacia el conductor
	bomb.scale = Vector3.ONE * 0.65
	_cockpit.add_child(bomb)
	_box_in(bomb, Vector3(0.42, 0.17, 0.24), Vector3.ZERO, CarFactory.flat(Color(0.12, 0.13, 0.09), 0.7)).layers = COCKPIT_LAYER
	for k in 3:   # cartuchos
		_box_in(bomb, Vector3(0.09, 0.09, 0.3), Vector3(-0.13 + k * 0.13, 0.12, -0.02), CarFactory.flat(Color(0.45, 0.08, 0.05), 0.6)).layers = COCKPIT_LAYER
	_box_in(bomb, Vector3(0.44, 0.03, 0.26), Vector3(0.0, 0.05, 0.0), CarFactory.flat(Color(0.3, 0.28, 0.25), 0.9)).layers = COCKPIT_LAYER   # cinta
	_box_in(bomb, Vector3(0.02, 0.02, 0.3), Vector3(0.18, 0.0, 0.2), CarFactory.flat(Color(0.8, 0.1, 0.05), 0.5)).layers = COCKPIT_LAYER     # cables
	_box_in(bomb, Vector3(0.02, 0.02, 0.32), Vector3(0.15, -0.02, 0.21), CarFactory.flat(Color(0.8, 0.7, 0.05), 0.5)).layers = COCKPIT_LAYER
	_box_in(bomb, Vector3(0.05, 0.05, 0.05), Vector3(0.17, 0.06, 0.09), _led_mat).layers = COCKPIT_LAYER
	_box_in(bomb, Vector3(0.26, 0.09, 0.01), Vector3(-0.04, 0.0, 0.123), CarFactory.flat(Color(0.02, 0.0, 0.0), 0.3)).layers = COCKPIT_LAYER
	_bomb_label = Label3D.new()
	_bomb_label.text = "--:--"
	_bomb_label.font_size = 64
	_bomb_label.pixel_size = 0.0011
	_bomb_label.outline_size = 0
	_bomb_label.shaded = false
	_bomb_label.double_sided = false
	_bomb_label.modulate = Color(1.0, 0.35, 0.1)
	_bomb_label.position = Vector3(-0.04, 0.0, 0.13)
	_bomb_label.layers = COCKPIT_LAYER
	bomb.add_child(_bomb_label)

	# El copiloto que no debería estar ahí (solo aparece en los sustos).
	_passenger = Node3D.new()
	_passenger.position = Vector3(0.48, 0.5, -0.62)
	_passenger.visible = false
	_cockpit.add_child(_passenger)
	var shadow := CarFactory.flat(Color(0.0, 0.0, 0.0), 1.0)
	_box_in(_passenger, Vector3(0.42, 0.62, 0.3), Vector3(0.0, 0.3, 0.0), shadow).layers = COCKPIT_LAYER
	# Cara pálida, girada hacia ti, con ojos y boca negros.
	var face := Node3D.new()
	face.position = Vector3(-0.04, 0.78, -0.02)
	face.scale = Vector3.ONE * 0.85
	face.rotation.y = deg_to_rad(-55.0)
	_passenger.add_child(face)
	_box_in(face, Vector3(0.22, 0.3, 0.22), Vector3.ZERO, CarFactory.glow(Color(0.42, 0.42, 0.4), 0.06)).layers = COCKPIT_LAYER
	_box_in(face, Vector3(0.26, 0.12, 0.26), Vector3(0.0, 0.14, 0.01), shadow).layers = COCKPIT_LAYER   # pelo
	for side: float in [-1.0, 1.0]:
		_box_in(face, Vector3(0.055, 0.045, 0.02), Vector3(0.05 * side, 0.02, 0.11), shadow).layers = COCKPIT_LAYER
	_box_in(face, Vector3(0.07, 0.09, 0.02), Vector3(0.0, -0.08, 0.11), shadow).layers = COCKPIT_LAYER     # boca abierta

	_build_mirror()


## Retrovisor: una segunda cámara (de poca resolución) que mira hacia atrás.
func _build_mirror() -> void:
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(320, 96)
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 24.0
	_mirror_cam.near = 0.2
	_mirror_cam.far = 260.0
	_mirror_cam.cull_mask = 1                # no dibuja la cabina
	_mirror_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mirror_vp.add_child(_mirror_cam)

	var frame := _cockpit_box(Vector3(0.26, 0.08, 0.03), Vector3(0.02, 1.44, -0.5), CarFactory.flat(Color(0.02, 0.02, 0.02), 0.5))
	frame.rotation.x = deg_to_rad(-8.0)
	var glass := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.23, 0.065)
	glass.mesh = quad
	var mat := StandardMaterial3D.new()
	# La imagen ya viene "revelada": la usamos como luz propia para que el
	# filtro de color de la escena no la oscurezca otra vez.
	mat.albedo_color = Color.BLACK
	mat.emission_enabled = true
	mat.emission_texture = _mirror_vp.get_texture()
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 1.8
	mat.uv1_scale = Vector3(-1.0, 1.0, 1.0)  # los espejos dan la vuelta a la imagen
	mat.uv1_offset = Vector3(1.0, 0.0, 0.0)
	glass.material_override = mat
	glass.position = Vector3(0.0, 0.0, 0.016)
	glass.layers = COCKPIT_LAYER
	frame.add_child(glass)


func _cockpit_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := CarFactory.add_box(_cockpit, size, pos, mat)
	mi.layers = COCKPIT_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _box_in(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := CarFactory.add_box(parent, size, pos, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_sparks() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.top_level = true            # se coloca en coordenadas del mundo, no pegado al coche
	p.emitting = false
	p.one_shot = true
	p.amount = 28
	p.lifetime = 0.5
	p.explosiveness = 0.95
	p.spread = 55.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0.0, -22.0, 0.0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.22)
	mesh.material = CarFactory.glow(Color(1.0, 0.65, 0.2), 8.0)
	p.mesh = mesh
	return p


## Llamaradas azules por el tubo de escape mientras va el nitro.
func _make_exhaust_flames() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = Vector3(0.55, 0.4, CarFactory.LENGTH * 0.5 + 0.1)
	p.emitting = false
	p.amount = 30
	p.lifetime = 0.18
	p.direction = Vector3(0.0, 0.0, 1.0)
	p.spread = 8.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector3.ZERO
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	p.scale_amount_curve = shrink
	var mesh := SphereMesh.new()
	mesh.radius = 0.13
	mesh.height = 0.26
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = CarFactory.glow(Color(0.3, 0.55, 1.0), 6.0)
	p.mesh = mesh
	return p


func _make_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = Vector3(0.0, 0.25, 1.5)
	p.emitting = false
	p.amount = 36
	p.lifetime = 0.9
	p.local_coords = false        # el humo se queda atrás, no viaja con el coche
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.9, 0.05, 0.2)
	p.direction = Vector3.UP
	p.spread = 40.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0.0, 1.2, 0.0)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.35))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	p.scale_amount_min = 0.9
	p.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(0.5, 0.52, 0.58, 0.16))
	fade.set_color(1, Color(0.5, 0.52, 0.58, 0.0))
	p.color_ramp = fade
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	return p
