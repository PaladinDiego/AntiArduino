[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$LogFile,
    [string]$WorkDir,
    [switch]$DryRun,
    [switch]$QuickSmoke,
    [switch]$Force,
    [string[]]$Platforms = @("atmelavr", "atmelsam", "espressif8266", "espressif32", "ststm32", "raspberrypi")
)

. (Join-Path $PSScriptRoot "00-Common.ps1")

Write-Log "Generando reporte de instalacion..." "INFO"

if ($DryRun) {
    Write-Log "[DRYRUN] Escribiria el reporte en SETUP_EMBEDDED.md." "INFO"
    exit 0
}

$ReportPath = Join-Path $WorkDir "SETUP_EMBEDDED.md"
$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Consultas dinámicas en tiempo de ejecución
$PioVer = try { (& pio --version 2>&1) -join " " } catch { "No detectado" }
$PyVer = try { (& python --version 2>&1) -join " " } catch { "No detectado" }

# Verificación física en disco
$ExtBase = Join-Path $env:USERPROFILE ".antigravity-ide\extensions"
$HasClangd = (Get-ChildItem -Path $ExtBase -Filter "*clangd*" -Directory -ErrorAction SilentlyContinue).Count -gt 0
$HasPIO = (Get-ChildItem -Path $ExtBase -Filter "*platformio-ide*" -Directory -ErrorAction SilentlyContinue).Count -gt 0

$StatusClangd = if ($HasClangd) { "Detectada en disco ($ExtBase)" } else { "No detectada" }
$StatusPIO = if ($HasPIO) { "Detectada en disco ($ExtBase)" } else { "No detectada" }

$Content = @"
# Reporte de Instalación: Antigravity Embedded

**Fecha:** $Date
**Workspace:** $WorkDir

## Entorno Subyacente
- **PlatformIO:** $PioVer
- **Python:** $PyVer

## Estado de Extensiones (Verificación física)
- **vscode-clangd:** $StatusClangd
- **platformio-ide:** $StatusPIO

## Estructura del Workspace
- \`.vscode\` -> Lanzadores de debug, tareas y snippets.
- \`scripts\` -> Orquestación del Monitor Serial.
- \`.antigravity-embedded\` -> Logs y Plotter.
- \`AGENTS.md\` -> Contexto mandatorio para el Agente IA.

## Reversión
Si algo falla, ejecuta \`.\undo.ps1 -RemoveExtensions -RemovePlatforms\` desde PowerShell.
"@

Set-Content -Path $ReportPath -Value $Content -Encoding Ascii -Force
Write-Log "SETUP_EMBEDDED.md generado dinamicamente en $ReportPath." "OK"
