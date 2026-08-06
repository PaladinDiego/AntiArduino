# AGENTS.md — Instrucciones para el agente que EJECUTA este instalador

> Este archivo es para el agente de IA que va a **correr** este repositorio en la
> máquina de un usuario final. No confundir con
> [`config/AGENTS.md.template`](config/AGENTS.md.template), que es el archivo que
> el instalador copia al *workspace del usuario final* (`C:\embedded-dev\AGENTS.md`)
> para que el agente que trabaje ahí conozca ese proyecto de Arduino/ESP32/STM32.
> Este archivo describe el propio proceso de instalación, no el proyecto embebido.

Si estás leyendo esto porque acabas de clonar el repo, este es el primer archivo
que debes leer. No leas `README.md` primero — ese está escrito para humanos
(ver la nota al principio del README).

---
## Paso 0 — ¿ya tienes el repo clonado?

Si llegaste a este archivo **sin haber clonado el repo** (por ejemplo, lo leíste
directo vía URL raw sin pasar por GitHub), detente: los pasos siguientes asumen
que tu directorio de trabajo ya es la raíz del repo clonado. Ve a la sección
"Para agentes de IA" de [`README.md`](README.md) y sigue el comando de clonado
que está ahí — no lo repliques de memoria aquí, para no tener dos copias que
puedan desincronizarse.

## Prerequisitos del sistema (verifica antes de correr nada)

`00-Preflight.ps1` (el primer módulo, corre siempre incluso en `-DryRun`)
exige:

- **Python >= 3.9 en el PATH.** Compara Major/Minor como enteros.
- Windows de 64 bits.
- Perfil de Antigravity IDE resoluble (ver `Resolve-AntigravityProfile` más
  abajo).

`git` no es un check bloqueante de Preflight, pero sin él PlatformIO no podrá
descargar algunas librerías de Arduino desde repositorios durante la
compilación — si el usuario reporta un fallo de compilación por una librería
que no aparece, comprueba `git --version` antes de asumir otra causa.

Si Preflight falla por Python, el propio módulo ya imprime el comando de
remediación exacto (`winget install Python.Python.3.12 ...`) en el log
`[FAIL]`. Desde 2026, si la consola es interactiva (stdin no redirigido) y
`winget` está disponible, Preflight puede ofrecer instalarlo por ti tras una
confirmación explícita (`Read-Host`, S/N) — **esto es la única excepción
conocida a "no arregles nada automáticamente"** en este repo, y solo aplica a
esa pregunta puntual. Si tu sesión es no interactiva (stdin redirigido, caso
típico de un agente automatizado), Preflight detecta esto y omite el prompt
por su cuenta — no necesitas hacer nada especial, pero tampoco esperes que se
instale nada por ti: falla con el mensaje de remediación y debes reportarlo
al usuario o esperar instrucciones, igual que cualquier otro `[FAIL]`.

Ver también [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (`## ERROR:
Python NO encontrado en PATH`) y `manifest.json` → `modules[0].checks`.

---

## Si eres un agente ejecutando este repo por primera vez, haz EXACTAMENTE esto

Sin variantes. En este orden. Desde PowerShell, con el directorio de trabajo en
la raíz del repo.

```powershell
.\Deploy-Environment.ps1 -DryRun
```

1. Si el comando anterior termina con `EXITCODE: 0` (o `$LASTEXITCODE -eq 0`) y
   el log muestra las 8 fases (`00-Preflight` a `07-GenerateReport`) sin ninguna
   línea `[FAIL]`, continúa al paso 2.
2. Si el `-DryRun` falla, **no sigas** al paso 2. Ve directo a la sección
   "Cómo reportar un error" más abajo. No intentes "arreglarlo" reescribiendo
   código de `src/` a menos que el usuario te lo pida explícitamente.
3. Ejecuta la instalación real:
   ```powershell
   .\Deploy-Environment.ps1
   ```
4. Verifica el resultado de forma independiente (no confíes en el log de
   instalación):
   ```powershell
   .\scripts\verify-install.ps1
   ```
5. Si `verify-install.ps1` reporta `N de N checks pasaron`, informa éxito al
   usuario. Si reporta menos de N, pega la lista de checks fallidos tal cual y
   busca cada mensaje en `docs/TROUBLESHOOTING.md` antes de decidir qué hacer.

No hay pasos alternativos. No ejecutes los scripts de `src/` individualmente,
no llames a `undo.ps1` "por si acaso", no uses `-Force` salvo que el usuario lo
pida explícitamente.

---

## Reintentos incrementales (`-Resume` / `-OnlyModules`)

Si ya corriste `Deploy-Environment.ps1` una vez en esta sesión (real, no
`-DryRun`) y necesitas volver a correrlo — por ejemplo, porque aplicaste un
fix a un solo módulo y quieres verificarlo — **no repitas el flujo completo
del paso 3 desde cero sin más.** Desde 2026-08-05, el orquestador soporta dos
flags para esto:

- **`.\Deploy-Environment.ps1 -Resume`**: corre las 8 fases en el mismo orden
  de siempre, pero `02-InstallExtensions`, `04-InstallPlatforms` y
  `05-RunSmokeTests` se saltean (log `[SKIP]`) si su contenido no cambió desde
  la última corrida real exitosa. Son los únicos 3 módulos cacheables — el
  resto (`00`, `01`, `03`, `06`, `07`) siempre corre en vivo, con o sin
  `-Resume`, porque ya es barato por su propio diseño interno. La decisión de
  saltar o no se basa en un hash del contenido real (script + templates +
  parámetros relevantes), **no** en que "ya se corrió antes" — si editaste
  `04-InstallPlatforms.ps1`, esa corrida se re-ejecuta sola, y además fuerza
  que `05-RunSmokeTests` también se re-ejecute aunque no lo hayas tocado
  (05 compila con lo que 04 instaló, así que un cambio en 04 puede invalidar
  el resultado cacheado de 05).
- **`.\Deploy-Environment.ps1 -OnlyModules 04,05`**: corre *exclusivamente*
  los módulos nombrados (por número o nombre completo), sin tocar el resto —
  ni siquiera `00-Preflight`. Los módulos nombrados siempre se ejecutan de
  verdad, nunca se saltean por cache. Útil para depuración puntual explícita,
  que es exactamente la excepción que ya contemplaba la regla de "no
  ejecutes los scripts de `src/` individualmente" más arriba.

`-Resume -DryRun` es seguro y útil como "estado del pipeline": calcula y
muestra qué se saltearía sin escribir nada. `-Force` sigue ganando sobre
`-Resume` — con ambos activos, los 3 módulos cacheables se re-ejecutan sin
importar el estado guardado (mismo comportamiento de siempre de `-Force`,
ahora explícito también respecto al cache).

El estado vive en `.deploy-state.json` (raíz del repo, gitignored). Se
actualiza automáticamente en cada corrida real exitosa, uses `-Resume` o no
— así que no necesitas planear con anticipación cuándo usarlo. Si corriste
`undo.ps1`, ese archivo se borra solo al final (evita que el cache mienta
sobre algo que la reversión acaba de quitar).

Ver `manifest.json` → `incremental_state` para el detalle completo del
mecanismo (qué entra en cada fingerprint, por qué solo esos 3 módulos).

---

## NO hagas esto

Cosas que ya se probaron en esta sesión de desarrollo y fallan o son
peligrosas:

- **No reescribas `Resolve-AntigravityProfile` de memoria.** Vive en
  `src/00-Common.ps1`. Ya tuvo un bug real (buscaba `product.json` solo en la
  raíz de instalación, cuando en instalaciones reales vive en
  `resources\app\product.json`) y otro bug real (asumía el nombre del binario
  como `antigravity.cmd` cuando en la práctica es `antigravity-ide.cmd`). La
  versión actual ya busca en ambas rutas de `product.json` y resuelve
  `bin\*.cmd` dinámicamente. Si necesitas resolver el perfil del IDE en un
  script nuevo, dot-source `00-Common.ps1` y usa la función, no la repliques.
- **No asumas el nombre del binario del IDE.** Varía entre instalaciones
  (`antigravity.cmd` vs `antigravity-ide.cmd` vs cualquier otro `*.cmd` futuro
  dentro de `bin\`). Siempre usa `Resolve-AntigravityProfile`, nunca una ruta
  hardcodeada.
- **No trates un crash de Electron posterior a un output válido como fallo
  real.** Ver la sección "Comportamiento conocido no determinista" abajo antes
  de asumir que algo se rompió.
- **No ejecutes un módulo de `src/*.ps1` de forma aislada** fuera de
  `Deploy-Environment.ps1` (o `undo.ps1` para reversión) salvo depuración
  puntual explícitamente pedida por el usuario. Los módulos comparten
  `RepoRoot`/`LogFile`/`WorkDir`/`Platforms` inyectados por el orquestador; si
  los invocas sueltos con parámetros inventados, el comportamiento no es
  representativo.
- **No agregues `-Force` "para asegurarte".** Sobrescribe configuración real
  del usuario (`settings.json`, `keybindings.json`, extensiones, plataformas)
  sin preguntar. Solo úsalo si el usuario lo pide explícitamente.
- **No envuelvas la invocación completa del orquestador en `2>&1` al probar
  en PowerShell 5.1.** En ese escenario, PowerShell puede envolver stderr
  nativo interno (benigno) como `ErrorRecord`, y combinado con
  `$ErrorActionPreference = "Stop"` (que `Deploy-Environment.ps1` define),
  eso se convierte en una excepción terminante que no refleja un fallo real.
  Si necesitas capturar toda la salida, usa `Tee-Object` o simplemente deja que
  el log vaya a consola.
- **No agregues patrones a `.gitignore` sin anclar con `/` al inicio** si el
  patrón es un nombre de archivo específico (no una extensión genérica). Un
  patrón como `stop_serial_monitor.ps1` sin `/` bloquea ese nombre en
  *cualquier* subcarpeta del repo, no solo en la raíz — esto ya causó que dos
  archivos reales (`scripts/stop_serial_monitor.ps1` y
  `docs/ARQUITECTURA_SERIAL_MONITOR.md`) quedaran fuera del repo en silencio
  durante semanas sin que nadie lo notara.

---

## Comportamiento conocido no determinista

### Crash de Electron al final de `--list-extensions` (benigno)

Durante `02-InstallExtensions.ps1`, la llamada `& $AgCmd --list-extensions`
invoca el binario del IDE en modo headless. De forma intermitente (no en cada
corrida), el proceso imprime:

```
[createInstance] extensionManagementService depends on antigravityAnalytics which is NOT registered.
```

y ocasionalmente, además, un stack trace nativo de V8/Node terminando en algo
como:

```
FATAL ERROR: v8::ToLocalChecked Empty MaybeLocal
----- Native stack trace -----
...
```

con un `ExitCode` residual distinto de cero (se observó `134`).

**Esto es benigno si la lista de extensiones ya se obtuvo correctamente antes
del crash** — es decir, si en el log ves líneas `[OK] Extension ... ya esta
instalada.` inmediatamente después. El crash ocurre al *cerrar* el proceso,
después de que ya escribió su output útil a stdout.

El script ya maneja esto: valida que `$Installed` (la salida de
`--list-extensions`) no esté vacía antes de confiar en la detección; si tiene
contenido, ignora el `ExitCode` residual y sigue. Solo si `$Installed` está
vacío/en blanco Y el `ExitCode` es distinto de cero, el módulo falla de verdad
(entonces sí es una señal real de que el binario está roto).

**Si ves este mensaje: no reinstales el IDE, no repliques el fallback manual
de extensiones, no reportes esto como error al usuario por sí solo.** Solo
repórtalo si el módulo `02-InstallExtensions.ps1` termina con `[FAIL]` en el
log Y `$Installed` estaba vacío.

---

## Cómo verificar éxito de forma independiente

No confíes en que el log de instalación (`setup.log`) diga `[OK]` en todo.
Corre esto contra el sistema real, en cualquier momento, incluso en una sesión
nueva sin haber corrido el instalador antes:

```powershell
.\scripts\verify-install.ps1
```

(Acepta `-WorkDir <ruta>` si el workspace no es el default `C:\embedded-dev`.)

El script comprueba el estado real del sistema (binarios, plataformas
instaladas, extensiones registradas, claves de configuración, archivos del
workspace) — no lee `setup.log` ni asume que la instalación reportó éxito.
Imprime `N de M checks pasaron` y, si algo falló, la lista explícita de qué
falló.

---

## Cómo reportar un error

1. Copia el mensaje de error **completo y literal**, no un resumen.
2. Búscalo en [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — está
   organizado como bloques `## ERROR: <patrón>` pensados para grep. Busca por
   fragmentos del mensaje, no solo por título de sección.
3. Si el error (o un patrón que lo cubra con regex) **aparece textualmente**
   en `TROUBLESHOOTING.md`, sigue la `ACCIÓN` indicada ahí al pie de la letra
   y respeta cualquier `NO HACER` de esa entrada.
4. **Si el error no está ahí textualmente, NO improvises una solución.**
   Repórtalo al usuario con el mensaje de error completo (stdout + stderr, sin
   resumir ni truncar) y espera instrucciones. No adivines una corrección de
   código, no reinstales componentes al azar, no borres estado (`undo.ps1`,
   backups, extensiones) sin que el usuario lo pida.
