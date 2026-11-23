class_name Hud
extends CanvasLayer
## Todo lo que se dibuja encima del juego: puntos y combo, velocímetro, nitro,
## distancia al perseguidor, avisos, la "radio", el filtro de pantalla de
## miedo, el título y la pantalla de fin. Se construye por código.

const GAUGE_MAX := 260.0
const RED := Color(1.0, 0.22, 0.14)
const PALE := Color(0.86, 0.93, 1.0)
const GOLD := Color(1.0, 0.8, 0.2)
const NITRO_BLUE := Color(0.35, 0.65, 1.0)

## Filtro de pantalla: grano, colores separados (aberración), cortes tipo
## "glitch", borde oscuro y rojo cuando la bomba está a punto, y desenfoque
## hacia fuera con el nitro.
const POST_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float fear = 0.0;
uniform float glitch = 0.0;
uniform float danger = 0.0;
uniform float boost = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Glitch: bandas horizontales que se desplazan a saltos.
	float band = floor(uv.y * 36.0);
	float tick = floor(TIME * 24.0);
	float g = glitch * step(0.7, hash(vec2(band, tick)));
	uv.x += (hash(vec2(band + 7.0, tick)) - 0.5) * 0.12 * g;

	vec2 dir = uv - 0.5;
	float ca = 0.0015 + fear * 0.006 + glitch * 0.025 + boost * 0.004;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ca).b;
	// Nitro: estela hacia fuera desde el centro.
	if (boost > 0.01) {
		vec3 acc = vec3(0.0);
		for (int i = 1; i <= 6; i++) {
			acc += texture(screen_tex, uv - dir * boost * 0.018 * float(i)).rgb;
		}
		col = mix(col, acc / 6.0, clamp(length(dir) * 2.2, 0.0, 1.0) * boost);
	}
	// Con miedo, los colores se apagan.
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(l) * vec3(1.08, 0.95, 0.93), fear * 0.4);
	// Grano de película.
	col += (hash(uv * vec2(1280.0, 720.0) + fract(TIME * 7.13) * 100.0) - 0.5) * (0.035 + fear * 0.09 + glitch * 0.2);
	// Bordes oscuros que se cierran con el miedo; rojos con la bomba.
	float d = length((SCREEN_UV - 0.5) * vec2(1.0, 0.8));
	float edge = smoothstep(0.26 - fear * 0.08, 0.72, d);
	col *= 1.0 - edge * (0.6 + fear * 0.3);
	col = mix(col, vec3(0.75, 0.0, 0.0), edge * danger * 0.85);
	COLOR = vec4(col, 1.0);
}
"""


## El velocímetro: un arco dibujado a mano con draw_arc.
class Gauge extends Control:
	var speed := 0.0
	var min_speed := 60.0
	var armed := false
	var boosting := false

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 16.0
		var a0 := deg_to_rad(135.0)
		var sweep := deg_to_rad(270.0)
		var a_min := a0 + sweep * clampf(min_speed / GAUGE_MAX, 0.0, 1.0)
		var a_now := a0 + sweep * clampf(speed / GAUGE_MAX, 0.0, 1.0)
		var zone := RED if armed else GOLD

		draw_arc(c, r, a0, a0 + sweep, 64, Color(0.0, 0.0, 0.0, 0.5), 20.0, true)   # fondo
		draw_arc(c, r, a0, a_min, 32, Color(zone, 0.45), 20.0, true)                # zona prohibida
		for kmh in range(0, int(GAUGE_MAX) + 1, 20):                               # rayitas cada 20
			var dir := Vector2.from_angle(a0 + sweep * kmh / GAUGE_MAX)
			draw_line(c + dir * (r - 9.0), c + dir * (r + 9.0), Color(1.0, 1.0, 1.0, 0.25), 2.0, true)
		var below := armed and speed < min_speed
		var bar := RED if below else (NITRO_BLUE if boosting else PALE)
		if a_now - a0 > 0.01:
			draw_arc(c, r, a0, a_now, 48, bar, 8.0, true)                          # velocidad actual
		var min_dir := Vector2.from_angle(a_min)
		draw_line(c + min_dir * (r - 16.0), c + min_dir * (r + 16.0), zone, 5.0, true)   # marca del mínimo
		var now_dir := Vector2.from_angle(a_now)
		draw_line(c + now_dir * (r - 34.0), c + now_dir * (r + 10.0), Color.WHITE, 3.0, true)   # aguja


var _font: Font
var _root: Control
var _post: ShaderMaterial
var _flash: ColorRect
var _drive: Control          # todo lo que solo se ve conduciendo
var _gauge: Gauge
var _speed_label: Label
var _min_label: Label
var _status_label: Label
var _score_label: Label
var _combo_label: Label
var _combo_bar: ProgressBar
var _distance_label: Label
var _record_label: Label
var _nitro_bar: ProgressBar
var _nitro_label: Label
var _him_label: Label
var _abilities_label: Label
var _warning: Label
var _closure_label: Label
var _fuse_bar: ProgressBar
var _popups: Control
var _banner: Label
var _banner_time := 0.0
var _title: Control
var _title_prompt: Label
var _title_record: Label
var _over: Control
var _over_title: Label
var _over_stats: Label
var _over_prompt: Label
var _time := 0.0
var _min_pulse := 0.0
var _combo_pulse := 0.0
var _shown_score := 0.0


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "Arial"])
	font.font_weight = 700
	_font = font

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# El filtro va primero: así lo de encima (los textos) no se distorsiona.
	var shader := Shader.new()
	shader.code = POST_SHADER
	_post = ShaderMaterial.new()
	_post.shader = shader
	var post := _full_rect(Color.WHITE)
	post.material = _post
	_root.add_child(post)

	_build_drive()
	_build_title()
	_build_game_over()

	_banner = _label("", 28, Color(1.0, 0.55, 0.45))
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_banner.modulate.a = 0.0
	_place(_root, _banner, 0.5, 1.0, Vector2(-480.0, -150.0), Vector2(960.0, 90.0))

	_flash = _full_rect(Color(1.0, 0.9, 0.75))
	_flash.modulate.a = 0.0
	_root.add_child(_flash)


func _process(delta: float) -> void:
	_time += delta
	var blink := 0.55 + 0.45 * sin(_time * 5.0)
	_title_prompt.modulate.a = blink
	_over_prompt.modulate.a = blink
	_warning.modulate.a = 0.78 + 0.22 * sin(_time * 18.0)
	_min_pulse = move_toward(_min_pulse, 0.0, delta * 0.8)
	_min_label.scale = Vector2.ONE * (1.0 + _min_pulse * 0.6)
	_combo_pulse = move_toward(_combo_pulse, 0.0, delta * 3.0)
	_combo_label.scale = Vector2.ONE * (1.0 + _combo_pulse * 0.5)

	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time * 2.0, 0.0, 1.0)
		# La voz "tiembla" un poco.
		_banner.position.x = _banner.get_parent_area_size().x * 0.5 - 480.0 + randf_range(-1.5, 1.5)


# ------------------------------------------------------------ uso desde Main

## Datos de conducción. `danger` va de 0 (tranquilo) a 1 (la bomba explota ya).
func set_drive(speed_kmh: float, min_kmh: float, armed: bool, danger: float, nitro: float, boosting: bool) -> void:
	_gauge.speed = speed_kmh
	_gauge.min_speed = min_kmh
	_gauge.armed = armed
	_gauge.boosting = boosting
	_gauge.queue_redraw()
	_speed_label.text = str(roundi(speed_kmh))
	_min_label.text = "MÍN %d" % roundi(min_kmh)
	_min_label.label_settings.font_color = RED if armed else GOLD
	_status_label.text = "● BOMBA ARMADA" if armed else "○ BOMBA INACTIVA"
	_status_label.label_settings.font_color = RED if armed else Color(0.7, 0.7, 0.7)
	_nitro_bar.value = nitro
	_nitro_label.modulate.a = 1.0 if not boosting else 0.6 + 0.4 * sin(_time * 30.0)

	var below := armed and speed_kmh < min_kmh
	_warning.visible = below
	_fuse_bar.visible = armed and danger > 0.01
	_fuse_bar.value = 1.0 - danger


## Filtro de pantalla. Todo de 0 a 1.
func set_fx(fear: float, glitch: float, danger: float, boost: float) -> void:
	_post.set_shader_parameter("fear", fear)
	_post.set_shader_parameter("glitch", glitch)
	_post.set_shader_parameter("danger", danger * (0.75 + 0.25 * sin(_time * 14.0)))
	_post.set_shader_parameter("boost", boost)


## Estado de las habilidades compradas (texto ya preparado por Main).
func set_abilities(text: String) -> void:
	_abilities_label.text = text


## Distancia a "ÉL". Negativa = todavía no ha aparecido.
func set_pursuer(gap_m: float) -> void:
	_him_label.visible = gap_m >= 0.0
	if gap_m < 0.0:
		return
	_him_label.text = "ÉL  ·  %d m" % roundi(gap_m)
	var close := clampf(1.0 - gap_m / 110.0, 0.0, 1.0)
	_him_label.label_settings.font_color = PALE.lerp(RED, close)
	_him_label.modulate.a = 1.0 if close < 0.5 else 0.55 + 0.45 * sin(_time * (8.0 + close * 20.0))


## Aviso de calle cortada. `distance_m` = metros hasta el muro (INF = no hay).
## `turn` = hacia dónde conviene girar: -1 izquierda, 1 derecha, 0 da igual.
func set_closure(distance_m: float, turn: int) -> void:
	_closure_label.visible = distance_m < 260.0
	if _closure_label.visible:
		var meters := roundi(distance_m / 10.0) * 10
		if turn < 0:
			_closure_label.text = "←  GIRA  ·  CALLE CORTADA  %d m" % meters
		elif turn > 0:
			_closure_label.text = "CALLE CORTADA  %d m  ·  GIRA  →" % meters
		else:
			_closure_label.text = "←  CALLE CORTADA  %d m  ·  ¡GIRA!  →" % meters
		# Cerca del muro parpadea.
		_closure_label.modulate.a = 1.0 if distance_m > 130.0 else 0.6 + 0.4 * sin(_time * 16.0)


## Puntos, combo (multiplicador) y lo que le queda al combo (0-1).
func set_score(score: float, combo: float, combo_left: float, distance_m: float) -> void:
	# El marcador "cuenta" hacia arriba en vez de saltar.
	_shown_score = move_toward(_shown_score, score, maxf(30.0, (score - _shown_score) * 0.2))
	_score_label.text = _thousands(roundi(_shown_score))
	_combo_label.visible = combo > 1.01
	_combo_label.text = "x%.1f" % combo
	_combo_bar.visible = combo > 1.01
	_combo_bar.value = combo_left
	_distance_label.text = "%.2f km" % (distance_m / 1000.0)


func set_record(score: float) -> void:
	var text := "RÉCORD  %s" % _thousands(roundi(score)) if score > 0.0 else ""
	_record_label.text = text
	_title_record.text = text


## Texto que sale volando desde el centro: "¡CASI! +250".
func popup(text: String, color := GOLD, big := false) -> void:
	var l := _label(text, 46 if big else 34, color)
	_popups.add_child(l)
	l.size = Vector2(700.0, 60.0)
	l.position = Vector2(_popups.size.x * 0.5 - 350.0 + randf_range(-40.0, 40.0), _popups.size.y * 0.42)
	l.pivot_offset = Vector2(350.0, 30.0)
	l.scale = Vector2.ONE * 1.6
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 120.0, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)


func pulse_combo() -> void:
	_combo_pulse = 1.0


## Mensaje de la "radio" en la parte de abajo.
func say(text: String, seconds := 4.0) -> void:
	_banner.text = text
	_banner_time = seconds


## Hace "saltar" el texto del mínimo (cuando sube de nivel).
func pulse_min() -> void:
	_min_pulse = 1.0


func show_title() -> void:
	_title.visible = true
	_drive.visible = false
	_over.visible = false


func show_drive() -> void:
	_title.visible = false
	_drive.visible = true
	_over.visible = false


## Oculta o vuelve a enseñar el título y la pantalla de fin (para la tienda).
func hide_menus(hidden: bool, title: bool) -> void:
	_title.visible = title and not hidden
	_over.visible = not title and not hidden


func show_game_over(reason: String, lines: String) -> void:
	_drive.visible = false
	_over.visible = true
	_banner_time = 0.0
	_banner.modulate.a = 0.0
	_over_title.text = reason
	_over_stats.text = lines


## La bomba explota: fogonazo y fuera el velocímetro.
func explode() -> void:
	_drive.visible = false
	_flash.modulate.a = 0.9
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.5)


# ------------------------------------------------------------- construcción

func _build_drive() -> void:
	_drive = _layer()
	_drive.visible = false

	_popups = Control.new()
	_popups.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drive.add_child(_popups)

	# Velocímetro, abajo a la derecha.
	_gauge = Gauge.new()
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_drive, _gauge, 1.0, 1.0, Vector2(-300.0, -290.0), Vector2(270.0, 270.0))
	_speed_label = _label("0", 76, Color.WHITE)
	_place(_gauge, _speed_label, 0.5, 0.5, Vector2(-110.0, -62.0), Vector2(220.0, 84.0))
	_place(_gauge, _label("km/h", 20, Color(1.0, 1.0, 1.0, 0.6)), 0.5, 0.5, Vector2(-110.0, 22.0), Vector2(220.0, 26.0))
	_min_label = _label("MÍN 60", 26, RED)
	_place(_gauge, _min_label, 0.5, 1.0, Vector2(-110.0, -46.0), Vector2(220.0, 32.0))
	_min_label.pivot_offset = Vector2(110.0, 16.0)
	_status_label = _label("", 20, RED)
	_place(_drive, _status_label, 1.0, 1.0, Vector2(-300.0, -322.0), Vector2(270.0, 26.0))

	# Marcador, arriba a la izquierda.
	_score_label = _label("0", 54, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_drive, _score_label, 0.0, 0.0, Vector2(30.0, 14.0), Vector2(320.0, 60.0))
	_combo_label = _label("x1.0", 44, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_combo_label.pivot_offset = Vector2(0.0, 26.0)
	_place(_drive, _combo_label, 0.0, 0.0, Vector2(30.0, 74.0), Vector2(160.0, 52.0))
	_combo_bar = _bar(GOLD)
	_place(_drive, _combo_bar, 0.0, 0.0, Vector2(150.0, 96.0), Vector2(140.0, 8.0))
	_distance_label = _label("0.00 km", 22, PALE, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_drive, _distance_label, 0.0, 0.0, Vector2(32.0, 128.0), Vector2(300.0, 26.0))
	_record_label = _label("", 18, Color(1.0, 1.0, 1.0, 0.5), HORIZONTAL_ALIGNMENT_LEFT)
	_place(_drive, _record_label, 0.0, 0.0, Vector2(32.0, 154.0), Vector2(300.0, 24.0))

	# Nitro y perseguidor, abajo a la izquierda.
	_abilities_label = _label("", 20, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_drive, _abilities_label, 0.0, 1.0, Vector2(30.0, -206.0), Vector2(420.0, 88.0))
	_abilities_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_him_label = _label("", 30, PALE, HORIZONTAL_ALIGNMENT_LEFT)
	_him_label.visible = false
	_place(_drive, _him_label, 0.0, 1.0, Vector2(30.0, -112.0), Vector2(320.0, 36.0))
	_nitro_label = _label("NITRO  [SHIFT]", 20, NITRO_BLUE, HORIZONTAL_ALIGNMENT_LEFT)
	_place(_drive, _nitro_label, 0.0, 1.0, Vector2(30.0, -72.0), Vector2(320.0, 24.0))
	_nitro_bar = _bar(NITRO_BLUE)
	_place(_drive, _nitro_bar, 0.0, 1.0, Vector2(30.0, -44.0), Vector2(300.0, 16.0))

	# Aviso de calle cortada, arriba del todo.
	_closure_label = _label("", 30, Color(1.0, 0.7, 0.15))
	_closure_label.visible = false
	_place(_drive, _closure_label, 0.5, 0.0, Vector2(-400.0, 26.0), Vector2(800.0, 40.0))

	# Aviso de la bomba, arriba en el centro.
	_warning = _label("¡ACELERA!", 76, RED)
	_warning.visible = false
	_place(_drive, _warning, 0.5, 0.0, Vector2(-320.0, 96.0), Vector2(640.0, 90.0))
	_fuse_bar = _bar(RED)
	_fuse_bar.visible = false
	_place(_drive, _fuse_bar, 0.5, 0.0, Vector2(-190.0, 190.0), Vector2(380.0, 14.0))


func _build_title() -> void:
	_title = _layer()
	_title.add_child(_full_rect(Color(0.0, 0.0, 0.0, 0.35)))
	_place(_title, _label("SIN FRENO", 132, Color.WHITE), 0.5, 0.5, Vector2(-520.0, -310.0), Vector2(1040.0, 150.0))
	_place(_title, _label("Hay una bomba en tu coche. Si bajas de la mínima, explota. Y ÉL te sigue.", 27, Color(1.0, 0.55, 0.45)),
			0.5, 0.5, Vector2(-560.0, -160.0), Vector2(1120.0, 36.0))
	var controls := "W / ↑  acelerar      A D / ← →  girar      S / ↓  frenar (¡cuidado!)\nESPACIO  derrapar (suéltalo para el turbo)      SHIFT  nitro\nC  cámara dentro / fuera      T  tienda      R  reiniciar      ESC  salir"
	_place(_title, _label(controls, 21, PALE), 0.5, 0.5, Vector2(-560.0, 205.0), Vector2(1120.0, 100.0))
	_title_prompt = _label("Pulsa ACELERAR para arrancar", 34, RED)
	_place(_title, _title_prompt, 0.5, 0.5, Vector2(-520.0, 150.0), Vector2(1040.0, 44.0))
	_title_record = _label("", 22, Color(1.0, 1.0, 1.0, 0.6))
	_place(_title, _title_record, 0.5, 0.0, Vector2(-520.0, 14.0), Vector2(1040.0, 30.0))


func _build_game_over() -> void:
	_over = _layer()
	_over.visible = false
	_over.add_child(_full_rect(Color(0.0, 0.0, 0.0, 0.5)))
	_over_title = _label("¡BOOM!", 130, RED)
	_place(_over, _over_title, 0.5, 0.5, Vector2(-620.0, -300.0), Vector2(1240.0, 160.0))
	_over_stats = _label("", 30, Color.WHITE)
	_place(_over, _over_stats, 0.5, 0.5, Vector2(-520.0, -130.0), Vector2(1040.0, 250.0))
	_over_prompt = _label("R / ENTER  volver a intentarlo        T  tienda", 28, PALE)
	_place(_over, _over_prompt, 0.5, 0.5, Vector2(-520.0, 160.0), Vector2(1040.0, 40.0))


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.001
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	back.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", back)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _full_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _label(text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var settings := LabelSettings.new()
	settings.font = _font
	settings.font_size = font_size
	settings.font_color = color
	settings.outline_size = maxi(4, int(font_size / 6.0))
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	var label := Label.new()
	label.text = text
	label.label_settings = settings
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Coloca un control con tamaño fijo `sz`, a `pos` píxeles del punto de la
## pantalla (o del padre) indicado por ax/ay: 0 = izquierda/arriba, 0.5 = centro,
## 1 = derecha/abajo.
func _place(parent: Control, c: Control, ax: float, ay: float, pos: Vector2, sz: Vector2) -> void:
	parent.add_child(c)
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


## 12450 -> "12 450"
func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out
