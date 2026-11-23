class_name Upgrades
## Las mejoras de la tienda y la "chatarra" (el dinero del juego).
## Todo se guarda en el mismo archivo que el récord (user://sin_freno.cfg).
##
## Para añadir una mejora nueva: ponla en LIST y luego úsala en main.gd con
## Upgrades.level("su_id").

const SAVE_PATH := "user://sin_freno.cfg"
## Cuántos puntos hacen falta para ganar 1 de chatarra.
const POINTS_PER_SCRAP := 50.0

## id, nombre, descripción (con %s para el efecto de cada nivel), precios por
## nivel (cuantos precios, tantos niveles) y el efecto de cada nivel.
const LIST: Array[Dictionary] = [
	{"id": "armor", "name": "Blindaje",
	 "desc": "Aguantas %s sin perder velocidad (por partida).",
	 "costs": [120, 300, 600], "effects": ["1 choque", "2 choques", "3 choques"]},
	{"id": "fuse", "name": "Mecha larga",
	 "desc": "La bomba tarda %s más en explotar cuando bajas de la mínima.",
	 "costs": [100, 250, 500], "effects": ["0,4 s", "0,8 s", "1,2 s"]},
	{"id": "tank", "name": "Depósito de nitro",
	 "desc": "El nitro dura %s más y empiezas con más.",
	 "costs": [100, 250, 500], "effects": ["un 15 %", "un 30 %", "un 45 %"]},
	{"id": "engine", "name": "Motor trucado",
	 "desc": "Aceleras %s más y la velocidad máxima sube.",
	 "costs": [150, 350, 700], "effects": ["un 8 %", "un 16 %", "un 24 %"]},
	{"id": "lights", "name": "Faros de largo alcance",
	 "desc": "Ves %s más lejos, y en los apagones no te quedas del todo a oscuras.",
	 "costs": [200], "effects": ["mucho"]},
	{"id": "pulse", "name": "Pulso  [Q]",
	 "desc": "Habilidad: empuja a ÉL 60 m hacia atrás. Se recarga en %s.",
	 "costs": [250, 500], "effects": ["25 s", "15 s"]},
	{"id": "slowmo", "name": "Frenazo de pánico  [E]",
	 "desc": "Habilidad: el tiempo va lento 3 segundos. %s por partida.",
	 "costs": [300, 650], "effects": ["1 vez", "2 veces"]},
]

static var scrap := 0
static var levels := {}


static func load_data() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	scrap = int(cfg.get_value("tienda", "chatarra", 0))
	levels.clear()
	for u in LIST:
		levels[u["id"]] = int(cfg.get_value("tienda", u["id"], 0))


static func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)          # cargamos antes para no borrar el récord
	cfg.set_value("tienda", "chatarra", scrap)
	for id in levels:
		cfg.set_value("tienda", id, levels[id])
	cfg.save(SAVE_PATH)


static func level(id: String) -> int:
	return int(levels.get(id, 0))


static func info(id: String) -> Dictionary:
	for u in LIST:
		if u["id"] == id:
			return u
	return {}


static func max_level(id: String) -> int:
	return (info(id)["costs"] as Array).size()


## Precio del siguiente nivel (-1 si ya está al máximo).
static func next_cost(id: String) -> int:
	var lvl := level(id)
	if lvl >= max_level(id):
		return -1
	return int(info(id)["costs"][lvl])


## Intenta comprar el siguiente nivel. Devuelve true si se ha comprado.
static func buy(id: String) -> bool:
	var cost := next_cost(id)
	if cost < 0 or scrap < cost:
		return false
	scrap -= cost
	levels[id] = level(id) + 1
	save_data()
	return true


## Chatarra que da una partida con estos puntos.
static func scrap_for(score: float) -> int:
	return int(score / POINTS_PER_SCRAP)
