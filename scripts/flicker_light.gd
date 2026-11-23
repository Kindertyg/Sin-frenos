class_name FlickerLight
extends OmniLight3D
## Farola estropeada: se enciende y se apaga a ratos irregulares.

var base_energy := 3.0
var _wait := 0.0
var _on := true


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_on = not _on
	# Encendida aguanta un rato; apagada vuelve enseguida.
	_wait = randf_range(0.1, 1.4) if _on else randf_range(0.03, 0.2)
	light_energy = (base_energy if _on else base_energy * 0.06) * City.power
