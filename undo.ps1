<#
.SYNOPSIS
    Revierte los cambios hechos por Deploy-Environment.ps1
.EXAMPLE
    .\undo.ps1 -WhatIf
    .\undo.ps1 -RemovePlatforms -RemoveExtensions
#>
[CmdletBinding()]
param(
    [string]$WorkDir = "C:\embedded-dev",
    [switch]$RemovePlatforms,
    [switch]$RemoveExtensions,
    [switch]$WhatIf
)

$LogFile = Join-Path $PSScriptRoot "undo.log"

. (Join-Path $PSScriptRoot "src\00-Common.ps1")

function Undo-Log {
    param([string]$Message, [string]$Type = "INFO")
    if ($WhatIf) { $Message = "[WHAT-IF] $Message" }
    Write-Log $Message $Type
}

Undo-Log "Iniciando reversión del entorno Antigravity Embedded..." "INFO"

# 1. Restaurar settings.json
$AppDataDir = Join-Path $env:APPDATA "Antigravity IDE\User"
$SettingsTarget = Join-Path $AppDataDir "settings.json"
$BakPath = Get-ChildItem -Path $AppDataDir -Filter "settings.json.bak_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($BakPath) {
    Undo-Log "Restaurando settings.json desde: $($BakPath.Name)" "INFO"
    if (-not $WhatIf) { Copy-Item -Path $BakPath.FullName -Destination $SettingsTarget -Force }
}

# 2. Eliminar .clangd del Workspace
$ClangdTarget = Join-Path $WorkDir ".clangd"
if (Test-Path $ClangdTarget) {
    Undo-Log "Eliminando .clangd de $WorkDir" "INFO"
    if (-not $WhatIf) { Remove-Item -Path $ClangdTarget -Force }
}

# 3. Revertir PATH del Usuario
$PioDir = Join-Path $env:USERPROFILE ".platformio\penv\Scripts"
$UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")

if ($UserPath -match [regex]::Escape($PioDir)) {
    Undo-Log "Removiendo penv\Scripts del PATH persistente del usuario..." "INFO"
    if (-not $WhatIf) {
        $Paths = $UserPath -split ';' | Where-Object { $_ -ne $PioDir -and $_ -ne "" }
        $NewPath = $Paths -join ';'
        [System.Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
        Undo-Log "PATH restaurado. (Requiere reiniciar la terminal para verse reflejado)" "WARN"
    }
}

# 4. Remover Extensiones
if ($RemoveExtensions) {
    Undo-Log "Desinstalando extensiones del IDE..." "INFO"
    
    if (-not $WhatIf) {
        $ExtBase = Join-Path $env:USERPROFILE ".antigravity-ide\extensions"
        
        $ExtBak = Get-ChildItem -Path $ExtBase -Filter "extensions.json.bak_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($ExtBak) {
            Undo-Log "Evidencia de fallback manual detectada. Restaurando extensions.json..." "INFO"
            Copy-Item -Path $ExtBak.FullName -Destination (Join-Path $ExtBase "extensions.json") -Force
            
            $ManualExt = Get-ChildItem -Path $ExtBase -Filter "platformio.platformio-ide-*" -Directory
            foreach ($Dir in $ManualExt) {
                Undo-Log "Eliminando carpeta de extensión manual: $($Dir.Name)" "INFO"
                Remove-Item -Path $Dir.FullName -Recurse -Force
            }
        }
        
        try {
            $AgCmd = Resolve-AntigravityProfile
            Start-Process -FilePath $AgCmd -ArgumentList "--uninstall-extension llvm-vs-code-extensions.vscode-clangd" -Wait -NoNewWindow
            Start-Process -FilePath $AgCmd -ArgumentList "--uninstall-extension platformio.platformio-ide" -Wait -NoNewWindow
        } catch {
            Undo-Log "Perfil de Antigravity IDE no encontrado. Saltando desinstalación estándar." "WARN"
        }
    }
}

# 5. Remover Plataformas
if ($RemovePlatforms) {
    Undo-Log "Desinstalando plataformas globales de PlatformIO..." "INFO"
    $Platforms = @("atmelavr", "atmelsam", "espressif8266", "espressif32", "ststm32", "raspberrypi")
    if (-not $WhatIf) {
        foreach ($Plat in $Platforms) {
            Start-Process -FilePath "pio.exe" -ArgumentList "pkg uninstall -g -p $Plat" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
    }
}

Undo-Log "=== Reversión completada ===" "OK"
