extends Node3D
## SIN FRENO (prototipo) — script principal: las reglas del juego.
##
## Llevas una bomba en el coche. En cuanto superas la velocidad mínima, se
## arma. Desde ese momento, si bajas de la mínima empieza a quemarse la mecha;
## si no vuelves a acelerar a tiempo... BOOM. Y la mínima va subiendo.
## Además ÉL te sigue por tu mismo camino: cada choque le acerca.
##
## Puntos estilo arcade: cada metro suma, y las jugadas arriesgadas (pasar
## rozando coches, derrapar, reventar vallas) suben el COMBO, que multiplica
## todo y rellena el nitro. Chocar contra muros o coches rompe el combo.
##
## Aquí están las reglas y el ambiente. El resto vive en los nodos hijos:
##   City, Car, Camera, Traffic, Audio, HUD (y Pursuer y Apparitions, que se
##   crean por código).

enum State { TITLE, UNARMED, ARMED, EXPLODED }

const SAVE_PATH := "user://sin_freno.cfg"
# Ojo: los Color de Godot van en sRGB (como en el selector de color) y el
# "tonemap" oscurece mucho los tonos bajos, así que estos valores parecen
# claros pero en pantalla quedan como una noche cerrada.
const NIGHT_COLOR := Color(0.1, 0.11, 0.18)       # color del cielo y de la niebla
const AMBIENT_ENERGY := 0.6
const MOON_ENERGY := 0.25
const START_POS := Vector3(40.0, 0.0, 0.0)        # el centro de una calle

const RADIO_START := "«Hay un regalo debajo de tu asiento. Arranca.»"
const RADIO_ARMED := "«Ya está armada. Si bajas de %d km/h... adiós.»"
const RADIO_HIM := "«Mira por el retrovisor. No estás solo.»"
const RADIO_LEVELS: Array[String] = [
	"«Te veo muy tranquilo. Ahora el mínimo es %d.»",
	"«Más rápido. %d km/h.»",
	"«Él tiene hambre. %d.»",
	"«¿Te tiemblan las manos? %d km/h.»",
	"«Nadie va a venir a ayudarte. %d.»",
	"«%d. Te estoy mirando.»",
	"«Ya casi te tiene. %d.»",
	"«%d. No mires atrás.»",
	"«%d. ¿Oyes tu corazón?»",
	"«%d.»",
]
const RADIO_BLACKOUT: Array[String] = [
	"«Vamos a apagar las luces.»",
	"«A oscuras se conduce mejor, ¿no?»",
	"«Shhh.»",
]
const RADIO_SHADOWS: Array[String] = [
	"«¿Has visto eso?»",
	"«No los mires.»",
	"«Ellos también te esperan.»",
]

const COMBO_MAX := 5.0
const COMBO_WINDOW := 4.0      ## segundos que dura el combo sin hacer nada

## Después de reintentar nos saltamos la pantalla de título.
static var quick_restart := false
## La cámara elegida se mantiene al reintentar.
static var first_person := true

@export_group("Bomba")
@export var start_min_kmh := 70.0       ## velocidad mínima al empezar
@export var max_min_kmh := 170.0        ## hasta dónde llega a subir
@export var level_step_kmh := 10.0      ## cuánto sube en cada nivel
@export var level_time := 20.0          ## segundos entre subidas
@export var fuse_time := 2.5            ## segundos que aguantas por debajo de la mínima
@export var fuse_recover := 0.4         ## rapidez con la que se recupera la mecha

@export_group("Él")
@export var pursuer_extra_kmh := 25.0   ## ÉL va siempre a la mínima + esto

@export_group("Ambiente")
@export var rain := true
@export var lightning := true
@export var reflections := true         ## reflejos en el asfalto mojado; apágalo si va lento
@export var blackouts := true
@export var shadows := true             ## las figuras en la calle
@export_range(0.0, 1.0) var jumpscare_chance := 0.3   ## probabilidad de susto con cada relámpago

var state := State.TITLE
var min_kmh := 70.0        # velocidad mínima actual (sube poco a poco hasta la del nivel)
var level := 0
var fuse := 2.5            # segundos de mecha que quedan
var run_time := 0.0        # segundos con la bomba armada
var distance := 0.0        # metros recorridos con la bomba armada
var top_speed := 0.0
var score := 0.0
var combo := 1.0
var combo_left := 0.0      # 1 = recién subido, 0 = se acaba
var near_misses := 0
var turbos := 0
var best_score := 0.0

var _env: Environment
var _moon: DirectionalLight3D
var _rain_fx: GPUParticles3D
var _beep_wait := 0.0
var _lightning_wait := 7.0
var _blackout_left := 0.0
var _scare := 0.0          # susto reciente (se va apagando)
var _glitch := 0.0
var _exploded_at := 0      # reloj real (ms) del momento de la explosión
var _game_over_shown := false
var _new_record := false
var _death_reason := "¡BOOM!"
var _earned := 0           # chatarra ganada en esta partida
var _pulse_cd := 0.0       # segundos que le faltan al pulso para recargarse
var _slowmo_uses := 0
var _slowmo_on := false
var _dark_floor := 0.0     # luz mínima en los apagones (con los faros mejorados)
var shop: Shop

@onready var city: City = $City
@onready var car: PlayerCar = $Car
@onready var cam: ChaseCamera = $Camera
@onready var traffic: Traffic = $Traffic
@onready var audio: GameAudio = $Audio
@onready var hud: Hud = $HUD
var pursuer: Pursuer
var apparitions: Apparitions


func _ready() -> void:
	Engine.time_scale = 1.0
	_load_record()
	Upgrades.load_data()
	_build_environment()

	pursuer = Pursuer.new()
	add_child(pursuer)
	apparitions = Apparitions.new()
	add_child(apparitions)

	car.global_position = START_POS
	car.reset_physics_interpolation()
	city.target = car
	city.prewarm()
	traffic.target = car
	traffic.city = city
	pursuer.target = car
	apparitions.target = car
	apparitions.city = city
	cam.target = car
	cam.first_person = first_person
	cam.snap()
	car.crashed.connect(_on_car_crashed)
	car.prop_hit.connect(_on_prop_hit)
	car.drift_boost.connect(_on_drift_boost)
	traffic.near_miss.connect(_on_near_miss)
	pursuer.caught.connect(_on_caught)
	apparitions.scared.connect(_on_shadow)
	hud.set_record(best_score)
	car.armor_used.connect(_on_armor_used)
	_apply_upgrades()
	min_kmh = start_min_kmh
	fuse = fuse_time

	shop = Shop.new()
	hud.add_child(shop)
	shop.closed.connect(_on_shop_closed)

	# El retrovisor usa una copia del ambiente sin reflejos ni resplandor (más barato).
	var mirror_env := _env.duplicate() as Environment
	mirror_env.ssr_enabled = false
	mirror_env.glow_enabled = false
	car.set_mirror_environment(mirror_env)

	# "Calentar" los efectos ahora, para que no den un tirón la primera vez
	# que aparecen en mitad de la partida.
	Explosion.warm_up(self, START_POS)
	car.warm_up()

	if quick_restart:
		_start_run()
	else:
		cam.start_orbit(PI * 0.82)   # la cámara empieza mirando el coche de frente
		hud.show_title()

	# Modo de pruebas automáticas (ver scripts/dev_autotest.gd).
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest"):
			var tester = load("res://scripts/dev_autotest.gd").new()
			tester.main = self
			add_child(tester)
			break


func _unhandled_input(event: InputEvent) -> void:
	if shop.visible:
		return
	if event.is_action_pressed("shop") and (state == State.TITLE or _game_over_shown):
		hud.hide_menus(true, state == State.TITLE)
		shop.open()
	elif event.is_action_pressed("pulse"):
		_use_pulse()
	elif event.is_action_pressed("slowmo"):
		_use_slowmo()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event.is_action_pressed("restart") and state != State.TITLE:
		_restart()
	elif event.is_action_pressed("ui_accept") and _game_over_shown:
		_restart()
	elif event.is_action_pressed("camera"):
		set_first_person(not first_person)


func set_first_person(on: bool) -> void:
	first_person = on
	cam.first_person = on
	if state == State.UNARMED or state == State.ARMED:
		car.set_first_person(on)


func _physics_process(delta: float) -> void:
	match state:
		State.TITLE:
			if shop.visible:
				return
			if Input.is_action_just_pressed("accelerate") or Input.is_action_just_pressed("ui_accept"):
				_start_run()
		State.UNARMED:
			# La bomba se arma al pasar con algo de margen de la velocidad mínima.
			if car.speed_kmh >= min_kmh + 5.0:
				_arm_bomb()
		State.ARMED:
			_update_bomb(delta)


func _process(delta: float) -> void:
	var armed := state == State.ARMED
	var danger := 1.0 - fuse / fuse_time if armed else 0.0

	# Combo: se va gastando; al acabarse vuelve a x1.
	if combo > 1.0:
		combo_left -= delta / COMBO_WINDOW
		if combo_left <= 0.0:
			combo = 1.0

	# Miedo: lo que más asuste en cada momento.
	_scare = move_toward(_scare, 0.0, delta * 0.6)
	_glitch = move_toward(_glitch, 0.0, delta * 2.5)
	var fear := maxf(maxf(danger * 0.8, pursuer.closeness()), _scare)
	if _blackout_left > 0.0:
		fear = maxf(fear, 0.4)
	if pursuer.closeness() > 0.8:
		_glitch = maxf(_glitch, (pursuer.closeness() - 0.8) * 2.0)

	hud.set_drive(car.speed_kmh, min_kmh, armed, danger, car.nitro, car.boosting)
	hud.set_score(score, combo, combo_left, distance)
	hud.set_pursuer(pursuer.gap if pursuer.active else -1.0)
	hud.set_fx(fear, _glitch, danger, cam.boost_kick)
	var heading := car.vel.normalized() if car.speed > 5.0 else -car.global_transform.basis.z
	var closure := city.closure_ahead(car.global_position, heading)
	var turn := city.best_turn(car.global_position, heading, closure) if closure < 260.0 else 0
	hud.set_closure(closure, turn)
	_update_bomb_display(armed)
	_pulse_cd = maxf(0.0, _pulse_cd - delta)
	hud.set_abilities(_abilities_text())

	cam.rumble = danger * 0.5 + clampf((car.speed_kmh - 110.0) / 300.0, 0.0, 0.3) + (0.25 if car.boosting else 0.0)
	audio.update_engine(car.speed_kmh, car.throttle_in, car.boosting, delta)
	audio.set_skid(clampf((absf(car.slip) - 3.0) / 12.0, 0.0, 1.0), delta)
	audio.set_fear(fear if state != State.EXPLODED else 0.0, delta)

	if _rain_fx != null:
		# La lluvia cae alrededor de la cámara, adelantada hacia donde vamos.
		_rain_fx.global_position = cam.global_position + car.vel * 0.4 + Vector3.UP * 14.0
	_update_lightning(delta)
	_update_blackout(delta)

	# Tras la explosión: un momento a cámara lenta y luego la pantalla de fin.
	if state == State.EXPLODED and not _game_over_shown and Time.get_ticks_msec() - _exploded_at > 1400:
		_game_over_shown = true
		Engine.time_scale = 1.0
		var lines := "Puntos   %s\nDistancia   %.2f km     Tiempo   %s\nVelocidad máxima   %d km/h\nCasi choques   %d     Turbos   %d" % [
			_thousands(roundi(score)), distance / 1000.0, _clock(run_time), roundi(top_speed), near_misses, turbos]
		lines += "\n\n+%d de chatarra   (tienes %d)" % [_earned, Upgrades.scrap]
		if _new_record:
			lines += "\n¡NUEVO RÉCORD!"
		hud.show_game_over(_death_reason, lines)


# --------------------------------------------------------------- la partida

func _start_run() -> void:
	state = State.UNARMED
	car.controls_enabled = true
	car.set_first_person(first_person)
	cam.stop_orbit()
	traffic.active = true
	hud.show_drive()
	_radio(RADIO_START, 5.0)


func _arm_bomb() -> void:
	state = State.ARMED
	fuse = fuse_time
	_beep_wait = 0.0
	_radio(RADIO_ARMED % roundi(min_kmh), 4.0)
	apparitions.active = shadows
	# ÉL aparece unos segundos después.
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		if state == State.ARMED:
			pursuer.start()
			_radio(RADIO_HIM, 4.0)
			_scare = 0.7)


func _update_bomb(delta: float) -> void:
	run_time += delta
	var step := car.speed * delta
	distance += step
	score += step * combo
	top_speed = maxf(top_speed, car.speed_kmh)
	pursuer.speed_kmh = min_kmh + pursuer_extra_kmh

	# Cada cierto tiempo sube el nivel, y con él la velocidad mínima.
	var max_level := int((max_min_kmh - start_min_kmh) / level_step_kmh)
	if level < max_level and run_time >= (level + 1) * level_time:
		level += 1
		var new_min := roundi(start_min_kmh + level * level_step_kmh)
		_radio(RADIO_LEVELS[mini(level - 1, RADIO_LEVELS.size() - 1)] % new_min, 4.0)
		hud.pulse_min()
		hud.popup("NIVEL %d" % (level + 1), Hud.RED, true)
		traffic.density = minf(1.0, 0.6 + level * 0.08)
		apparitions.rate = 1.0 + level * 0.25
		if blackouts and level % 2 == 0:
			get_tree().create_timer(3.0).timeout.connect(_start_blackout)
	# La mínima no salta de golpe: sube poco a poco hasta la del nivel.
	min_kmh = move_toward(min_kmh, start_min_kmh + level * level_step_kmh, 4.0 * delta)

	# La mecha: se quema por debajo de la mínima y se recupera por encima.
	var margin := car.speed_kmh - min_kmh
	if margin < 0.0:
		fuse -= delta
	else:
		fuse = minf(fuse + delta * fuse_recover, fuse_time)
	if fuse <= 0.0:
		_explode("¡BOOM!")
		return

	# Pitidos: más seguidos cuanto más cerca estás de la mínima.
	_beep_wait -= delta
	if _beep_wait <= 0.0:
		var urgency := 0.0
		if margin < 0.0:
			urgency = 1.0
			_beep_wait = lerpf(0.07, 0.25, fuse / fuse_time)
		elif margin < 25.0:
			urgency = 0.25 + 0.4 * (1.0 - margin / 25.0)
			_beep_wait = lerpf(0.3, 0.9, margin / 25.0)
		else:
			_beep_wait = 1.2
		audio.beep(urgency)
		car.bomb_blink()


## La pantalla de la bomba del salpicadero.
func _update_bomb_display(armed: bool) -> void:
	if not armed:
		car.set_bomb_display("--.-" if state != State.EXPLODED else "", false)
	elif car.speed_kmh < min_kmh:
		car.set_bomb_display("%.1f" % maxf(fuse, 0.0), true)
	else:
		car.set_bomb_display("%d" % roundi(min_kmh), false)


func _explode(reason: String) -> void:
	if state == State.EXPLODED:
		return
	state = State.EXPLODED
	_death_reason = reason
	_new_record = score > best_score
	if _new_record:
		best_score = score
		_save_record()
	_earned = Upgrades.scrap_for(score)
	Upgrades.scrap += _earned
	Upgrades.save_data()
	_slowmo_on = false
	pursuer.stop()
	apparitions.active = false
	Explosion.spawn(self, car.global_position, car.vel, car.body_color)
	car.destroy()
	cam.shake = 3.0
	cam.start_orbit(0.0, 14.0)
	audio.explosion()
	hud.explode()
	Engine.time_scale = 0.3          # cámara lenta
	_exploded_at = Time.get_ticks_msec()


func _restart() -> void:
	quick_restart = true
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ------------------------------------------------------- puntos y combos

## Una jugada arriesgada: suma puntos (multiplicados), sube el combo y da nitro.
func _stunt(text: String, points: float, nitro_gain: float) -> void:
	if state != State.ARMED:
		return
	combo = minf(combo + 0.5, COMBO_MAX)
	combo_left = 1.0
	var gained := roundi(points * combo)
	score += gained
	car.nitro = minf(1.0, car.nitro + nitro_gain)
	hud.popup("%s  +%d" % [text, gained])
	hud.pulse_combo()
	audio.ding(combo)


func _break_combo() -> void:
	if combo > 1.0:
		hud.popup("COMBO ROTO", Hud.RED)
	combo = 1.0
	combo_left = 0.0


func _on_near_miss(_car: Knockable) -> void:
	near_misses += 1
	audio.whoosh()
	_stunt("¡CASI!", 250.0, 0.14)


func _on_drift_boost(charge: float) -> void:
	turbos += 1
	cam.shake = maxf(cam.shake, 0.4)
	_stunt("¡TURBO!", 200.0 + charge * 300.0, 0.0)


func _on_car_crashed(impact: float) -> void:
	cam.shake = maxf(cam.shake, clampf(impact / 20.0, 0.2, 1.5))
	audio.crash(impact / 30.0)
	if impact > 8.0:
		_break_combo()


func _on_prop_hit(prop: Knockable, lost: float) -> void:
	cam.shake = maxf(cam.shake, 0.3 + lost * 2.0)
	audio.crash(0.4 + lost * 1.5)
	if prop.penalty < 0.1:
		_stunt("¡FUERA!", 80.0, 0.04)    # vallas: dan puntos
	else:
		_break_combo()                   # coches y contenedores: rompen el combo


# ------------------------------------------------------------- terror

func _on_caught() -> void:
	audio.sting()
	_glitch = 1.0
	_explode("TE ALCANZÓ")


func _on_shadow(hit: bool) -> void:
	if hit:
		audio.sting()
	else:
		audio.radio_static()
	_scare = 1.0 if hit else 0.6
	_glitch = 1.0 if hit else 0.5
	if hit:
		car.vel *= 0.85
		cam.shake = maxf(cam.shake, 0.8)
		if randf() < 0.5:
			_radio(RADIO_SHADOWS.pick_random(), 3.0)


func _radio(text: String, seconds: float) -> void:
	hud.say(text, seconds)
	audio.radio_static()
	_glitch = maxf(_glitch, 0.25)


## Apagón: la ciudad parpadea y se queda a oscuras unos segundos.
func _start_blackout() -> void:
	if state != State.ARMED:
		return
	_radio(RADIO_BLACKOUT.pick_random(), 3.0)
	_blackout_left = randf_range(7.0, 10.0)
	var tw := create_tween()
	for p: float in [0.2, 1.0, 0.1, 0.7, _dark_floor]:
		tw.tween_callback(city.set_power.bind(p))
		tw.tween_interval(0.12)


func _update_blackout(delta: float) -> void:
	if _blackout_left <= 0.0:
		return
	_blackout_left -= delta
	if _blackout_left <= 0.0 or state == State.EXPLODED:
		_blackout_left = 0.0
		var tw := create_tween()
		for p: float in [0.6, 0.0, 0.3, 0.0, 1.0]:
			tw.tween_callback(city.set_power.bind(p))
			tw.tween_interval(0.1)


# ------------------------------------------------------------------ récord

func _load_record() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = float(cfg.get_value("record", "score", 0.0))


func _save_record() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # cargamos antes para no borrar la tienda
	cfg.set_value("record", "score", best_score)
	cfg.save(SAVE_PATH)


# ---------------------------------------------------- tienda y habilidades

## Las mejoras compradas cambian los números del juego al empezar.
func _apply_upgrades() -> void:
	fuse_time += 0.4 * Upgrades.level("fuse")
	var tank := Upgrades.level("tank")
	car.nitro_drain *= 1.0 - 0.15 * tank
	car.nitro = 0.5 + 0.15 * tank
	var engine := Upgrades.level("engine")
	car.engine_accel *= 1.0 + 0.08 * engine
	car.max_speed_kmh += 10.0 * engine
	car.armor = Upgrades.level("armor")
	if Upgrades.level("lights") > 0:
		car.long_beams()
		_dark_floor = 0.18
	_slowmo_uses = Upgrades.level("slowmo")


func _on_shop_closed(bought: bool) -> void:
	if bought and state == State.TITLE:
		# Volvemos a cargar para que las mejoras se apliquen ya.
		get_tree().reload_current_scene()
		return
	hud.hide_menus(false, state == State.TITLE)


## Pulso: empuja a ÉL hacia atrás.
func _use_pulse() -> void:
	var lvl := Upgrades.level("pulse")
	if lvl == 0 or state != State.ARMED or _pulse_cd > 0.0 or not pursuer.active:
		return
	_pulse_cd = 25.0 if lvl == 1 else 15.0
	pursuer.gap = minf(pursuer.gap + 60.0, pursuer.max_gap)
	_glitch = 1.0
	cam.shake = maxf(cam.shake, 0.6)
	audio.radio_static()
	audio.whoosh()
	hud.popup("¡PULSO!", Hud.NITRO_BLUE, true)


## Frenazo de pánico: el tiempo va lento unos segundos.
func _use_slowmo() -> void:
	if _slowmo_uses <= 0 or state != State.ARMED or _slowmo_on:
		return
	_slowmo_uses -= 1
	_slowmo_on = true
	Engine.time_scale = 0.4
	hud.popup("TIEMPO LENTO", Hud.PALE, true)
	audio.whoosh()
	# El temporizador cuenta en tiempo real (si no, también iría lento).
	get_tree().create_timer(3.0, true, false, true).timeout.connect(_end_slowmo)


func _end_slowmo() -> void:
	if _slowmo_on and state == State.ARMED:
		Engine.time_scale = 1.0
	_slowmo_on = false


func _on_armor_used() -> void:
	cam.shake = maxf(cam.shake, 0.8)
	audio.crash(0.8)
	hud.popup("¡BLINDAJE!  quedan %d" % car.armor, Hud.PALE)


func _abilities_text() -> String:
	if state != State.ARMED and state != State.UNARMED:
		return ""
	var parts: Array[String] = []
	if Upgrades.level("pulse") > 0:
		parts.append("Q  PULSO  " + ("listo" if _pulse_cd <= 0.0 else "%d s" % ceili(_pulse_cd)))
	if Upgrades.level("slowmo") > 0:
		parts.append("E  FRENAZO  x%d" % _slowmo_uses)
	if Upgrades.level("armor") > 0:
		parts.append("BLINDAJE  x%d" % car.armor)
	return "\n".join(parts)


func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


# ---------------------------------------------------------------- ambiente

func _build_environment() -> void:
	_env = Environment.new()
	# Cielo de un solo color, igual que la niebla: así lo lejano se funde con
	# el fondo y no se ve dónde se acaba la ciudad.
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = NIGHT_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.45, 0.55, 0.85)
	_env.ambient_light_energy = AMBIENT_ENERGY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Niebla por distancia: empieza cerca y lo tapa todo a 260 m.
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_light_color = NIGHT_COLOR
	_env.fog_density = 1.0
	_env.fog_depth_begin = 12.0
	_env.fog_depth_end = 260.0
	# Resplandor alrededor de todo lo que brilla (ventanas, neones, faros).
	_env.glow_enabled = true
	_env.glow_intensity = 0.7
	_env.glow_bloom = 0.03
	_env.glow_hdr_threshold = 0.8
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	if reflections:
		_env.ssr_enabled = true
		_env.ssr_max_steps = 48
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.1
	_env.adjustment_saturation = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)

	# Una luna muy tenue, para que los edificios no sean siluetas planas.
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 1.0)
	_moon.light_energy = MOON_ENERGY
	_moon.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	add_child(_moon)

	if rain:
		_build_rain()


func _build_rain() -> void:
	_rain_fx = GPUParticles3D.new()
	_rain_fx.amount = 3000
	_rain_fx.lifetime = 0.8
	_rain_fx.local_coords = false     # las gotas se quedan en el mundo: al correr, pasan volando
	_rain_fx.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rain_fx.visibility_aabb = AABB(Vector3(-70.0, -40.0, -70.0), Vector3(140.0, 60.0, 140.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(32.0, 0.5, 32.0)
	pm.direction = Vector3(0.08, -1.0, 0.03)
	pm.spread = 1.5
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0.0, -8.0, 0.0)
	_rain_fx.process_material = pm
	var drop := QuadMesh.new()
	drop.size = Vector2(0.018, 0.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.8, 0.95, 0.16)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	drop.material = mat
	_rain_fx.draw_pass_1 = drop
	add_child(_rain_fx)


## De vez en cuando, un relámpago ilumina la ciudad un instante. A veces, con
## esa luz, ves que hay alguien sentado a tu lado.
func _update_lightning(delta: float) -> void:
	if not lightning:
		return
	_lightning_wait -= delta
	if _lightning_wait > 0.0:
		return
	_lightning_wait = randf_range(8.0, 20.0)
	var tw := create_tween()
	tw.tween_method(_set_flash, 0.0, 1.0, 0.05)
	tw.tween_method(_set_flash, 1.0, 0.15, 0.1)
	tw.tween_method(_set_flash, 0.15, 0.7, 0.04)
	tw.tween_method(_set_flash, 0.7, 0.0, 0.6)
	get_tree().create_timer(randf_range(0.4, 1.6)).timeout.connect(audio.thunder)
	if state == State.ARMED and first_person and randf() < jumpscare_chance:
		car.show_passenger(0.3)
		audio.sting()
		_scare = 1.0
		_glitch = 0.8


func _set_flash(amount: float) -> void:
	var sky := NIGHT_COLOR.lerp(Color(0.55, 0.6, 0.8), amount)
	_env.background_color = sky
	_env.fog_light_color = sky
	_env.ambient_light_energy = lerpf(AMBIENT_ENERGY, AMBIENT_ENERGY * 4.0, amount)
	_moon.light_energy = lerpf(MOON_ENERGY, 2.5, amount)
