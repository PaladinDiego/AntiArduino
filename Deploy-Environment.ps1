[CmdletBinding()]
param(
    [string]$WorkDir = "C:\embedded-dev",
    [switch]$DryRun,
    [switch]$QuickSmoke,
    [switch]$SkipSmokeTests,
    [switch]$Force,
    [string[]]$Platforms = @("atmelavr", "atmelsam", "espressif8266", "espressif32", "ststm32", "raspberrypi")
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$SrcDir = Join-Path $RepoRoot "src"
$LogFile = Join-Path $RepoRoot "setup.log"

if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

. (Join-Path $SrcDir "00-Common.ps1")

Write-Log "Iniciando despliegue de Antigravity Embedded..." "INFO"
if ($DryRun) { Write-Log "[DRYRUN] Modo simulacion activo. Ningun archivo sera modificado." "WARN" }

$Modules = Get-ChildItem -Path $SrcDir -Filter "*.ps1" | Where-Object { $_.Name -ne "00-Common.ps1" } | Sort-Object Name

foreach ($Module in $Modules) {
    if ($SkipSmokeTests -and $Module.Name -like "*05-RunSmokeTests*") {
        Write-Log "Saltando $($Module.Name) por flag -SkipSmokeTests" "INFO"
        continue
    }

    Write-Log "=== Ejecutando modulo: $($Module.Name) ===" "INFO"
    try {
        & $Module.FullName -RepoRoot $RepoRoot -LogFile $LogFile -WorkDir $WorkDir `
            -DryRun:$DryRun -QuickSmoke:$QuickSmoke -Force:$Force -Platforms $Platforms
        
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
            Write-Log "El modulo $($Module.Name) fallo ($LASTEXITCODE)." "FAIL"
            exit 1
        }
    } catch {
        Write-Log "Error critico en $($Module.Name): $_" "FAIL"
        exit 1
    }
}
Write-Log "=== Despliegue completado ===" "OK"
