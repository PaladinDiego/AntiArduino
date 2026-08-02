---
name: arduino-flash
description: Use when building, uploading, flashing, monitoring, or debugging
  Arduino, ESP32, ESP8266, STM32, or RP2040 firmware with PlatformIO on this
  machine. Also use when the user asks to "compilar", "subir el codigo",
  "flashear", "abrir el monitor serial", or reports upload, boot, port, or
  serial errors. Do not use for host-side code, web projects, or when the user
  only wants to read firmware source without building it.
---

# Arduino / ESP32 Flash & Monitor

Procedimiento determinista para este entorno. No redescubras nada: los hechos
de abajo están verificados en esta máquina.

## HECHOS VERIFICADOS DEL ENTORNO

| Elemento | Valor |
|---|---|
| SO / shell | Windows 11 AMD64, PowerShell 5.1 |
| Workspace embebido | `__WORKDIR__` |
| PlatformIO Core | `%USERPROFILE%\.platformio\penv\Scripts\pio.exe` |
| Python de PIO | `%USERPROFILE%\.platformio\penv\Scripts\python.exe` |
| IDE correcto | Antigravity IDE (`dataFolderName = .antigravity-ide`) |
| Extensiones | `%USERPROFILE%\.antigravity-ide\extensions` |
| Settings | `%APPDATA%\Antigravity IDE\User` |
| Scripts de esta skill | `__WORKDIR__\scripts\` |

**Usa SIEMPRE el Python de PIO**, no el del sistema. PIO Core 6.x no soporta
oficialmente Python 3.14.

**NUNCA escribas en `%APPDATA%\Antigravity\User`**: ese es el perfil del
binario standalone y es huérfano en esta máquina. Si dudas, compara el
`dataFolderName` de cada `product.json` antes de escribir.

## REGLAS CRÍTICAS

1. **Exclusividad del puerto COM.** En Windows solo un proceso puede abrir un
   COM. Antes de CUALQUIER build o upload, cierra el monitor con
   `stop_serial_monitor.ps1`. El plotter web y el monitor no coexisten.
   El síntoma de violar esto es `could not open port` o `Access is denied`,
   y **no** significa que la placa esté rota.

2. **Job Object bug de Antigravity.** La terminal integrada encierra la sesión
   en un Job Object con `kill-on-close`. Cualquier `Start-Process` lanzado
   desde ahí muere con la sesión. Por eso el monitor se lanza vía
   `schtasks` (`open_serial_monitor.ps1`), que entrega el proceso al
   Programador de Tareas, fuera del árbol del IDE.

3. **Encoding.** La terminal es cp1252. Los scripts `.ps1` y `.py` son
   ASCII-only. Nunca imprimas emoji: rompe con `UnicodeEncodeError`.
   Usa `[OK]`, `[FAIL]`, `[WARN]`.

4. **`--filter log2file` deshabilita `send_on_enter`.** Si lanzas el monitor en
   modo `Logged` o `Background`, cada tecla llega suelta al firmware. El código
   Arduino **debe** leer carácter por carácter (`Serial.read()` en un `while`
   hasta `\n`/`\r`). `Serial.readStringUntil()` corta las palabras por timeout.
   Snippet: `aserialbuffer`.

5. **`compile_commands.json` es POR ENTORNO.** Al cambiar de entorno, regenera
   con `pio run -e <env> -t compiledb`, o clangd mostrará errores fantasma con
   includes del toolchain anterior.

6. **`.cpp` antes que `.ino`.** El preprocesado de `.ino` falla con prototipos.
   Ante un error raro de prototipo: renombra a `.cpp` y agrega
   `#include <Arduino.h>`.

## SCRIPTS

| Script | Para qué |
|---|---|
| `preflight.ps1` | Valida PIO, lista entornos de `platformio.ini` y puertos COM |
| `flash_watch.ps1` | Ciclo completo: cerrar monitor, compilar, subir, reabrir |
| `open_serial_monitor.ps1` | Abre monitor vía schtasks (`-Mode Interactive/Logged/Background`) |
| `stop_serial_monitor.ps1` | Cierra el árbol de procesos y verifica que el COM quedó libre |
| `decode_backtrace.ps1` | Decodifica Guru Meditation Error con addr2line |
| `detect_board.py` | Puerto, VID:PID, chip, placa probable y driver necesario |

## ÁRBOL DE DECISIÓN

### 1. Preflight (siempre, en este orden)
```powershell
& "__WORKDIR__\scripts\preflight.ps1" -WorkDir <proyecto>
```
- Si `pio system info` falla, el PATH está roto: usa la ruta absoluta y avisa
  que hay que reiniciar la terminal.
- Lee `platformio.ini`. Si hay varios entornos y el usuario no dijo cuál,
  pregunta **una** vez y recuerda la elección toda la sesión.
- Si no hay puerto, **no** intentes subir. Reporta las causas en orden de
  probabilidad real:
  1. cable USB de solo carga, sin líneas de datos
  2. driver ausente (CP210x, CH340, FTDI)
  3. placa en modo boot o colgada

  **Nunca** sugieras fijar `upload_port` manualmente como solución a esto.

### 2. Compilar
```powershell
pio run -e <env>
```
Si falla: parsea la **primera** línea con `error:` e ignora el ruido posterior.
Abre el archivo en la línea exacta, explica la causa en una frase, aplica el
fix y recompila. Nunca reintentes el mismo comando sin cambiar nada.
Máximo 3 ciclos, luego resume el estado y detente.

Librería faltante: `pio pkg install -e <env> -l "<nombre o url>"` y agrégala a
`lib_deps`.

### 3. Subir
```powershell
pio run -e <env> -t upload
```
Deja que PIO autodetecte el puerto. Solo pasa `--upload-port` si hay más de un
dispositivo conectado.
- Éxito en AVR: `bytes of flash verified` + `avrdude done`.
- Éxito en ESP32: `Hard resetting via RTS pin`.

### 4. Monitorear
- Monitor **del usuario** (interactivo, ventana propia):
  `open_serial_monitor.ps1 -Env <env>`
- Monitor **tuyo** (para leer la salida sin molestar):
  `open_serial_monitor.ps1 -Env <env> -Mode Background`, luego
  `Get-Content <log> -Tail 20`

### 5. Ciclo rápido (el 90% del uso real)
```powershell
& "__WORKDIR__\scripts\flash_watch.ps1" -Env <env>
```

### 6. Depurar (por orden de costo)
1. Trazas por Serial + `esp32_exception_decoder`. Si el decoder no corrió:
   `decode_backtrace.ps1 -Env <env> -LogFile <log>`.
2. JTAG: `esp-builtin` (S3/C3/C6), `esp-prog` o `jlink` (ESP32 clásico),
   `stlink` (STM32), `avr-stub` (Uno/Nano, **ocupa el puerto serie**).
   Requiere `build_type = debug`.
3. `pio run -t size` y análisis del mapa de memoria.

## SAFETY

Nunca ejecutes sin confirmación **explícita** del usuario:
- `erase_flash` / `pio run -t erase`
- cambios de fuses
- quemado de bootloader

## ERRORES COMUNES (casos reales de este montaje)

| Síntoma | Causa | Acción |
|---|---|---|
| `Please specify upload_port for environment` | Windows no ve ningún dispositivo | Cable, driver, modo boot (en ese orden) |
| `could not open port COMx: Access is denied` | Monitor o plotter tienen el puerto | `stop_serial_monitor.ps1` |
| `Failed to connect to ESP32: Wrong boot mode detected` | Chip no entró en bootloader | Mantén BOOT presionado al iniciar la carga |
| `A fatal error occurred: Timed out waiting for packet header` | Cable/puerto USB deficiente | Baja `upload_speed` a 115200 |
| `avrdude: stk500_recv(): programmer is not responding` | Puerto ocupado, o Nano con bootloader viejo | Cierra monitor; prueba `nanoatmega328` (57600) |
| `PermissionError: [WinError 5] ... _cffi_backend.pyd` | Archivo bloqueado por otro proceso | Reintenta el comando **una** vez |
| `UnicodeEncodeError: 'charmap' codec` | Emoji en script bajo cp1252 | Quita el emoji, no cambies el encoding de la consola |
| `'Serial.printf' is not a member of 'HardwareSerial'` | `printf` existe en ESP32, no en AVR | `snprintf` + `Serial.println` (snippet `aprintf`) |
| Extensión PlatformIO no aparece tras reinstalar | Se instaló en el perfil equivocado | Verifica que esté en `.antigravity-ide\extensions` |
| clangd marca errores en un proyecto que compila | `compile_commands.json` de otro entorno | `pio run -e <env> -t compiledb` |
