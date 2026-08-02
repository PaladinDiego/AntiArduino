# Troubleshooting

Casos reales de este montaje, con el síntoma exacto y qué hacer. Antes de nada:
`C:\embedded-dev\setup.log` tiene la historia completa con marcas de tiempo.

---

## Durante la instalación

### `No se encontro ninguna instalacion de Antigravity IDE`

El script busca en `%LOCALAPPDATA%\Programs\*Antigravity*` una carpeta que
contenga `resources\app\product.json`.

```powershell
Get-ChildItem "$env:LOCALAPPDATA\Programs" -Directory | Select-Object Name
```

Si tu instalación está en otro sitio (por ejemplo `C:\Program Files`), el script
no la ve. Instala Antigravity IDE desde el instalador oficial de usuario, o
copia manualmente `settings.json` y `keybindings.json` desde
`C:\embedded-dev\.antigravity-embedded\settings.generated.json`.

### `Python NO encontrado en PATH`

Reinstala Python marcando **"Add python.exe to PATH"**. Comprobación:

```powershell
where.exe python
```

Si aparece una ruta que acaba en `WindowsApps\python.exe`, ese es el alias falso
de la Microsoft Store. Desactívalo en *Configuración > Aplicaciones > Alias de
ejecución de aplicaciones*.

### `PlatformIO Core installation FAILED` / no se puede descargar

El script prueba GitHub y luego un mirror de jsDelivr. Si ambos fallan es red
corporativa, proxy o antivirus. Instálalo a mano:

```powershell
curl.exe -o get-platformio.py https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py
python get-platformio.py
```

Y vuelve a lanzar `setup.bat`: detectará que ya está y seguirá con el resto.

### `PermissionError: [WinError 5] ... _cffi_backend.pyd`

Un archivo temporalmente bloqueado por otro proceso. **Ya pasó una vez durante
la instalación de espressif32 y se resolvió solo al reintentar.** El script
reintenta 3 veces con espera creciente. Si aún así falla, cierra el IDE y
cualquier terminal con PlatformIO abierto y repite.

### La extensión PlatformIO IDE no queda instalada

Antigravity usa Open VSX, donde la extensión oficial no está publicada. El script
prueba tres caminos: Open VSX → descarga del `.vsix` de GitHub → parche del
manifiesto. Si los tres fallan:

**No es bloqueante.** Todo el flujo funciona por CLI (`pio`) y las tareas de
`tasks.json` llaman a `pio.exe` directamente, no a la extensión.

Para intentarlo a mano:

```powershell
$cli = "$env:LOCALAPPDATA\Programs\Antigravity IDE\bin\antigravity-ide.cmd"
& $cli --install-extension "C:\ruta\platformio-ide-3.3.4.vsix" --force
```

### La extensión se instala pero no arranca: *"depends on the C/C++ extension"*

Declara una dependencia dura de `ms-vscode.cpptools`, que no existe en los forks
de VS Code. El script parchea `package.json` cambiando `extensionDependencies`
por `extensionPack` y quitando cpptools. Si tuviste que parchear a mano,
**hazlo con reemplazo de texto plano**: un round-trip
`ConvertFrom-Json | ConvertTo-Json` destroza ese archivo (el nodo `contributes`
tiene más profundidad que el `-Depth` por defecto).

---

## Después de instalar

### El IDE abre sin ninguna de mis configuraciones

Estás abriendo el binario equivocado. Hay dos instalaciones posibles y cada una
usa su propia carpeta de datos:

```powershell
@("antigravity","Antigravity IDE") | ForEach-Object {
  $pj = "$env:LOCALAPPDATA\Programs\$_\resources\app\product.json"
  if (Test-Path $pj) {
    $p = Get-Content $pj -Raw | ConvertFrom-Json
    [pscustomobject]@{ Carpeta=$_; NameShort=$p.nameShort; DataFolder=$p.dataFolderName; Version=$p.version }
  }
} | Format-List
```

El bueno es el que tiene `dataFolderName = .antigravity-ide`. Sus settings viven
en `%APPDATA%\Antigravity IDE\User`, **nunca** en `%APPDATA%\Antigravity\User`
(ese es el perfil del standalone, huérfano en esta máquina). Ancla el correcto a
la barra de tareas.

### clangd marca en rojo código que compila perfectamente

Tres causas, en orden de frecuencia:

1. **`compile_commands.json` es de otro entorno.** Es *por entorno*: si lo
   generaste para `esp32dev` y ahora editas el proyecto `uno`, clangd usa
   includes de Xtensa sobre código AVR. Solución: `Ctrl+Shift+I`, o
   `pio run -e <env> -t compiledb`.

2. **Abriste tu carpeta de usuario entera como workspace.** clangd intenta
   indexar todo el disco. Abre la carpeta del proyecto concreto.

3. **`--query-driver` no cubre tu toolchain.** Instalaste una plataforma nueva
   después del setup. Vuelve a ejecutar `setup.bat -Force`: reconstruye la lista
   a partir de los toolchains realmente presentes.

Nunca añadas `--compile-commands-dir=${workspaceFolder}` a `clangd.arguments`:
fuerza a buscar la base de datos solo en la raíz del workspace y rompe los
proyectos que están en subcarpetas.

### `could not open port COMx: Access is denied`

Otro proceso tiene el puerto. En Windows el COM es exclusivo.

```powershell
& C:\embedded-dev\scripts\stop_serial_monitor.ps1 -Port COM9
```

Culpables habituales: el monitor externo, el plotter web abierto en el navegador,
el monitor propio de la extensión PlatformIO, o el Monitor Serie del Arduino IDE.
El plotter y el monitor **no pueden coexistir**.

### `Please specify 'upload_port' for environment`

Windows no ve **ningún** dispositivo. No significa que falte configuración.
Causas por probabilidad real:

1. Cable USB de solo carga, sin líneas de datos. (El más común con diferencia.)
2. Driver ausente — ejecuta `python C:\embedded-dev\scripts\detect_board.py`.
3. Placa colgada o en modo boot.

**No fijes `upload_port` a mano para "arreglarlo".** Si no hay dispositivo,
fijar el puerto solo cambia el mensaje de error.

### `Failed to connect to ESP32: Wrong boot mode detected`

Mantén pulsado **BOOT** mientras empieza la carga, suéltalo cuando aparezca
`Connecting...`. Algunas placas necesitan también pulsar EN/RST.

### `A fatal error occurred: Timed out waiting for packet header`

Baja la velocidad en `platformio.ini`:

```ini
upload_speed = 115200
```

Y prueba otro cable u otro puerto USB (mejor uno trasero, directo a placa base).

### `avrdude: stk500_recv(): programmer is not responding`

Puerto ocupado (cierra el monitor), o un Arduino Nano con bootloader antiguo. En
ese caso usa el entorno `nano_old` de `templates\platformio-nano.ini`, que
compila para 57600 baudios.

### La ventana del monitor serial no aparece

El script la lanza vía Programador de Tareas para escapar del Job Object del IDE.
Comprueba que la tarea puede ejecutarse:

```powershell
schtasks /create /tn PRUEBA_AG /tr "cmd.exe /c echo hola & pause" /sc once /st 00:00 /f
schtasks /run /tn PRUEBA_AG
schtasks /delete /tn PRUEBA_AG /f
```

Si no aparece ninguna ventana, es una política de grupo o una sesión no
interactiva, no el script. Alternativa mientras tanto: modo background y leer el
log.

```powershell
& C:\embedded-dev\scripts\open_serial_monitor.ps1 -Env uno -Mode Background
Get-Content C:\embedded-dev\.antigravity-embedded\logs\monitor_uno_*.log -Tail 20 -Wait
```

### Escribo en el monitor y la placa recibe las palabras cortadas

Es esperado en los modos `Logged` y `Background`: `--filter log2file` desactiva
`send_on_enter`, así que cada tecla se envía suelta. Tu firmware debe acumular
caracteres en un búfer hasta recibir `\n` o `\r`. Usa el snippet
`aserialbuffer`. Nunca uses `Serial.readStringUntil()` en este entorno: corta por
timeout cuando alguien teclea a velocidad humana.

En modo `Interactive` (el de por defecto) esto no pasa: se respetan los
`monitor_filters` de `platformio.ini`.

### `UnicodeEncodeError: 'charmap' codec can't encode character`

Hay un emoji o un carácter acentuado en un script `.ps1` o `.py`. La terminal es
cp1252. Quita el carácter — **no cambies el encoding de la consola**, eso rompe
otras cosas. Usa `[OK]`, `[FAIL]`, `[WARN]`.

### `'Serial.printf' is not a member of 'HardwareSerial'`

`printf` existe en ESP32 pero no en AVR. Para código portable, snippet `aprintf`:
`snprintf` a un búfer y luego `Serial.println`.

### El agente IA no usa la skill `arduino-flash`

1. Reinicia la sesión del agente para que Antigravity la redetecte.
2. Comprueba que existe:
   `C:\embedded-dev\.agents\skills\arduino-flash\SKILL.md`
3. Pide algo que dispare los triggers: *"sube el código al uno"*.
4. Si sigue sin activarse, la ruta de skills puede haber cambiado en tu versión.
   Consulta <https://antigravity.google/docs/ide/skills> y mueve la carpeta.
   El instalador deja una copia también en
   `%USERPROFILE%\.gemini\config\skills\arduino-flash\`.

---

## Empezar de cero

```powershell
cd C:\embedded-dev
.\undo.ps1
```

Y vuelve a ejecutar `setup.bat`. Los backups `*.bak_<fecha>` siguen ahí por si
necesitas recuperar algo concreto.
