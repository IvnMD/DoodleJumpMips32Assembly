##########################################################################
#
#   ███╗   ███╗██╗██████╗ ███████╗     ██╗██╗   ██╗███╗   ███╗██████╗
#   ████╗ ████║██║██╔══██╗██╔════╝     ██║██║   ██║████╗ ████║██╔══██╗
#   ██╔████╔██║██║██████╔╝███████╗     ██║██║   ██║██╔████╔██║██████╔╝
#   ██║╚██╔╝██║██║██╔═══╝ ╚════██║██   ██║██║   ██║██║╚██╔╝██║██╔═══╝
#   ██║ ╚═╝ ██║██║██║     ███████║╚█████╔╝╚██████╔╝██║ ╚═╝ ██║██║
#   ╚═╝     ╚═╝╚═╝╚═╝     ╚══════╝ ╚════╝  ╚═════╝ ╚═╝     ╚═╝╚═╝
#
#   Doodle Jump Clone en MIPS32 Assembly  |  v1.0
#   Autor  : Iván Mesa Domínguez
#   GitHub : github.com/IvnMD
#
##########################################################################
#
#   CONFIGURACIÓN DE MARS (leer antes de ejecutar)
#   ──────────────────────────────────────────────
#   1. Tools → Bitmap Display
#        Unit Width  : 8        Unit Height : 8
#        Display W   : 512      Display H   : 512
#        Base Address: 0x10008000 ($gp)
#      → Pulsa "Connect to MIPS"
#
#   2. Tools → Keyboard and Display MMIO Simulator
#      → Pulsa "Connect to MIPS"
#
#   3. Ensambla (F3) y ejecuta (F5)
#   4. Haz clic en el área de texto del MMIO Keyboard
#      para que reciba el foco, luego teclea A/D
#
#   CONTROLES
#   ──────────
#   A   → Mover izquierda
#   D   → Mover derecha
#   (El jugador rebota automáticamente en las plataformas)
#
#   OBJETIVO
#   ─────────
#   Mantente en pie el mayor tiempo posible.
#   Cada plataforma que sale por abajo de la pantalla = +1 punto.
#   Si caes al vacío… GAME OVER.
#
##########################################################################
#
#   ARQUITECTURA DEL JUEGO
#   ──────────────────────
#   Grid lógico : 64 × 64 unidades  (512px / 8px por unidad)
#   Sistema de coordenadas: (0,0) = esquina superior-izquierda
#   Y positivo   → hacia abajo
#
#   Cálculo de dirección de una celda (col, row):
#   addr = DISPLAY_BASE + (row * COLS + col) * 4
#
#   TABLA DE REGISTROS GUARDADOS (por subroutine)
#   ──────────────────────────────────────────────
#   $s0  → Índice de bucle en draw_platforms / check_scroll
#   $s1  → Valor y_end en draw_rect
#   $s2  → Ancho  en draw_rect
#   $s3  → Alto   en draw_rect
#   $s4  → Copia de x inicio en draw_rect
#   $ra  → Siempre preservado en subrutinas con jal interno
#
#   PARÁMETROS DE draw_rect
#   ─────────────────────────
#   $a0 = x (columna inicial)    $a2 = w (ancho)
#   $a1 = y (fila inicial)       $a3 = h (alto)
#   $t8 = color (0x00RRGGBB)
#
##########################################################################

# ══════════════════════════════════════════════════════
#   CONSTANTES DE DISPLAY
# ══════════════════════════════════════════════════════
.eqv  DISPLAY_BASE   0x10008000   # Dirección base del Bitmap Display
.eqv  COLS           64            # Columnas (512 / 8)
.eqv  ROWS           64            # Filas    (512 / 8)
.eqv  TOTAL_CELLS    4096          # COLS * ROWS

# ══════════════════════════════════════════════════════
#   PALETA DE COLORES  (formato 0x00RRGGBB)
# ══════════════════════════════════════════════════════
.eqv  C_BG           0x0D1B2A     # Fondo:      azul marino oscuro
.eqv  C_PLAYER       0xFF2D9B     # Jugador:    rosa neón (synthwave)
.eqv  C_EYE         0xFFFFFF     # Ojo jugador: blanco
.eqv  C_PLAT_A       0x00FF88     # Plataforma par:   verde neón
.eqv  C_PLAT_B       0x00CCFF     # Plataforma impar: cyan
.eqv  C_PLAT_EDGE    0x004433     # Borde superior de plataforma
.eqv  C_GAMEOVER     0x1A0000     # Fondo rojo oscuro (pantalla game over)
.eqv  C_GRID         0x0F1E2E     # Color líneas de cuadrícula (decoración)

# ══════════════════════════════════════════════════════
#   FÍSICA
# ══════════════════════════════════════════════════════
.eqv  GRAVITY        1             # Aceleracion gravitacional (unidades/frame2)
.eqv  JUMP_VEL       -14           # Impulso al rebotar (negativo = sube)
.eqv  MAX_FALL_VEL   16            # Velocidad máxima de caída
.eqv  MOVE_SPEED     3             # Desplazamiento horizontal por tecla

# ══════════════════════════════════════════════════════
#   DIMENSIONES DE ENTIDADES
# ══════════════════════════════════════════════════════
.eqv  PL_W           3             # Ancho del jugador  (unidades)
.eqv  PL_H           3             # Alto  del jugador
.eqv  PT_W           10            # Ancho de plataforma
.eqv  PT_H           2             # Alto  de plataforma
.eqv  NUM_PLATS      6             # Número de plataformas simultáneas

# ══════════════════════════════════════════════════════
#   SISTEMA DE SCROLL (cámara)
# ══════════════════════════════════════════════════════
.eqv  SCROLL_TRIGGER 20            # Si jugador_y < este valor → scroll
.eqv  SCROLL_AMT     2             # Unidades de scroll por frame

# ══════════════════════════════════════════════════════
#   MMIO TECLADO (Keyboard and Display MMIO Simulator)
# ══════════════════════════════════════════════════════
.eqv  KBD_CTRL       0xFFFF0000   # Registro de control (bit0 = tecla lista)
.eqv  KBD_DATA       0xFFFF0004   # Registro de datos   (ASCII de la tecla)
.eqv  KEY_a          0x61
.eqv  KEY_d          0x64
.eqv  KEY_A          0x41
.eqv  KEY_D          0x44

# ══════════════════════════════════════════════════════
#   FRAME TIMING
# ══════════════════════════════════════════════════════
.eqv  FRAME_MS       80            # ~12 FPS — mas controlable en MARS

# ══════════════════════════════════════════════════════
#   SYSCALLS
# ══════════════════════════════════════════════════════
.eqv  SYS_PRINT_INT  1
.eqv  SYS_PRINT_STR  4
.eqv  SYS_SLEEP      32
.eqv  SYS_EXIT       10

##########################################################################
#   .data  —  Variables y strings
##########################################################################
.data

# ── Estado del jugador ──────────────────────────────────────────────────
player_x:    .word 30              # Columna inicial
player_y:    .word 46              # Fila inicial (sobre la plataforma 0)
vel_y:       .word 0               # Velocidad vertical actual

# ── Plataformas (arrays paralelos de longitud NUM_PLATS) ────────────────
# Distribuidas uniformemente en vertical al inicio
plat_x:  .word  4, 22, 38, 52,  9, 43
plat_y:  .word 50, 42, 34, 26, 18, 10

# ── Estado del juego ────────────────────────────────────────────────────
score:       .word 0               # Puntuación actual
game_over:   .word 0               # Flag: 0 = jugando, 1 = fin de juego
rand_seed:   .word 0x00A3F1B7      # Semilla para generador pseudoaleatorio

# ── Strings de consola ──────────────────────────────────────────────────
s_init:      .asciiz "╔══════════════════════════════╗\n║      MIPS JUMPER v1.0        ║\n║  github.com/IvnMD            ║\n╚══════════════════════════════╝\nControles: A = izquierda  D = derecha\nHaz clic en el MMIO Keyboard primero!\n──────────────────────────────────────\n"
s_score_lbl: .asciiz "Puntuacion: "
s_nl:        .asciiz "\n"
s_gameover:  .asciiz "\n╔══════════════════════════╗\n║       GAME  OVER!        ║\n╚══════════════════════════╝\nScore final: "
s_restart:   .asciiz "\nReinicia la simulacion para volver a jugar.\n"

##########################################################################
#   .text  —  Código
##########################################################################
.text

##########################################################################
#   main  —  Punto de entrada
##########################################################################
main:
    # Mensaje de bienvenida en consola
    li    $v0, SYS_PRINT_STR
    la    $a0, s_init
    syscall

    # Colocar al jugador justo sobre la primera plataforma
    # plat_y[0] = 50 → jugador_y = 50 - PL_H = 47
    li    $t0, 47
    sw    $t0, player_y

    # Mostrar puntuación inicial
    jal   print_score

# ══════════════════════════════════════════════════════════════════════
#   GAME LOOP PRINCIPAL
# ══════════════════════════════════════════════════════════════════════
game_loop:
    # ── 0. Comprobar flag de fin ──────────────────────────────────────
    lw    $t0, game_over
    bne   $t0, $zero, game_over_screen

    # ── 1. Borrar pantalla ────────────────────────────────────────────
    jal   clear_screen

    # ── 2. Leer input de teclado ──────────────────────────────────────
    jal   read_keyboard

    # ── 3. Aplicar física (gravedad + posición Y) ─────────────────────
    jal   apply_physics

    # ── 4. Detección de colisiones con plataformas ────────────────────
    jal   check_collisions

    # ── 5. Scroll de cámara ───────────────────────────────────────────
    jal   check_scroll

    # ── 6. Comprobar muerte (caída por el borde inferior) ────────────
    jal   check_death

    # ── 7. Renderizado ────────────────────────────────────────────────
    jal   draw_platforms
    jal   draw_player

    # ── 8. Control de velocidad ───────────────────────────────────────
    # Doble mecanismo: busy-wait + syscall sleep
    # Si va demasiado rapido: sube el li $t0 a 500000 o 800000
    # Si va demasiado lento:  bajalo a  100000 o  50000
    li    $t0, 300000              # iteraciones de espera activa
busy_wait:
    addi  $t0, $t0, -1
    bgtz  $t0, busy_wait

    li    $v0, SYS_SLEEP           # syscall 32 como respaldo
    li    $a0, FRAME_MS
    syscall

    j     game_loop

# ══════════════════════════════════════════════════════════════════════
#   GAME OVER SCREEN
# ══════════════════════════════════════════════════════════════════════
game_over_screen:
    # Pintar pantalla con rojo oscuro
    li    $a0, 0
    li    $a1, 0
    li    $a2, COLS
    li    $a3, ROWS
    li    $t8, C_GAMEOVER
    jal   draw_rect

    # Mensaje en consola
    li    $v0, SYS_PRINT_STR
    la    $a0, s_gameover
    syscall
    lw    $a0, score
    li    $v0, SYS_PRINT_INT
    syscall
    li    $v0, SYS_PRINT_STR
    la    $a0, s_restart
    syscall

    li    $v0, SYS_EXIT
    syscall


##########################################################################
#   clear_screen
#   ────────────
#   Rellena las 64×64 celdas del Bitmap Display con el color de fondo.
#   Complejidad: O(COLS*ROWS) escrituras de 4 bytes.
#   No destruye registros guardados.
##########################################################################
clear_screen:
    li    $t0, 0                   # contador (0 .. TOTAL_CELLS-1)
    li    $t1, TOTAL_CELLS
    li    $t2, DISPLAY_BASE
    li    $t3, C_BG

clr_loop:
    beq   $t0, $t1, clr_ret
    sw    $t3, 0($t2)
    addi  $t0, $t0, 1
    addi  $t2, $t2, 4
    j     clr_loop

clr_ret:
    jr    $ra


##########################################################################
#   draw_rect
#   ─────────
#   Dibuja un rectángulo relleno en el Bitmap Display.
#
#   Parámetros:
#     $a0 = x   (columna inicial, unidades)
#     $a1 = y   (fila inicial,    unidades)
#     $a2 = w   (ancho,           unidades)
#     $a3 = h   (alto,            unidades)
#     $t8 = color (0x00RRGGBB)
#
#   Preserva: $s0-$s4, $ra
#   Complejidad: O(w * h)
##########################################################################
draw_rect:
    # Guardar registros en el stack
    addi  $sp, $sp, -24
    sw    $ra,  0($sp)
    sw    $s0,  4($sp)
    sw    $s1,  8($sp)
    sw    $s2, 12($sp)
    sw    $s3, 16($sp)
    sw    $s4, 20($sp)

    move  $s0, $a0                 # $s0 = x inicio
    move  $s1, $a1                 # $s1 = y actual (fila)
    move  $s2, $a2                 # $s2 = ancho
    move  $s3, $a3                 # $s3 = alto
    add   $s4, $s1, $s3            # $s4 = y_end = y + h

dr_row:
    bge   $s1, $s4, dr_ret         # fila >= y_end → terminado

    # Calcular dirección base de esta fila:
    # addr_fila = BASE + fila * COLS * 4
    li    $t0, DISPLAY_BASE
    li    $t1, COLS
    mul   $t2, $s1, $t1            # fila * COLS
    sll   $t2, $t2, 2              # * 4 bytes
    add   $t0, $t0, $t2            # addr_fila
    # Añadir offset de columna inicial
    sll   $t2, $s0, 2              # x * 4
    add   $t0, $t0, $t2            # $t0 = dirección celda (s0, s1)

    add   $t2, $s0, $s2            # x_end = x + w
    move  $t3, $s0                 # columna actual = x

dr_col:
    bge   $t3, $t2, dr_next_row    # col >= x_end → siguiente fila

    # Comprobación de límites (permite clipping en bordes de pantalla)
    blt   $t3, 0,    dr_skip
    bge   $t3, COLS, dr_skip
    blt   $s1, 0,    dr_skip
    bge   $s1, ROWS, dr_skip
    sw    $t8, 0($t0)              # ← pintar celda

dr_skip:
    addi  $t0, $t0, 4              # avanzar puntero
    addi  $t3, $t3, 1              # siguiente columna
    j     dr_col

dr_next_row:
    addi  $s1, $s1, 1              # siguiente fila
    j     dr_row

dr_ret:
    lw    $ra,  0($sp)
    lw    $s0,  4($sp)
    lw    $s1,  8($sp)
    lw    $s2, 12($sp)
    lw    $s3, 16($sp)
    lw    $s4, 20($sp)
    addi  $sp, $sp, 24
    jr    $ra


##########################################################################
#   draw_platforms
#   ──────────────
#   Itera las NUM_PLATS plataformas y dibuja las que estén en pantalla.
#   Alterna color verde/cyan según índice par/impar.
#   Añade un borde superior más oscuro para efecto 3D.
##########################################################################
draw_platforms:
    addi  $sp, $sp, -8
    sw    $ra, 0($sp)
    sw    $s0, 4($sp)

    li    $s0, 0                   # i = 0

dp_loop:
    li    $t0, NUM_PLATS
    bge   $s0, $t0, dp_ret

    # Cargar plat_x[i] y plat_y[i]
    sll   $t1, $s0, 2              # offset = i * 4
    la    $t2, plat_x
    add   $t2, $t2, $t1
    lw    $a0, 0($t2)              # $a0 = px

    la    $t2, plat_y
    add   $t2, $t2, $t1
    lw    $a1, 0($t2)              # $a1 = py

    # Culling: no dibujar si está fuera de pantalla
    li    $t3, -PT_H
    blt   $a1, $t3, dp_next        # demasiado arriba
    bge   $a1, ROWS, dp_next       # demasiado abajo

    # ── Cuerpo de la plataforma ───────────────────────
    li    $a2, PT_W
    li    $a3, PT_H
    andi  $t3, $s0, 1              # par/impar
    beq   $t3, $zero, dp_green
    li    $t8, C_PLAT_B            # impar → cyan
    j     dp_draw_body
dp_green:
    li    $t8, C_PLAT_A            # par   → verde
dp_draw_body:
    jal   draw_rect

    # ── Borde superior (1px más oscuro = efecto 3D) ──────────────────
    sll   $t1, $s0, 2
    la    $t2, plat_x
    add   $t2, $t2, $t1
    lw    $a0, 0($t2)
    la    $t2, plat_y
    add   $t2, $t2, $t1
    lw    $a1, 0($t2)
    li    $a2, PT_W
    li    $a3, 1
    li    $t8, C_PLAT_EDGE
    jal   draw_rect

dp_next:
    addi  $s0, $s0, 1
    j     dp_loop

dp_ret:
    lw    $ra, 0($sp)
    lw    $s0, 4($sp)
    addi  $sp, $sp, 8
    jr    $ra


##########################################################################
#   draw_player
#   ───────────
#   Dibuja el jugador como un cuadrado rosa con un ojo blanco.
#   El "ojo" da personalidad al personaje y es visible por el zoom ×8.
##########################################################################
draw_player:
    addi  $sp, $sp, -4
    sw    $ra, 0($sp)

    # ── Cuerpo principal (3×3, rosa neón) ─────────────────────────────
    lw    $a0, player_x
    lw    $a1, player_y
    li    $a2, PL_W
    li    $a3, PL_H
    li    $t8, C_PLAYER
    jal   draw_rect

    # ── Ojo (1×1, blanco, en posición central-izquierda) ─────────────
    lw    $a0, player_x
    addi  $a0, $a0, 1              # centrado horizontalmente
    lw    $a1, player_y
    addi  $a1, $a1, 1              # a mitad de altura
    li    $a2, 1
    li    $a3, 1
    li    $t8, C_EYE
    jal   draw_rect

    lw    $ra, 0($sp)
    addi  $sp, $sp, 4
    jr    $ra


##########################################################################
#   read_keyboard
#   ─────────────
#   Consulta el registro de control MMIO (bit 0 = tecla disponible).
#   Si hay tecla y es 'a'/'A' → mover izquierda.
#   Si hay tecla y es 'd'/'D' → mover derecha.
#   Implementa wrapping en los bordes de pantalla.
##########################################################################
read_keyboard:
    # ── Comprobar si hay tecla lista ──────────────────────────────────
    li    $t0, KBD_CTRL
    lw    $t1, 0($t0)
    andi  $t1, $t1, 1              # bit 0: 1 = tecla disponible
    beq   $t1, $zero, rk_ret       # sin tecla → salir

    # ── Leer código ASCII ─────────────────────────────────────────────
    li    $t0, KBD_DATA
    lw    $t2, 0($t0)              # $t2 = tecla ASCII

    lw    $t3, player_x            # posición X actual

    beq   $t2, KEY_a, rk_left
    beq   $t2, KEY_A, rk_left
    beq   $t2, KEY_d, rk_right
    beq   $t2, KEY_D, rk_right
    j     rk_ret

rk_left:
    addi  $t3, $t3, -MOVE_SPEED
    # Wrapping izquierda: si x < 0 → aparecer por la derecha
    bge   $t3, 0, rk_save
    li    $t3, 61                  # COLS - PL_W
    j     rk_save

rk_right:
    addi  $t3, $t3, MOVE_SPEED
    # Wrapping derecha: si x > COLS-PL_W → aparecer por la izquierda
    li    $t4, 61
    ble   $t3, $t4, rk_save
    li    $t3, 0

rk_save:
    sw    $t3, player_x

rk_ret:
    jr    $ra


##########################################################################
#   apply_physics
#   ─────────────
#   Aplica gravedad (vel_y += GRAVITY) con clamp a MAX_FALL_VEL,
#   luego actualiza player_y += vel_y.
##########################################################################
apply_physics:
    lw    $t0, vel_y
    lw    $t1, player_y

    # vel_y += GRAVITY (1)
    addi  $t0, $t0, GRAVITY

    # Clamp: vel_y ≤ MAX_FALL_VEL
    li    $t2, MAX_FALL_VEL
    blt   $t0, $t2, ap_no_clamp
    move  $t0, $t2
ap_no_clamp:
    sw    $t0, vel_y

    # player_y += vel_y
    add   $t1, $t1, $t0
    sw    $t1, player_y

    jr    $ra


##########################################################################
#   check_collisions
#   ─────────────────
#   Solo actúa si el jugador está CAYENDO (vel_y > 0).
#
#   Para cada plataforma comprueba dos condiciones:
#     Vertical  : pie_jugador ∈ [py, py + PT_H + margen]
#     Horizontal: solapamiento en X entre jugador y plataforma
#
#   Si colisiona: vel_y = JUMP_VEL  (rebote automático)
#                 player_y ajustado justo encima de la plataforma
##########################################################################
check_collisions:
    addi  $sp, $sp, -8
    sw    $ra, 0($sp)
    sw    $s0, 4($sp)

    # Solo comprobar si está cayendo (vel_y > 0)
    lw    $t9, vel_y
    blez  $t9, cc_ret              # vel_y ≤ 0 → no puede aterrizar

    lw    $t0, player_x            # px jugador
    lw    $t1, player_y
    add   $t1, $t1, PL_H          # $t1 = pie del jugador (y + alto)

    li    $s0, 0                   # i = 0

cc_loop:
    li    $t3, NUM_PLATS
    bge   $s0, $t3, cc_ret

    sll   $t4, $s0, 2              # offset = i * 4

    # Cargar plataforma i
    la    $t5, plat_x
    add   $t5, $t5, $t4
    lw    $t6, 0($t5)              # $t6 = plat_x[i]

    la    $t5, plat_y
    add   $t5, $t5, $t4
    lw    $t7, 0($t5)              # $t7 = plat_y[i]

    # ─ Test vertical ──────────────────────────────────────────────────
    # El pie del jugador debe estar en [plat_y, plat_y + PT_H + 2]
    blt   $t1, $t7, cc_miss        # pie por encima de la plataforma
    addi  $t8, $t7, PT_H
    addi  $t8, $t8, 2              # pequeño margen de tolerancia
    bgt   $t1, $t8, cc_miss        # pie demasiado profundo (atravesó)

    # ─ Test horizontal ────────────────────────────────────────────────
    # jugador_x + PL_W > plat_x  Y  jugador_x < plat_x + PT_W
    add   $t8, $t0, PL_W
    ble   $t8, $t6, cc_miss        # jugador completamente a la izquierda
    add   $t8, $t6, PT_W
    bge   $t0, $t8, cc_miss        # jugador completamente a la derecha

    # ── ¡Colisión detectada! ──────────────────────────────────────────
    # Velocidad de rebote
    li    $t8, JUMP_VEL
    sw    $t8, vel_y

    # Ajustar posición Y exacta (evitar jitter visual)
    sub   $t8, $t7, PL_H          # player_y = plat_y - PL_H
    sw    $t8, player_y

cc_miss:
    addi  $s0, $s0, 1
    j     cc_loop

cc_ret:
    lw    $ra, 0($sp)
    lw    $s0, 4($sp)
    addi  $sp, $sp, 8
    jr    $ra


##########################################################################
#   check_scroll
#   ────────────
#   Si el jugador está por encima del SCROLL_TRIGGER (y < 20):
#     1. Desplaza todas las plataformas HACIA ABAJO en SCROLL_AMT unidades
#     2. Mueve al jugador hacia abajo en SCROLL_AMT (efecto cámara)
#     3. Si alguna plataforma sale por abajo (y ≥ ROWS):
#          → Reaparece en la parte superior con X aleatoria
#          → Incrementa la puntuación
##########################################################################
check_scroll:
    addi  $sp, $sp, -8
    sw    $ra, 0($sp)
    sw    $s0, 4($sp)

    # Solo scrollear si el jugador está en la zona superior
    lw    $t0, player_y
    li    $t1, SCROLL_TRIGGER
    bge   $t0, $t1, cs_ret         # jugador por debajo del trigger

    # ── Mover todas las plataformas hacia abajo ───────────────────────
    li    $s0, 0

cs_loop:
    li    $t0, NUM_PLATS
    bge   $s0, $t0, cs_move_player

    sll   $t1, $s0, 2
    la    $t2, plat_y
    add   $t2, $t2, $t1
    lw    $t3, 0($t2)

    addi  $t3, $t3, SCROLL_AMT    # bajar plataforma
    sw    $t3, 0($t2)

    # ── Respawn si sale por el borde inferior ─────────────────────────
    blt   $t3, ROWS, cs_no_respawn

    # Nueva Y: fuera de pantalla por arriba → aparecerá deslizándose
    li    $t3, -2
    sw    $t3, 0($t2)

    # Nueva X pseudoaleatoria
    la    $t2, plat_x
    add   $t2, $t2, $t1
    jal   rand_x                   # retorna en $v0
    sw    $v0, 0($t2)

    # Incrementar y mostrar puntuación
    lw    $t4, score
    addi  $t4, $t4, 1
    sw    $t4, score
    jal   print_score

cs_no_respawn:
    addi  $s0, $s0, 1
    j     cs_loop

cs_move_player:
    # Desplazar al jugador con el scroll para mantener ilusión de cámara
    lw    $t0, player_y
    addi  $t0, $t0, SCROLL_AMT
    sw    $t0, player_y

cs_ret:
    lw    $ra, 0($sp)
    lw    $s0, 4($sp)
    addi  $sp, $sp, 8
    jr    $ra


##########################################################################
#   check_death
#   ───────────
#   Si player_y ≥ ROWS (cayó por el borde inferior) → game_over = 1
##########################################################################
check_death:
    lw    $t0, player_y
    li    $t1, ROWS
    blt   $t0, $t1, cd_ret        # todavía en pantalla → seguir jugando

    li    $t0, 1
    sw    $t0, game_over           # ← activar flag de game over

cd_ret:
    jr    $ra


##########################################################################
#   rand_x
#   ───────
#   Generador pseudoaleatorio LCG (Linear Congruential Generator):
#   seed = seed * 1664525 + 1013904223   (parámetros de Numerical Recipes)
#
#   Retorna: $v0 ∈ [0, COLS - PT_W - 1]  (= [0, 53])
#   Usa: $t0, $t1  (no preserva)
##########################################################################
rand_x:
    lw    $t0, rand_seed

    # seed = seed * 1664525
    li    $t1, 1664525
    mult  $t0, $t1
    mflo  $t0                      # guardar 32 bits bajos

    # seed = seed + 1013904223
    li    $t1, 1013904223
    add   $t0, $t0, $t1
    sw    $t0, rand_seed

    # Extraer bits medios (más aleatorios) y mapear al rango [0, 53]
    srl   $t0, $t0, 7              # desplazar para evitar bits de baja entropía
    andi  $t0, $t0, 0x7F           # máscara a 7 bits (0-127)
    li    $t1, 54                  # COLS - PT_W = 64 - 10
    rem   $v0, $t0, $t1            # resultado en [0, 53]

    jr    $ra


##########################################################################
#   print_score
#   ───────────
#   Muestra la puntuación actual en el panel Run I/O de MARS.
##########################################################################
print_score:
    li    $v0, SYS_PRINT_STR
    la    $a0, s_score_lbl
    syscall
    lw    $a0, score
    li    $v0, SYS_PRINT_INT
    syscall
    li    $v0, SYS_PRINT_STR
    la    $a0, s_nl
    syscall
    jr    $ra

##########################################################################
#   END OF FILE
#   ─────────────────────────────────────────────────────────────────────
#   Posibles mejoras futuras (contribuciones bienvenidas):
#
#   [ ] Plataformas móviles (traslación horizontal)
#   [ ] Plataformas frágiles (desaparecen tras el primer rebote)
#   [ ] Sprite más elaborado para el jugador (8×8)
#   [ ] Efectos de partículas al rebotar (píxeles amarillos ×3 frames)
#   [ ] High score persistente (entre ejecuciones)
#   [ ] Incremento de dificultad (plataformas más separadas con el tiempo)
#   [ ] Música: tono generado por syscall de audio de MARS
##########################################################################
