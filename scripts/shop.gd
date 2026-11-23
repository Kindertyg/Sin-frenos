class_name Shop
extends Control
## La tienda ("el taller"): una lista de mejoras que se compran con chatarra.
## Se maneja con flechas/W-S y ENTER, con el ratón o con el mando.
## ESC o T para salir.

signal closed(bought_something: bool)

const RED := Color(1.0, 0.22, 0.14)
const GOLD := Color(1.0, 0.8, 0.2)
const PALE := Color(0.86, 0.93, 1.0)
const GREY := Color(0.5, 0.5, 0.55)

var _font: Font
var _scrap_label: Label
var _desc_label: Label
var _msg_label: Label
var _buttons: Array[Button] = []
var _bought := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Impact", "Arial Black", "Arial"])
	font.font_weight = 700
	_font = font

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.035, 0.05, 0.95)
	style.border_color = Color(0.5, 0.08, 0.05)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(980.0, 0.0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	var title := _label("EL TALLER", 54, RED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_scrap_label = _label("", 36, GOLD)
	_scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_scrap_label)
	col.add_child(_label("«Paga y conduce. Él no espera.»", 22, Color(1.0, 0.55, 0.45)))

	for u in Upgrades.LIST:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0.0, 46.0)
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", PALE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _button_style(Color(0.08, 0.08, 0.1)))
		b.add_theme_stylebox_override("hover", _button_style(Color(0.2, 0.06, 0.05)))
		b.add_theme_stylebox_override("focus", _button_style(Color(0.35, 0.07, 0.05)))
		b.add_theme_stylebox_override("pressed", _button_style(Color(0.5, 0.1, 0.05)))
		var id: String = u["id"]
		b.pressed.connect(_on_buy.bind(id))
		b.focus_entered.connect(_show_desc.bind(id))
		b.mouse_entered.connect(b.grab_focus)
		col.add_child(b)
		_buttons.append(b)

	_desc_label = _label("", 22, PALE)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(0.0, 62.0)
	col.add_child(_desc_label)
	_msg_label = _label("", 24, GOLD)
	col.add_child(_msg_label)
	col.add_child(_label("ENTER  comprar      ESC / T  salir", 20, GREY))


func open() -> void:
	_bought = false
	_msg_label.text = ""
	_refresh()
	visible = true
	_buttons[0].grab_focus()


func close() -> void:
	visible = false
	closed.emit(_bought)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("shop"):
		get_viewport().set_input_as_handled()
		close()


func _refresh() -> void:
	_scrap_label.text = "CHATARRA  %d" % Upgrades.scrap
	for i in Upgrades.LIST.size():
		var id: String = Upgrades.LIST[i]["id"]
		var lvl := Upgrades.level(id)
		var top := Upgrades.max_level(id)
		var pips := "●".repeat(lvl) + "○".repeat(top - lvl)
		var cost := Upgrades.next_cost(id)
		var price := "MÁXIMO" if cost < 0 else "%d" % cost
		_buttons[i].text = "  %s   %s        %s" % [Upgrades.LIST[i]["name"], pips, price]
		var can := cost >= 0 and Upgrades.scrap >= cost
		_buttons[i].add_theme_color_override("font_color", PALE if can else GREY)


func _show_desc(id: String) -> void:
	var u := Upgrades.info(id)
	var lvl := Upgrades.level(id)
	var effects: Array = u["effects"]
	if lvl >= effects.size():
		_desc_label.text = (u["desc"] as String) % effects[effects.size() - 1] + "   (al máximo)"
	else:
		var text := (u["desc"] as String) % effects[lvl]
		if lvl > 0:
			text += "   (ahora: %s)" % effects[lvl - 1]
		_desc_label.text = text


func _on_buy(id: String) -> void:
	var cost := Upgrades.next_cost(id)
	if cost < 0:
		_msg_label.text = "Ya está al máximo."
	elif Upgrades.buy(id):
		_bought = true
		_msg_label.text = "Comprado: %s" % Upgrades.info(id)["name"]
	else:
		_msg_label.text = "Te faltan %d de chatarra." % (cost - Upgrades.scrap)
	_refresh()
	_show_desc(id)


func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	s.set_content_margin_all(8)
	return s


func _label(text: String, font_size: int, color: Color) -> Label:
	var settings := LabelSettings.new()
	settings.font = _font
	settings.font_size = font_size
	settings.font_color = color
	settings.outline_size = 4
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.85)
	var l := Label.new()
	l.text = text
	l.label_settings = settings
	return l
