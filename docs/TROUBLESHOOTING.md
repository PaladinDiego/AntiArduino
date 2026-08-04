# Troubleshooting

Formato fijo, uno por bloque, pensado para grep:

```
## ERROR: <mensaje exacto o patrón>
CAUSA: <una frase>
ACCIÓN: <pasos numerados, imperativos>
NO HACER: <si aplica>
```

Para agentes: si tu error no aparece aquí **textualmente** (ni como patrón que
lo cubra), no improvises — repórtalo al usuario completo y espera
instrucciones. Ver `AGENTS.md`.

`C:\embedded-dev\setup.log` tiene la historia completa con marcas de tiempo de
cualquier instalación real (no `-DryRun`).

---

# Durante la instalación

## ERROR: No se encontro ninguna instalacion de Antigravity IDE
## ERROR: No se encontro un perfil de Antigravity IDE con dataFolderName = '.antigravity-ide'

CAUSA: `Resolve-AntigravityProfile` (`src/00-Common.ps1`) busca `product.json`
en `%LOCALAPPDATA%\Programs\*Antigravity*\product.json` y en
`%LOCALAPPDATA%\Programs\*Antigravity*\resources\app\product.json`. Si la
instalación real está en otra ruta (por ejemplo `C:\Program Files`), o si
`product.json` vive en una tercera ubicación no contemplada, no se encuentra.

ACCIÓN:
1. Lista las carpetas candidatas:
   ```powershell
   Get-ChildItem "$env:LOCALAPPDATA\Programs" -Directory | Select-Object Name
   ```
2. Para cada candidata, comprueba si tiene `product.json` y qué
   `dataFolderName` declara:
   ```powershell
   Get-ChildItem "$env:LOCALAPPDATA\Programs" -Directory | ForEach-Object {
     foreach ($p in @("$($_.FullName)\product.json", "$($_.FullName)\resources\app\product.json")) {
       if (Test-Path $p) { (Get-Content $p -Raw | ConvertFrom-Json) | Select-Object @{n='Carpeta';e={$_.applicationName}}, dataFolderName, version, @{n='Ruta';e={$p}} }
     }
   }
   ```
3. Si ninguna carpeta tiene `dataFolderName = ".antigravity-ide"`, el IDE no
   está instalado correctamente. Instálalo desde el instalador oficial de
   usuario (no `C:\Program Files`, que requiere permisos de administrador y
   el instalador no lo busca ahí).
4. Si sí existe pero en una ruta rara, repórtalo al usuario — puede requerir
   ampliar `Resolve-AntigravityProfile` con una tercera ruta candidata.

NO HACER: no hardcodees la ruta del `product.json` que encontraste como
"solución" en tu sesión — eso reintroduce el mismo bug que ya se corrigió una
vez (ver AGENTS.md, sección "NO hagas esto").

---

## ERROR: antigravity.cmd
## ERROR: El binario del IDE no existe en la ruta esperada

CAUSA: El nombre del ejecutable `.cmd` dentro de `bin\` varía entre
instalaciones (`antigravity.cmd`, `antigravity-ide.cmd`, u otro nombre en
versiones futuras). Un código que asuma un nombre fijo falla en cualquier
instalación que use otro.

ACCIÓN:
1. Nunca uses una ruta de binario hardcodeada. Usa
   `Resolve-AntigravityProfile` de `src/00-Common.ps1`, que resuelve
   dinámicamente el primer `*.cmd` dentro de `bin\` de la instalación con
   `dataFolderName = ".antigravity-ide"`.
2. Para confirmar el nombre real en una máquina dada:
   ```powershell
   Get-ChildItem "$env:LOCALAPPDATA\Programs\Antigravity IDE\bin" -Filter "*.cmd"
   ```

NO HACER: no asumas que el nombre es `antigravity.cmd` porque lo viste en una
instalación — en la máquina de prueba real de este repo el binario es
`antigravity-ide.cmd`.

---

## ERROR: Python NO encontrado en PATH

CAUSA: Python no está instalado, o el único `python.exe` en el PATH es el
alias falso de la Microsoft Store.

ACCIÓN:
1. Comprueba qué resuelve el PATH:
   ```powershell
   where.exe python
   ```
2. Si la ruta termina en `WindowsApps\python.exe`, desactiva el alias en
   *Configuración > Aplicaciones > Alias de ejecución de aplicaciones*.
3. Reinstala Python marcando **"Add python.exe to PATH"**.

NO HACER: no instales un segundo Python sin desactivar el alias de la Store
primero — seguirá ganando el alias por orden del PATH.

---

## ERROR: PlatformIO Core installation FAILED

CAUSA: El instalador de PlatformIO Core no pudo descargar `get-platformio.py`
o ejecutar el instalador (red corporativa, proxy, antivirus).

ACCIÓN:
1. Descarga e instala a mano:
   ```powershell
   curl.exe -o get-platformio.py https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py
   python get-platformio.py
   ```
2. Vuelve a lanzar `setup.bat` (o `Deploy-Environment.ps1`): detecta que
   `pio.exe` ya existe y continúa con el resto de los módulos.

NO HACER: no repitas la descarga en bucle sin revisar si hay un proxy/firewall
corporativo bloqueando `raw.githubusercontent.com` — el reintento por sí solo
no lo resuelve.

---

## ERROR: PermissionError: [WinError 5] ... _cffi_backend.pyd

CAUSA: Un archivo temporalmente bloqueado por otro proceso durante la
instalación de una plataforma (observado con `espressif32`).

ACCIÓN:
1. El script ya reintenta 3 veces con espera creciente; en la mayoría de los
   casos se resuelve solo.
2. Si persiste, cierra el IDE y cualquier terminal con PlatformIO abierto.
3. Repite la instalación.

NO HACER: no borres manualmente `~/.platformio` para "empezar de cero" solo
por este error — es mucho más agresivo de lo necesario y borra plataformas ya
instaladas correctamente.

---

## ERROR: La extensión PlatformIO IDE no aparece en extensions.json / --list-extensions tras la instalación

CAUSA: Antigravity usa Open VSX, donde la extensión oficial de PlatformIO no
está publicada. Los tres fallbacks (Open VSX → descarga de `.vsix` desde
GitHub → parche del manifiesto) fallaron los tres.

ACCIÓN:
1. Esto **no es bloqueante**: todo el flujo de compilación/carga funciona por
   CLI (`pio`) y las tareas de `tasks.json` llaman a `pio.exe` directamente,
   no a la extensión del IDE.
2. Para intentarlo a mano, resuelve primero el binario correcto (no lo
   hardcodees, ver entrada de `antigravity.cmd` arriba):
   ```powershell
   . .\src\00-Common.ps1
   $cli = Resolve-AntigravityProfile
   & $cli --install-extension "C:\ruta\platformio-ide-3.3.4.vsix" --force
   ```

NO HACER: no reportes esto como fallo crítico de la instalación por sí solo —
confírmalo primero corriendo `scripts/verify-install.ps1`, que valida el
resto del entorno independientemente de esta extensión puntual.

---

## ERROR: depends on the C/C++ extension

CAUSA: El manifiesto original de la extensión PlatformIO declara una
dependencia dura de `ms-vscode.cpptools`, que no existe en forks de VS Code
como Antigravity.

ACCIÓN:
1. El script ya parchea `package.json` cambiando `extensionDependencies` por
   `extensionPack` y quitando `ms-vscode.cpptools` — ver
   `src/02-InstallExtensions.ps1`.
2. Si necesitas parchear a mano, hazlo por **reemplazo de texto plano**
   (`-replace` sobre el string), nunca por round-trip
   `ConvertFrom-Json | ConvertTo-Json`.

NO HACER: no uses `ConvertFrom-Json | ConvertTo-Json -Depth N` sobre este
`package.json` para "limpiarlo" — el nodo `contributes` tiene más
profundidad que cualquier `-Depth` razonable y el archivo queda truncado
silenciosamente (sin error visible).

---

## ERROR: [createInstance] extensionManagementService depends on antigravityAnalytics which is NOT registered
## ERROR: FATAL ERROR: v8::ToLocalChecked Empty MaybeLocal

CAUSA: El binario del IDE, al ejecutarse en modo headless para
`--list-extensions`, imprime este aviso de telemetría no registrada y,
ocasionalmente, crashea al *cerrar el proceso* (después de ya haber escrito
el listado de extensiones a stdout) con un stack trace nativo de V8/Node y un
`ExitCode` residual distinto de cero (observado: `134`). Es un crash de
Electron al salir, no un fallo de la operación que se pidió.

ACCIÓN:
1. Si el log muestra `[OK] Extension ... ya esta instalada.` inmediatamente
   después (es decir, la detección funcionó), **ignora el mensaje** — es
   benigno.
2. `src/02-InstallExtensions.ps1` ya valida esto: solo trata el `ExitCode`
   como fallo real si `$Installed` (la salida de `--list-extensions`) está
   vacía o en blanco. Si ves un `[FAIL]` real de este módulo, revisa si
   `$Installed` estaba vacío — si sí, sí es un fallo real (el binario no
   devolvió nada útil, algo está roto de verdad).
3. Si estás reproduciendo esto manualmente fuera del script, vuelve a correr
   `& $AgCmd --list-extensions` una vez más — es intermitente, no determinista.

NO HACER: no reinstales el IDE ni repitas el fallback manual de extensiones
solo por ver este mensaje. No lo reportes al usuario como error si la
detección de extensiones ya tuvo éxito antes del crash.

---

# Después de instalar

## ERROR: El IDE abre sin ninguna de mis configuraciones (settings.json parece vacío o por defecto)

CAUSA: Hay dos instalaciones posibles de Antigravity (`antigravity` y
`Antigravity IDE`), cada una con su propia carpeta de datos en `%APPDATA%`.
Estás abriendo el binario equivocado.

ACCIÓN:
1. Identifica cuál instalación tiene `dataFolderName = ".antigravity-ide"`:
   ```powershell
   @("antigravity","Antigravity IDE") | ForEach-Object {
     $pj = "$env:LOCALAPPDATA\Programs\$_\resources\app\product.json"
     if (Test-Path $pj) {
       $p = Get-Content $pj -Raw | ConvertFrom-Json
       [pscustomobject]@{ Carpeta=$_; NameShort=$p.nameShort; DataFolder=$p.dataFolderName; Version=$p.version }
     }
   } | Format-List
   ```
2. Ese es el que tiene la configuración instalada, en
   `%APPDATA%\Antigravity IDE\User`. Ancla ese acceso directo a la barra de
   tareas.

NO HACER: no copies `settings.json` manualmente al perfil equivocado
(`%APPDATA%\Antigravity\User`, sin "IDE") — es el perfil huérfano del
standalone, no el que usa el instalador.

---

## ERROR: clangd subraya en rojo código que compila perfectamente con pio run

CAUSA: Tres posibles, en orden de frecuencia: `compile_commands.json` de otro
entorno, workspace abierto en la carpeta equivocada (muy amplia), o
`--query-driver` desactualizado tras instalar una plataforma nueva.

ACCIÓN:
1. Regenera la base de datos de compilación del entorno activo:
   `Ctrl+Shift+I`, o `pio run -e <env> -t compiledb`.
2. Verifica que abriste la carpeta del proyecto concreto, no tu carpeta de
   usuario completa (clangd intenta indexar todo el disco).
3. Si instalaste una plataforma nueva después del setup original, vuelve a
   ejecutar `setup.bat -Force` para reconstruir `--query-driver` a partir de
   los toolchains realmente presentes.

NO HACER: no añadas `--compile-commands-dir=${workspaceFolder}` a
`clangd.arguments` — fuerza a clangd a buscar la base de datos solo en la raíz
del workspace y rompe proyectos en subcarpetas.

---

## ERROR: could not open port COMx: Access is denied

CAUSA: Otro proceso tiene el puerto COM abierto — en Windows el acceso es
exclusivo.

ACCIÓN:
1. Cierra el proceso que lo tiene:
   ```powershell
   & C:\embedded-dev\scripts\stop_serial_monitor.ps1 -Port COM9
   ```
2. Culpables habituales: el monitor externo del propio setup, el plotter web
   abierto en el navegador, el monitor de la extensión PlatformIO, o el
   Monitor Serie del Arduino IDE.

NO HACER: no dejes el plotter web y el monitor de terminal abiertos a la
vez — no pueden coexistir sobre el mismo puerto.

---

## ERROR: Please specify 'upload_port' for environment

CAUSA: Windows no detecta **ningún** dispositivo serie. No es un problema de
configuración de `platformio.ini`.

ACCIÓN, por probabilidad real:
1. Prueba con otro cable USB — el más común es un cable de solo carga, sin
   líneas de datos.
2. Ejecuta `python C:\embedded-dev\scripts\detect_board.py` para comprobar si
   falta un driver.
3. Revisa si la placa quedó colgada o en modo boot; reconéctala.

NO HACER: no fijes `upload_port` a mano "para arreglarlo" si no hay ningún
dispositivo — solo cambia el mensaje de error, no soluciona la causa.

---

## ERROR: Failed to connect to ESP32: Wrong boot mode detected

CAUSA: La placa no entró en modo de descarga (bootloader) antes de que
`esptool` intentara conectar.

ACCIÓN:
1. Mantén pulsado **BOOT** mientras empieza la carga.
2. Suelta **BOOT** en cuanto aparezca `Connecting...`.
3. Algunas placas necesitan también pulsar **EN/RST** en el momento correcto.

NO HACER: no cambies `upload_speed` como primer intento — el boot mode es la
causa dominante de este mensaje específico.

---

## ERROR: A fatal error occurred: Timed out waiting for packet header

CAUSA: Velocidad de subida demasiado alta para el cable/puerto/placa, o cable
de mala calidad.

ACCIÓN:
1. Baja la velocidad en `platformio.ini`:
   ```ini
   upload_speed = 115200
   ```
2. Prueba otro cable u otro puerto USB (preferible uno trasero, directo a la
   placa base, no un hub).

NO HACER: no asumas que es un problema de driver antes de probar cable y
puerto — es la causa más común con diferencia.

---

## ERROR: avrdude: stk500_recv(): programmer is not responding

CAUSA: Puerto ocupado por otro proceso, o un Arduino Nano con bootloader
antiguo que necesita 57600 baudios en vez de 115200.

ACCIÓN:
1. Cierra el monitor serial si está abierto sobre ese puerto.
2. Si es un Nano viejo, usa el entorno `nano_old` de
   `templates\platformio-nano.ini` (compila a 57600 baudios).

NO HACER: no reflashees repetidamente al mismo baudrate esperando que
funcione a la enésima — si es un Nano viejo, el entorno normal nunca va a
conectar.

---

## ERROR: La ventana del monitor serial no aparece

CAUSA: El script lanza el monitor vía el Programador de Tareas de Windows
para escapar del Job Object (kill-on-close) del IDE. Si el Programador de
Tareas no puede ejecutar procesos interactivos (política de grupo, sesión no
interactiva), la ventana nunca aparece.

ACCIÓN:
1. Comprueba que el Programador de Tareas puede lanzar una ventana:
   ```powershell
   schtasks /create /tn PRUEBA_AG /tr "cmd.exe /c echo hola & pause" /sc once /st 00:00 /f
   schtasks /run /tn PRUEBA_AG
   schtasks /delete /tn PRUEBA_AG /f
   ```
2. Si tampoco aparece ventana ahí, es una política de grupo o sesión no
   interactiva — no es un bug del script. Usa el modo background como
   alternativa:
   ```powershell
   & C:\embedded-dev\scripts\open_serial_monitor.ps1 -Env uno -Mode Background
   Get-Content C:\embedded-dev\.antigravity-embedded\logs\monitor_uno_*.log -Tail 20 -Wait
   ```

NO HACER: no concluyas que el script está roto solo por esto — confirma
primero con la prueba de `schtasks` de arriba, que aísla el problema del
Programador de Tareas del problema del script.

---

## ERROR: La placa recibe las palabras cortadas al escribir en el monitor

CAUSA: Es esperado en los modos `Logged` y `Background`: `--filter log2file`
desactiva `send_on_enter`, así que cada tecla se envía suelta.

ACCIÓN:
1. El firmware debe acumular caracteres en un búfer hasta recibir `\n` o
   `\r`. Usa el snippet `aserialbuffer` (`snippets/arduino.code-snippets`).
2. Si necesitas comportamiento con `send_on_enter`, usa el modo `Interactive`
   (el de por defecto), que respeta los `monitor_filters` de
   `platformio.ini`.

NO HACER: no uses `Serial.readStringUntil()` en este entorno — corta por
timeout en cuanto alguien teclea a velocidad humana, no espera el delimitador
real.

---

## ERROR: UnicodeEncodeError: 'charmap' codec can't encode character

CAUSA: Hay un emoji o un carácter acentuado en un script `.ps1` o `.py`. La
consola de Windows por defecto es cp1252, no UTF-8.

ACCIÓN:
1. Quita el carácter problemático del script.
2. Usa marcadores ASCII simples: `[OK]`, `[FAIL]`, `[WARN]`.

NO HACER: no cambies el encoding de la consola para "arreglarlo" — rompe
otras herramientas que asumen cp1252 en esta misma sesión.

---

## ERROR: 'Serial.printf' is not a member of 'HardwareSerial'

CAUSA: `printf` existe en la implementación de `HardwareSerial` de ESP32 pero
no en AVR (Uno, Nano, Mega).

ACCIÓN:
1. Para código portable entre plataformas, usa el snippet `aprintf`
   (`snippets/arduino.code-snippets`): `snprintf` a un búfer y luego
   `Serial.println`.

NO HACER: no condiciones el código con `#ifdef ESP32` solo para poder seguir
usando `Serial.printf` — el snippet `aprintf` ya resuelve esto sin
condicionales de plataforma.

---

## ERROR: El agente IA no usa la skill arduino-flash

CAUSA: La sesión del agente no redetectó la skill, o la ruta de skills cambió
en la versión instalada del IDE.

ACCIÓN:
1. Reinicia la sesión del agente.
2. Comprueba que el archivo existe:
   `C:\embedded-dev\.agents\skills\arduino-flash\SKILL.md`
3. Pide algo que dispare los triggers de la skill (por ejemplo: *"sube el
   código al uno"*).
4. Si sigue sin activarse, la ruta de skills puede haber cambiado en tu
   versión del IDE. Consulta
   <https://antigravity.google/docs/ide/skills> y mueve la carpeta. El
   instalador deja una copia adicional en
   `%USERPROFILE%\.gemini\config\skills\arduino-flash\` por si esa es la ruta
   correcta en tu versión.

NO HACER: no dupliques `SKILL.md` en más ubicaciones "por si acaso" sin
confirmar primero cuál ruta usa tu versión del IDE.

---

# Empezar de cero

```powershell
cd C:\embedded-dev
.\undo.ps1
```

Y vuelve a ejecutar `setup.bat`. Los backups `*.bak_<fecha>` siguen ahí por si
necesitas recuperar algo concreto.
