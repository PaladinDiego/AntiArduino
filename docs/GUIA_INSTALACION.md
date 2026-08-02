# Guía de instalación paso a paso

Para alguien que nunca ha usado PlatformIO ni PowerShell. Si ya sabes, ve directo
al [README](../README.md).

---

## Paso 0 — Comprueba que tienes lo necesario

Abre el menú Inicio, escribe `powershell`, ábrelo y pega esto:

```powershell
python --version; git --version
```

Deberías ver algo como `Python 3.12.1` y `git version 2.45.0`.

**Si dice "no se reconoce el término python":**
1. Ve a <https://www.python.org/downloads/>
2. Descarga la versión para Windows.
3. En la primera pantalla del instalador, **marca la casilla
   "Add python.exe to PATH"** (abajo del todo). Esto es lo importante.
4. Instala, cierra PowerShell, ábrelo de nuevo y vuelve a probar.

**Si falta git**, no es bloqueante: la instalación funcionará igual, pero algunas
librerías de Arduino que se descargan desde repositorios no se podrán instalar.
Lo tienes en <https://git-scm.com/download/win>.

---

## Paso 1 — Copia la carpeta

Copia toda la carpeta `Antigravity-Setup-v1.0` a donde prefieras: el escritorio,
un USB, Descargas. Da igual, pero **cópiala entera**, no solo el `.bat`.

---

## Paso 2 — Doble clic en `setup.bat`

Se abrirá una ventana negra que empieza así:

```
  ================================================================
   ANTIGRAVITY IDE - SETUP DE ENTORNO EMBEBIDO  v1.0.0
   Arduino / ESP32 / ESP8266 / STM32 / RP2040
  ================================================================

   Workspace destino : C:\embedded-dev
   Tiempo estimado   : 15-20 minutos
```

**No cierres esa ventana.** Puedes minimizarla y seguir con lo tuyo.

### Si Windows muestra un aviso azul ("Windows protegió su PC")

Haz clic en **"Más información"** y luego en **"Ejecutar de todas formas"**.
Aparece porque el archivo viene de internet, no porque sea peligroso. Si te
quedas más tranquila, abre `antigravity-setup.ps1` con el Bloc de notas: es texto
plano y puedes leerlo entero.

---

## Paso 3 — Lee lo que va pasando

Cada línea lleva una etiqueta:

| Etiqueta | Significado |
|---|---|
| `[OK]` | Hecho, o ya estaba hecho |
| `[INFO]` | Solo te está contando algo |
| `[>>]` | Empezando algo que tarda |
| `[WARN]` | Algo no ideal, pero la instalación sigue |
| `[FAIL]` | Algo falló; al final te dirá qué hacer |

Los tramos largos son:
- **PlatformIO Core**, 2–3 minutos
- **Plataformas de hardware**, 6–10 minutos (es lo que más tarda)
- **Prueba de compilación de ESP32**, unos 140 segundos

---

## Paso 4 — Comprueba el resultado

Al final verás un resumen. Lo que quieres leer es:

```
   Estado: INSTALACION COMPLETA Y VERIFICADA
```

Si dice **INSTALACION CON PROBLEMAS**, mira
[TROUBLESHOOTING.md](TROUBLESHOOTING.md). En casi todos los casos basta con
volver a ejecutar `setup.bat`.

---

## Paso 5 — Reinicia Antigravity IDE

Ciérralo del todo y vuelve a abrirlo. Es obligatorio: las extensiones y la
configuración nueva solo se cargan al arrancar.

**Ojo con cuál abres.** Si tienes dos iconos parecidos, el bueno es
**"Antigravity IDE"**. El instalador te dice cuál eligió; búscalo en el resumen:

```
[OK] IDE : Antigravity IDE v1.52.0
```

Ánclalo a la barra de tareas para no volver a confundirte.

---

## Paso 6 — Abre la carpeta de trabajo

En el IDE: **File > Open Folder** y elige `C:\embedded-dev`.

> **Importante:** no abras `C:\Users\TuNombre` entera como espacio de trabajo. Si
> lo haces, clangd intentará analizar todos los archivos de código de tu disco,
> marcará miles de errores falsos y consumirá CPU sin parar. Abre siempre la
> carpeta del proyecto concreto.

---

## Paso 7 — Tu primer proyecto

1. Copia la plantilla que corresponda a tu placa:

   ```powershell
   mkdir C:\embedded-dev\mi-proyecto
   copy C:\embedded-dev\templates\platformio-uno.ini C:\embedded-dev\mi-proyecto\platformio.ini
   mkdir C:\embedded-dev\mi-proyecto\src
   ```

2. Crea `src\main.cpp`. En el editor, escribe `askeleton` y pulsa Tab: el snippet
   te pone el esqueleto entero.

3. Conecta la placa y ejecuta la tarea **PIO: Detectar placa y driver**
   (`Ctrl+Shift+P` → *Tasks: Run Task*). Te dirá el puerto, el chip y si
   necesitas driver.

4. `Ctrl+R` para compilar. `Ctrl+U` para subir. `Ctrl+Alt+M` para ver el monitor
   serial.

---

## Lo que hay que recordar

**Un puerto COM solo lo puede abrir un programa a la vez.** Si el monitor está
abierto y pulsas `Ctrl+U`, la subida falla con *"Access is denied"*. Por eso
existe `Ctrl+Alt+F` (Flash & Watch): cierra el monitor, sube y lo reabre, en ese
orden.

**Si el editor subraya en rojo código que compila bien**, pulsa `Ctrl+Shift+I`.
La base de datos de IntelliSense es distinta para cada placa, y al cambiar de
placa hay que regenerarla.

**Si escribes en el monitor serial y llegan palabras cortadas**, tu código
Arduino está usando `Serial.readStringUntil()`. Usa el snippet `aserialbuffer`,
que lee carácter por carácter. La explicación está en
[ARQUITECTURA_SERIAL_MONITOR.md](ARQUITECTURA_SERIAL_MONITOR.md).
