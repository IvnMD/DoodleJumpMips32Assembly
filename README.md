# 🕹️ MIPS Jumper

> Clon de Doodle Jump escrito íntegramente en **MIPS32 Assembly**.  
> Gráficos en tiempo real con el Bitmap Display de MARS · Física de gravedad · Scroll infinito · Input de teclado por MMIO.

---

## Demo

<!-- Sustituye esta línea por tu GIF grabado con MARS -->
![MIPS Jumper gameplay](docs/gameplay.gif)

> 💡 **Cómo grabar el GIF:** usa [ScreenToGif](https://www.screentogif.com/) (Windows) o [Peek](https://github.com/phw/peek) (Linux) mientras juegas en MARS. Súbelo a `docs/gameplay.gif`.

---

## Descripción

Un cuadrado de 3×3 píxeles lógicos cae por gravedad y **rebota automáticamente** al aterrizar en cualquier plataforma. Las plataformas descienden continuamente simulando la cámara que sigue al jugador hacia arriba. Cuando el personaje cae al vacío: **Game Over**.

Cada plataforma que sale por el borde inferior y reaparece por la parte superior suma **+1 punto**, visible en tiempo real en el panel *Run I/O* de MARS.

---

## Características técnicas

| Feature | Implementación |
|---|---|
| Gráficos | Bitmap Display de MARS (64×64 unidades, 8px/unidad) |
| Input | Keyboard and Display MMIO Simulator (polling) |
| Física | Gravedad acumulativa + clamp de velocidad máxima |
| Colisiones | AABB (Axis-Aligned Bounding Box) con margen de tolerancia |
| Scroll | Trigger superior: si `player_y < 20` → desplazar todo |
| Aleatorio | LCG (Linear Congruential Generator) para spawn de plataformas |
| Timing | `syscall 32` (sleep) → ~30 FPS |

---

## Configuración de MARS (⚠️ leer antes de ejecutar)

### 1. Bitmap Display

```
Tools → Bitmap Display → Connect to MIPS
  Unit Width  : 8
  Unit Height : 8
  Display Width  : 512
  Display Height : 512
  Base Address : 0x10008000 ($gp)
```

### 2. Teclado MMIO

```
Tools → Keyboard and Display MMIO Simulator → Connect to MIPS
```

> ⚠️ Haz **clic en el área de texto** del MMIO Keyboard para que reciba el foco del teclado antes de jugar.

### 3. Ejecutar

```
F3  →  Ensamblar
F5  →  Ejecutar
```

---

## Controles

| Tecla | Acción |
|---|---|
| `A` / `a` | Mover izquierda |
| `D` / `d` | Mover derecha |
| *(automático)* | Rebota al tocar plataforma |

El personaje hace **wrapping horizontal**: sale por el borde derecho y aparece por el izquierdo y viceversa.

---

## Paleta de colores

| Elemento | Hex | Vista |
|---|---|---|
| Fondo | `0x0D1B2A` | Azul marino oscuro |
| Jugador | `0xFF2D9B` | Rosa neón |
| Ojo | `0xFFFFFF` | Blanco |
| Plataforma (par) | `0x00FF88` | Verde neón |
| Plataforma (impar) | `0x00CCFF` | Cyan eléctrico |
| Borde plataforma | `0x004433` | Verde oscuro (efecto 3D) |
| Game Over | `0x1A0000` | Rojo muy oscuro |

---

## Arquitectura del código

### Sistema de coordenadas

```
(0,0) ──────────────────► X  (63)
  │   Grid lógico: 64 × 64 celdas
  │   Cada celda = 8×8 píxeles reales
  │
  ▼
  Y (63)

addr_celda = BASE + (fila × 64 + columna) × 4
```

### Tabla de registros principales

| Registro | Rol en el juego |
|---|---|
| `$s0` | Índice de bucle (`i`) en `draw_platforms`, `check_collisions`, `check_scroll` |
| `$s1` | `y_end` en `draw_rect` (límite de filas a pintar) |
| `$s2` | Ancho (`w`) en `draw_rect` |
| `$s3` | Alto (`h`) en `draw_rect` |
| `$s4` | `x` inicial guardado en `draw_rect` |
| `$t8` | Color activo (parámetro implícito de `draw_rect`) |
| `$t9` | Copia de `vel_y` en `check_collisions` |
| `$ra` | Siempre guardado en stack antes de cualquier `jal` interno |

### Subrutinas

```
main
├── clear_screen          Rellena 64×64 celdas con color de fondo (O(n))
├── read_keyboard         Polling MMIO → mueve player_x
├── apply_physics         vel_y += gravity; player_y += vel_y
├── check_collisions      AABB contra cada plataforma → rebote si colisión
├── check_scroll          Scroll cámara + respawn de plataformas + score
├── check_death           player_y ≥ 64 → game_over = 1
├── draw_platforms        Dibuja las 6 plataformas con color alterno
├── draw_player           Cuerpo 3×3 + ojo 1×1
├── draw_rect             Primitiva base: rectángulo relleno con clipping
├── rand_x                LCG → X aleatoria en [0, 53]
└── print_score           Imprime score en Run I/O
```

### Flujo del game loop

```
┌─────────────────────────────┐
│         GAME LOOP           │
├─────────────────────────────┤
│  1. check game_over flag    │
│  2. clear_screen (fondo)    │
│  3. read_keyboard (MMIO)    │
│  4. apply_physics (gravedad)│
│  5. check_collisions (AABB) │
│  6. check_scroll (cámara)   │
│  7. check_death             │
│  8. draw_platforms          │
│  9. draw_player             │
│ 10. sleep(33ms) → ~30 FPS  │
└─────────────────────────────┘
```

---

## Variables del juego (`.data`)

| Variable | Tipo | Descripción |
|---|---|---|
| `player_x` | `.word` | Columna actual del jugador [0, 63] |
| `player_y` | `.word` | Fila actual del jugador [0, 63] |
| `vel_y` | `.word` | Velocidad vertical (negativo = sube) |
| `plat_x` | `.word ×6` | Coordenadas X de las 6 plataformas |
| `plat_y` | `.word ×6` | Coordenadas Y de las 6 plataformas |
| `score` | `.word` | Puntuación acumulada |
| `game_over` | `.word` | Flag: `0` = jugando, `1` = fin |
| `rand_seed` | `.word` | Semilla del generador pseudoaleatorio |

---

## Constantes de física

| Constante | Valor | Efecto |
|---|---|---|
| `GRAVITY` | `1` | Aceleración por frame |
| `JUMP_VEL` | `-14` | Impulso al rebotar (hacia arriba) |
| `MAX_FALL_VEL` | `16` | Velocidad máxima de caída |
| `MOVE_SPEED` | `3` | Píxeles por pulsación de tecla |
| `SCROLL_TRIGGER` | `20` | Y mínima antes de activar scroll |
| `SCROLL_AMT` | `2` | Unidades de desplazamiento por frame |

---

## Mejoras posibles

- [ ] Plataformas móviles (traslación horizontal)
- [ ] Plataformas frágiles (desaparecen tras el primer rebote)
- [ ] Sprite 8×8 más detallado para el jugador
- [ ] Efecto de partículas al rebotar (píxeles durante 3 frames)
- [ ] Dificultad progresiva (plataformas más separadas con el score)
- [ ] Música: tono generado por syscall de audio de MARS

---

## Contexto académico

Proyecto desarrollado como parte del **Grado Superior DAM** en el IES Puerto de la Cruz, Tenerife.  
El objetivo era demostrar comprensión práctica de:
- Gestión directa de memoria mapeada (MMIO)
- Aritmética de punteros para acceso al framebuffer
- Convención de llamada MIPS (stack, `$ra`, `$s0-$s7`)
- Bucles de juego con timing controlado

---

## Autor

**Iván Mesa Domínguez**  
[github.com/IvnMD](https://github.com/IvnMD) · [LinkedIn](https://www.linkedin.com/in/ivanmesadominguez/)

*Estudiante DAM · 15 años de experiencia comercial convertida en código.*
