# Antigravity IDE — Setup de Entorno Embebido

Convierte una instalación limpia de **Antigravity IDE** en un entorno completo de
desarrollo embebido (Arduino, ESP32, ESP8266, STM32, RP2040) de forma automatizada.

---

## Uso rápido

1. Clona este repositorio o descarga el contenido.
2. Ejecuta **`setup.bat`** (o `.\Deploy-Environment.ps1` desde PowerShell).
3. Espera a que los módulos finalicen (`[OK]`).
4. Al terminar, **reinicia Antigravity IDE** y abre `C:\embedded-dev` como carpeta de trabajo (*File > Open Folder*).

---

## Opciones avanzadas (CLI Flags)

```powershell
.\Deploy-Environment.ps1 -DryRun
.\Deploy-Environment.ps1 -QuickSmoke
.\Deploy-Environment.ps1 -SkipSmokeTests
.\Deploy-Environment.ps1 -Force
.\Deploy-Environment.ps1 -WorkDir "D:\embedded"
.\Deploy-Environment.ps1 -Platforms atmelavr,espressif32
```

---

## Qué instala

**Núcleo**
- PlatformIO Core (independiente de la extensión) + PATH de usuario
- **Nota de Riesgo:** Si la extensión de PlatformIO falla en el marketplace, el script usará un fallback manual (descarga de VSIX por GitHub API). Aunque se registre en `extensions.json`, requiere validación visual humana en el IDE.
- Extensión PlatformIO IDE (Open VSX → VSIX → parche del manifiesto)
- Extensión clangd con `--query-driver` para todos los toolchains
- 6 plataformas: atmelavr, atmelsam, espressif8266, espressif32, ststm32, raspberrypi

---

## Decisiones de Diseño / Cambios desde v1.0

- **Integridad (Checksums):** Los archivos `checksums.txt` y `make-checksums.ps1` del paquete v1.0 han sido deprecados. La integridad del paquete está delegada a Git (hashes de los commits).
- **Estructura Modular:** Lógica dividida en scripts numerados bajo `src/` orquestados secuencialmente.
- **Reversibilidad:** Inluido `undo.ps1` para remover los componentes instalados y restaurar backups de configuración.
