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

Write-Log "Ejecutando Preflight Checks..." "INFO"

# 1. Arquitectura OS
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Log "Se requiere Windows de 64-bits." "FAIL"
    exit 1
}

# 2. Python: Parseo de Major y Minor como enteros independientes
try {
    $PyVerStr = (& python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1).Trim()
    $Parts = $PyVerStr -split '\.'
    $Major = [int]$Parts[0]
    $Minor = [int]$Parts[1]
    
    if ($Major -lt 3 -or ($Major -eq 3 -and $Minor -lt 9)) {
        Write-Log "Python en el PATH es version $PyVerStr. Se requiere >= 3.9." "FAIL"
        exit 1
    }
    Write-Log "Python version $PyVerStr detectado correctamente." "OK"
} catch {
    Write-Log "Python no esta en el PATH o fallo al ejecutar. Instalalo antes de continuar." "FAIL"
    exit 1
}

# 3. Antigravity IDE Instalado
try {
    $AgCmd = Resolve-AntigravityProfile
    Write-Log "Perfil de Antigravity IDE encontrado." "OK"
} catch {
    Write-Log "El IDE no esta instalado o no se encontro el perfil .antigravity-ide." "FAIL"
    exit 1
}
