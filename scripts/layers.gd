class_name Layers
## Capas de física (cada una es un bit). Tienen los mismos nombres en
## Proyecto > Configuración del proyecto > Nombres de capas > Física 3D.

const WORLD := 1    # capa 1: edificios y cosas que no se mueven
const PLAYER := 2   # capa 2: el coche del jugador
const PROPS := 4    # capa 3: tráfico y objetos que salen volando al golpearlos
const GROUND := 8   # capa 4: el suelo (solo lo usan los restos que salen volando)
const DEBRIS := 16  # capa 5: restos que ya han salido volando
