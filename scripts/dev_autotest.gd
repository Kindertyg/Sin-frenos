extends Node
## SOLO PARA PRUEBAS. No forma parte del juego: puedes borrar este archivo.
##
## Se activa lanzando el juego con argumentos después de "--":
##     godot --path . -- --autotest             conduce recto y al final frena
##     godot --path . -- --autotest=crash       gira hasta chocar contra un edificio
##     godot --path . -- --autotest=weave       va haciendo eses entre el tráfico
##     godot --path . -- --autotest=long        conduce recto más de un minuto (sube de nivel)
##     godot --path . -- --autotest=closure     va recto hasta una calle cortada
##     godot --path . -- --autotest=corner:120  toma una curva de 90 grados a 120 km/h
##     godot --path . -- --autotest=restart     explota, reintenta y vuelve a arrancar
##     ... --shots=C:/carpeta                   guarda capturas en esa carpeta
## Conduce solo, escribe datos en la consola y cierra el juego al terminar.

var main            # el nodo Main (lo pone main.gd)
var mode := "straight"
var shots_dir := ""
var _clock := 0.0          # segundos reales, sin contar los tirones largos
var _last_ms := 0
var _next_log := 0.0
var _done := {}
var _explosion_at := -1.0
var _crashes := 0
var _props := 0
var _corner_speed := 120.0
var _corner_phase := 0

static var _runs := 0      # cuántas veces se ha cargado la escena (modo restart)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest="):
			mode = arg.get_slice("=", 1)
		elif arg.begins_with("--shots="):
			shots_dir = arg.get_slice("=", 1)
	if mode.begins_with("corner"):
		if mode.contains(":"):
			_corner_speed = mode.get_slice(":", 1).to_float()
		mode = "corner"
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	_last_ms = Time.get_ticks_msec()

	# Así las pruebas no pisan el récord del jugador.
	main.best_score = 1.0e12
	# Las calles cortadas solo se prueban en su propio modo; en el resto
	# estorbarían al piloto automático, que no sabe esquivarlas.
	main.city.closure_chance = 1.0 if mode == "closure" else 0.0
	main.city.rebuild()

	main.car.crashed.connect(_on_crash)
	main.car.prop_hit.connect(_on_prop)
	_runs += 1
	print("[autotest] modo=", mode, " capturas=", shots_dir, " carga nº ", _runs)


func _on_crash(impact: float) -> void:
	_crashes += 1
	print("[autotest] choque contra muro: golpe de %.1f m/s" % impact)


func _on_prop(_prop: Knockable, lost: float) -> void:
	_props += 1
	print("[autotest] objeto golpeado: pierde %.0f%% de velocidad" % (lost * 100.0))


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var frame_ms := now - _last_ms
	_last_ms = now
	if frame_ms > 250:
		print("[autotest] TIRÓN de %d ms en t=%.1f" % [frame_ms, _clock])
	_clock += minf(frame_ms / 1000.0, 0.1)
	var t := _clock
	var car: PlayerCar = main.car
	var exploded: bool = main.state == main.State.EXPLODED

	if t >= _next_log:
		_next_log += 1.0
		print("[autotest] t=%.0f estado=%d vel=%.0f min=%.0f mecha=%.2f dist=%.0f fps=%d objetos=%d draw=%d" % [
			t, main.state, car.speed_kmh, main.min_kmh, main.fuse, main.distance,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])

	if _once("title", t, 1.5):
		_shot("1_titulo")
	if mode == "shop" and _runs == 1:
		# Primera carga: tienda con chatarra de prueba, comprarlo todo y salir.
		if _once("s_open", t, 1.0):
			Upgrades.scrap = 9000
			main.hud.hide_menus(true, true)
			main.shop.open()
		if _once("s_shot1", t, 1.4):
			_shot("7_tienda")
		if _once("s_buy", t, 1.8):
			for u in Upgrades.LIST:
				for k in 3:
					main.shop._on_buy(u["id"])
			main.shop._buttons[5].grab_focus()
		if _once("s_shot2", t, 2.1):
			_shot("7_tienda_comprado")
		if _once("s_close", t, 2.4):
			main.shop.close()
		return
	if _once("go", t, 2.2):
		main._start_run()
		car.external_input = true
		car.throttle_in = 1.0
	if _once("shot2", t, 5.5):
		_shot("2_arrancando")

	var end_time := 14.0
	match mode:
		"straight":
			if _once("shot3", t, 9.0):
				_shot("3_rapido")
		"crash":
			# Derrape hacia la derecha hasta meterse contra los edificios.
			if _once("turn", t, 7.0):
				car.steer_in = -1.0
				car.handbrake_in = true
			if _once("unturn", t, 7.5):
				car.handbrake_in = false
			if _once("shot_crash", t, 8.1):
				_shot("3b_choque")
			end_time = 30.0
		"weave":
			# Eses por toda la calle: acaba tocando tráfico, aparcados y vallas.
			end_time = 26.0
			if t > 4.0 and t < end_time and not exploded:
				_steer_to_x(car, 40.0 + 7.6 * sin((t - 4.0) * 0.7))
			if _once("shot_weave", t, 16.0):
				_shot("3c_eses")
		"long":
			end_time = 70.0
		"closure":
			# Recto hasta el muro: comprueba el aviso y el choque.
			end_time = 60.0
			var ahead: float = main.city.closure_ahead(car.global_position, Vector3.FORWARD)
			if ahead < 150.0 and _once("shot_far", t, 0.0):
				print("[autotest] calle cortada a %.0f m" % ahead)
				_shot("3d_corte_lejos")
			if ahead < 45.0 and _once("shot_near", t, 0.0):
				_shot("3e_corte_cerca")
		"restart":
			end_time = 6.0
			if _runs >= 2:
				# Segunda carga: debe haber arrancado directamente, sin título.
				if _once("check", t, 0.5):
					print("[autotest] tras reiniciar: estado=%d (1 = conduciendo sin título)" % main.state)
				if _once("quit2", t, 4.0):
					print("[autotest] fin")
					get_tree().quit()
				return
			if exploded and _explosion_at >= 0.0 and _once("again", t, _explosion_at + 2.5):
				print("[autotest] reintentando...")
				main._restart()
				return
		"corner":
			end_time = 60.0
			if t > 2.3 and not exploded:
				_drive_corner(car)
		"shop":
			end_time = 40.0
			if _once("s_info", t, 2.5):
				print("[autotest] mejoras: mecha=%.1f s, blindaje=%d, nitro_drain=%.2f, max=%d" % [main.fuse_time, car.armor, car.nitro_drain, car.max_speed_kmh])
			if _once("s_turn", t, 10.0):
				car.steer_in = -1.0
			if _once("s_unturn", t, 10.8):
				car.steer_in = 0.0
				print("[autotest] tras el muro: %.0f km/h, blindaje=%d" % [car.speed_kmh, car.armor])
			if _once("s_shot3", t, 10.9):
				_shot("8_blindaje")
			if _once("s_pulse", t, 9.0):
				var before: float = main.pursuer.gap
				main.pursuer.gap = 40.0
				main._use_pulse()
				print("[autotest] pulso: hueco 40 -> %.0f m" % main.pursuer.gap)
			if _once("s_shot4", t, 9.2):
				_shot("9_pulso")
			if _once("s_slow", t, 5.0):
				main._use_slowmo()
				print("[autotest] frenazo: time_scale=%.2f" % Engine.time_scale)
			if _once("s_slow_mid", t, 6.0):
				print("[autotest] durante frenazo: time_scale=%.2f" % Engine.time_scale)
			if _once("s_slow_end", t, 8.5):
				print("[autotest] tras frenazo: time_scale=%.2f" % Engine.time_scale)
			if _once("s_end", t, 18.0):
				end_time = t
		"him":
			# ÉL se acerca: retrovisor y "te alcanzó".
			end_time = 60.0
			if _once("him_close", t, 12.0):
				main.pursuer.gap = 45.0
			if t > 12.0 and not exploded:
				car.throttle_in = 1.0 if car.speed_kmh < 82.0 else 0.0
				car.brake_in = 1.0 if car.speed_kmh > 95.0 else 0.0
			if _once("shot_him1", t, 12.6):
				_shot("3f_el_lejos")
			if main.pursuer.gap < 14.0 and _once("shot_him2", t, 0.0):
				_shot("3g_el_encima")
		"horror":
			# Apagón, una sombra en la calle y el copiloto.
			end_time = 60.0
			if _once("blackout", t, 9.0):
				main._start_blackout()
			if _once("shot_dark", t, 10.5):
				_shot("3h_apagon")
			if _once("shadow", t, 12.0):
				main.apparitions._spawn(car.global_position)
				main.apparitions._vanish_at.fill(0.0)
			if _once("shot_shadow", t, 12.9):
				_shot("3i_sombra")
			if _once("passenger", t, 15.0):
				car.show_passenger(1.0)
			if _once("shot_passenger", t, 15.2):
				_shot("3j_copiloto")
			if _once("tp", t, 16.0):
				main.set_first_person(false)
			if _once("shot_tp", t, 17.0):
				_shot("3k_tercera")
			if _once("end_h", t, 18.0):
				end_time = t
	if _once("brake", t, end_time):
		car.steer_in = 0.0
		car.throttle_in = 0.0
		car.brake_in = 1.0

	if exploded:
		if _explosion_at < 0.0:
			_explosion_at = t
			print("[autotest] BOOM en t=%.1f dist=%.0f muros=%d objetos=%d" % [t, main.distance, _crashes, _props])
		if _once("shot4", t, _explosion_at + 0.35):
			_shot("4_explosion")
		if _once("shot5", t, _explosion_at + 1.1):
			_shot("5_explosion_despues")
		if _once("shot6", t, _explosion_at + 3.0):
			_shot("6_fin")
		if _once("quit", t, _explosion_at + 3.6):
			print("[autotest] fin")
			get_tree().quit()
	elif t > 90.0:
		print("[autotest] se acabó el tiempo sin explosión")
		get_tree().quit()


## Volante automático: lleva el coche (que va hacia el norte) a la coordenada X pedida.
func _steer_to_x(car: PlayerCar, target_x: float) -> void:
	var wanted_yaw := -atan2(target_x - car.global_position.x, 25.0)
	car.steer_in = clampf(angle_difference(car.rotation.y, wanted_yaw) * 4.0, -1.0, 1.0)


## Curva de 90 grados a la izquierda en el cruce de z = -200, a la velocidad pedida.
func _drive_corner(car: PlayerCar) -> void:
	var exit_z := -200.0
	if _corner_phase < 3:
		car.throttle_in = 1.0 if car.speed_kmh < _corner_speed else 0.0
	match _corner_phase:
		0:  # recto hacia el norte por el centro, hasta el punto de giro
			_steer_to_x(car, 40.0)
			var max_speed := car.max_speed_kmh / 3.6
			var yaw_rate := car.steer_rate * lerpf(1.0, car.high_speed_steer, clampf(car.speed / max_speed, 0.0, 1.0))
			var radius := car.speed / yaw_rate
			if car.global_position.z - exit_z < radius + car.speed * 0.25:
				_corner_phase = 1
				print("[autotest] empieza a girar a %.0f km/h (radio estimado %.0f m)" % [car.speed_kmh, radius])
		1:  # volante a tope hasta mirar al oeste
			car.steer_in = 1.0
			if absf(angle_difference(car.rotation.y, PI * 0.5)) < 0.25:
				_corner_phase = 2
		2:  # seguir la calle este-oeste
			var off := car.global_position.z - exit_z
			car.steer_in = clampf(angle_difference(car.rotation.y, PI * 0.5 - atan2(off, 25.0)) * 4.0, -1.0, 1.0)
			if car.global_position.x < -10.0:
				_corner_phase = 3
				print("[autotest] CURVA a %.0f km/h: sale a %.0f km/h, desvío %.1f m, muros=%d" % [_corner_speed, car.speed_kmh, off, _crashes])
				car.steer_in = 0.0
				car.throttle_in = 0.0
				car.brake_in = 1.0


## Devuelve true una sola vez, cuando el tiempo pasa de `at`.
func _once(key: String, t: float, at: float) -> bool:
	if t < at or _done.has(key):
		return false
	_done[key] = true
	return true


func _shot(shot_name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := shots_dir.path_join(shot_name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	if main.car.first_person:
		main.car._mirror_vp.get_texture().get_image().save_png(shots_dir.path_join(shot_name + "_retrovisor.png"))
	print("[autotest] captura ", path)
