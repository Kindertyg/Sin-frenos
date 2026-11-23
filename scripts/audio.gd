class_name GameAudio
extends Node
## Todo el sonido del juego. Los sonidos los fabrica Sfx (no hay archivos).

## Velocidades (km/h) a las que "cambia de marcha" el sonido del motor.
const GEARS: Array[float] = [0.0, 50.0, 90.0, 135.0, 180.0, 300.0]

@export_range(-40.0, 6.0) var master_db := 0.0   ## volumen general

var _engine: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _nitro: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _beep: AudioStreamPlayer
var _crash: AudioStreamPlayer
var _boom: AudioStreamPlayer
var _thunder: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _static: AudioStreamPlayer
var _whoosh: AudioStreamPlayer
var _ding: AudioStreamPlayer
var _skid_level := 0.0
var _heart_wait := 1.0


func _ready() -> void:
	_engine = _player(Sfx.engine_loop(), -22.0, true)
	_skid = _player(Sfx.noise_loop("skid"), -60.0, true)
	_rain = _player(Sfx.noise_loop("rain"), -27.0, true)
	_nitro = _player(Sfx.noise_loop("nitro"), -60.0, true)
	_drone = _player(Sfx.drone_loop(), -40.0, true)
	_heart = _player(Sfx.heartbeat(), -10.0)
	_beep = _player(Sfx.beep(), -12.0)
	_crash = _player(Sfx.crash(), -6.0)
	_boom = _player(Sfx.explosion(), -1.0)
	_thunder = _player(Sfx.thunder(), -12.0)
	_sting = _player(Sfx.sting(), -5.0)
	_static = _player(Sfx.static_burst(), -14.0)
	_whoosh = _player(Sfx.whoosh(), -8.0)
	_ding = _player(Sfx.ding(), -14.0)


func _player(stream: AudioStream, db: float, autoplay := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db + master_db
	add_child(p)
	if autoplay:
		p.play()
	return p


## Motor: el tono sube dentro de cada marcha y cae al cambiar a la siguiente.
func update_engine(speed_kmh: float, throttle: float, boosting: bool, delta: float) -> void:
	var rpm := 1.0
	for i in GEARS.size() - 1:
		if speed_kmh < GEARS[i + 1]:
			rpm = (speed_kmh - GEARS[i]) / (GEARS[i + 1] - GEARS[i])
			break
	var pitch := 0.7 + rpm * 0.8 + speed_kmh / 400.0
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_engine.pitch_scale = lerpf(_engine.pitch_scale, pitch, k)
	var db := -22.0 + throttle * 6.0 + master_db
	_engine.volume_db = lerpf(_engine.volume_db, db, clampf(delta * 6.0, 0.0, 1.0))
	_nitro.volume_db = lerpf(_nitro.volume_db, (-14.0 if boosting else -60.0) + master_db, k)


## Chirrido de ruedas: `amount` de 0 (nada) a 1 (derrape fuerte).
func set_skid(amount: float, delta: float) -> void:
	_skid_level = lerpf(_skid_level, amount, clampf(delta * 10.0, 0.0, 1.0))
	_skid.volume_db = lerpf(-60.0, -16.0, sqrt(_skid_level)) + master_db
	_skid.pitch_scale = 0.9 + _skid_level * 0.25


## Miedo, de 0 a 1: sube el zumbido y el latido se acelera.
func set_fear(fear: float, delta: float) -> void:
	_drone.volume_db = lerpf(_drone.volume_db, lerpf(-34.0, -9.0, fear) + master_db, clampf(delta * 3.0, 0.0, 1.0))
	_drone.pitch_scale = 1.0 + fear * 0.12
	_heart_wait -= delta
	if fear > 0.15 and _heart_wait <= 0.0:
		_heart_wait = lerpf(1.1, 0.36, fear)     # de 55 a 165 pulsaciones
		_heart.volume_db = lerpf(-20.0, -4.0, fear) + master_db
		_heart.play()


## Pitido de la bomba. `urgency` de 0 (tranquilo) a 1 (a punto de explotar).
func beep(urgency: float) -> void:
	_beep.pitch_scale = 1.0 + urgency * 0.5
	_beep.volume_db = lerpf(-24.0, -6.0, urgency) + master_db
	_beep.play()


func crash(strength: float) -> void:
	_crash.pitch_scale = randf_range(0.85, 1.15)
	_crash.volume_db = lerpf(-18.0, -4.0, clampf(strength, 0.0, 1.0)) + master_db
	_crash.play()


func explosion() -> void:
	for p: AudioStreamPlayer in [_engine, _skid, _beep, _nitro, _heart]:
		p.stop()
	_boom.play()


func thunder() -> void:
	_thunder.pitch_scale = randf_range(0.8, 1.1)
	_thunder.play()


func sting() -> void:
	_sting.pitch_scale = randf_range(0.9, 1.1)
	_sting.play()


func radio_static() -> void:
	_static.pitch_scale = randf_range(0.8, 1.2)
	_static.play()


func whoosh() -> void:
	_whoosh.pitch_scale = randf_range(0.9, 1.3)
	_whoosh.play()


## "Ding" de puntos; más agudo cuanto más alto el combo.
func ding(combo: float) -> void:
	_ding.pitch_scale = 1.0 + minf(combo - 1.0, 4.0) * 0.08
	_ding.play()
