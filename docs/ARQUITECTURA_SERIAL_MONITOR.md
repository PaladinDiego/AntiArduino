# Arquitectura del monitor serial

Por qué el monitor no se abre como un proceso normal, sino a través del
Programador de Tareas de Windows. Es la parte menos obvia de todo el montaje, y
la que más tiempo costó.

---

## El problema

Antigravity IDE en Windows encierra cada sesión de terminal integrada en un
**Job Object** con la bandera *kill-on-close*. Es un patrón común en IDEs para no
dejar procesos huérfanos cuando se cierra una pestaña.

El efecto secundario: cualquier proceso lanzado desde esa terminal hereda el job.
`Start-Process` normalmente crea un proceso independiente, pero en Windows
**sigue heredando el job del padre** salvo que se le indique explícitamente
*breakaway*, y PowerShell no expone esa bandera.

Resultado: cuando Antigravity da por terminada la sesión de terminal —o
simplemente la recicla entre mensajes del agente— se lleva por delante la ventana
del monitor. No importa qué le pidas al prompt: mientras la ventana nazca dentro
del árbol de procesos del IDE, va a morir con él.

Hay dos bugs públicos que encajan con esto:

- Alguien intentando que una ventana CMD se quedara **oculta** no lo consiguió ni
  con `-WindowStyle Hidden`, `-NoNewWindow`, `wscript`, la API `ShowWindow()` de
  Win32 ni desactivando ConPTY. La conclusión del propio reporte apuntaba a cómo
  Antigravity genera procesos hijos en Windows, un comportamiento no estándar
  frente a otros forks de VS Code.
- Varios usuarios reportan que el agente ejecuta comandos pero no ve la salida,
  porque la señal de fin (EOF) no llega bien en Windows y el IDE se queda
  esperando algo que nunca llega.

Encima, en Windows **un puerto COM solo lo puede abrir un proceso a la vez**. Si
el upload y el monitor lo intentan simultáneamente, sale `PermissionError(13)` /
*Access is denied*, y parece un fallo de hardware cuando no lo es.

---

## La solución

Sacar el proceso del árbol de Antigravity por completo, entregándoselo a un
servicio del sistema que el IDE no controla: el **Programador de Tareas**.

```
open_serial_monitor.ps1
        |
        | 1. escribe un lanzador temporal con los valores ya sustituidos
        |    .antigravity-embedded\run_AG_Serial_<guid>.ps1
        |
        | 2. schtasks /create  -> registra la tarea
        |    schtasks /run     -> la ejecuta YA
        |    schtasks /delete  -> la borra (ya no hace falta)
        v
  Programador de Tareas de Windows          <-- fuera del Job Object del IDE
        |
        v
  pio.exe device monitor ...                <-- sobrevive a recargas del IDE
        |
        +--> ventana visible (modo Interactive)
        +--> log espejo      (modo Background)
```

El lanzador temporal existe por una razón concreta: **`schtasks /tr` está
limitado a 261 caracteres**. Con rutas largas, pasar todos los argumentos ahí
desborda el límite. Por eso los valores se hornean dentro de un `.ps1` y `/tr`
solo referencia el archivo.

Como la tarea se crea bajo el usuario actual y sin `/ru`, se ejecuta "solo cuando
el usuario ha iniciado sesión": el proceso aparece en el escritorio interactivo,
que es justo lo que queremos.

---

## Los tres modos

| Modo | Ventana | Log | `send_on_enter` | Para qué |
|---|---|---|---|---|
| `Interactive` (por defecto) | visible | no | **sí** | La usas tú, escribes comandos |
| `Logged` | visible | `platformio-device-monitor-*.log` | no | Ver y guardar a la vez |
| `Background` | oculta | `.antigravity-embedded\logs\monitor_*.log` | no | El agente lee la salida sin molestarte |

```powershell
# el tuyo
.\scripts\open_serial_monitor.ps1 -Env uno

# el del agente
.\scripts\open_serial_monitor.ps1 -Env uno -Mode Background
Get-Content .\.antigravity-embedded\logs\monitor_uno_*.log -Tail 20 -Wait
```

---

## La trampa de `send_on_enter`

Cuando el monitor se lanza con `--filter log2file`, PlatformIO **sobrescribe** los
`monitor_filters` de `platformio.ini` y deja fuera `send_on_enter`.

Sin `send_on_enter`, cada tecla que pulsas viaja al microcontrolador
inmediatamente, en lugar de esperar al Enter para mandar la línea entera. Si tu
firmware usa `Serial.readStringUntil()` o depende de `Serial.setTimeout()`, va a
cortar las palabras por la mitad: nadie teclea a velocidad de máquina.

**El firmware debe acumular caracteres y procesar solo al recibir `\n` o `\r`:**

```cpp
String cmd = "";

void loop() {
  while (Serial.available() > 0) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (cmd.length() > 0) {
        cmd.trim();
        // procesar cmd
        cmd = "";
      }
    } else {
      cmd += c;   // seguir acumulando
    }
  }
}
```

Snippet: `aserialbuffer`. Este patrón funciona en los tres modos, así que
conviene usarlo siempre.

---

## Cerrar bien

`stop_serial_monitor.ps1` no mata por nombre de proceso. Matar todo lo que se
llame `pio` o `python` tumbaría compilaciones en curso. Hace tres pasadas:

1. **Árbol de procesos del PID registrado.** Consulta `Win32_Process` por
   `ParentProcessId` de forma recursiva y mata los hijos antes que el padre. Sin
   esto, matar el PowerShell contenedor deja vivo al `pio` hijo, que **sigue
   reteniendo el COM** — y el siguiente upload falla sin motivo aparente.
2. **Barrido por línea de comando.** Busca cualquier `device monitor` asociado a
   este workspace o a este puerto, por si quedó algo huérfano de una sesión
   anterior.
3. **Verificación real.** Abre y cierra el puerto con
   `System.IO.Ports.SerialPort`. Si no puede, avisa en vez de mentir diciendo que
   está libre.

También limpia los lanzadores `run_AG_Serial_*.ps1` y cualquier tarea programada
`AG_Serial_*` que hubiera quedado colgada.

---

## Configuraciones que hacen falta

En `settings.json` del IDE:

```json
"platformio-ide.forceUploadAndMonitor": false,
"terminal.integrated.shellIntegration.enabled": false,
"terminal.integrated.defaultProfile.windows": "AG PowerShell (clean)"
```

- La primera evita que la extensión de PlatformIO abra su propio monitor fantasma
  durante la subida y provoque un *Access denied*.
- Las otras dos arreglan el segundo bug: sin shell integration, el agente recibe
  correctamente la señal de fin de sus propios comandos.

---

## Orden que nunca hay que romper

```
cerrar monitor  ->  compilar  ->  subir  ->  reabrir monitor
```

Eso es exactamente lo que hace `flash_watch.ps1`, y es el motivo de que exista.
Si alguna vez ves *Access is denied* al subir, es que algo se saltó el primer
paso.
