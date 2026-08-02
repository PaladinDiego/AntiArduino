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

$PioDir = Join-Path $env:USERPROFILE ".platformio\penv\Scripts"
$PioExe = Join-Path $PioDir "pio.exe"

if ((-not (Test-Path $PioExe)) -or $Force) {
    if ($DryRun) {
        Write-Log "[DRYRUN] Descargaria e instalaria PlatformIO Core." "INFO"
    } else {
        Write-Log "Descargando instalador de PlatformIO Core..." "WARN"
        $InstallerPath = Join-Path $env:TEMP "get-platformio.py"
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py" -OutFile $InstallerPath -UseBasicParsing
        
        $Proc = Start-Process -FilePath "python" -ArgumentList $InstallerPath -Wait -NoNewWindow -PassThru
        if ($Proc.ExitCode -ne 0 -or -not (Test-Path $PioExe)) {
            Write-Log "Fallo la instalacion de PlatformIO Core." "FAIL"
            exit 1
        }
        Write-Log "PlatformIO Core instalado correctamente." "OK"
    }
} else {
    Write-Log "PlatformIO Core ya esta instalado en $PioExe." "OK"
}

# 1. PATH Persistente (Usuario)
$UserPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notmatch [regex]::Escape($PioDir)) {
    if ($DryRun) {
        Write-Log "[DRYRUN] Inyectaria penv\Scripts al PATH persistente del usuario." "INFO"
    } else {
        Write-Log "Inyectando penv\Scripts al PATH persistente del usuario..." "INFO"
        [System.Environment]::SetEnvironmentVariable("PATH", "$PioDir;$UserPath", "User")
    }
}

# 2. PATH en Sesion Actual
if ($env:PATH -notmatch [regex]::Escape($PioDir)) {
    if ($DryRun) {
        Write-Log "[DRYRUN] Añadiria penv\Scripts al PATH de la sesion actual." "INFO"
    } else {
        Write-Log "Añadiendo penv\Scripts al PATH de la sesion actual." "INFO"
        $env:PATH = "$PioDir;$env:PATH"
    }
}
