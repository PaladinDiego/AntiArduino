[CmdletBinding()]
param(
    [string]$WorkDir = "C:\embedded-dev",
    [switch]$DryRun,
    [switch]$QuickSmoke,
    [switch]$SkipSmokeTests,
    [switch]$Force,
    [string[]]$Platforms = @("atmelavr", "atmelsam", "espressif8266", "espressif32", "ststm32", "raspberrypi"),
    [switch]$Resume,
    [string[]]$OnlyModules
)

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$SrcDir = Join-Path $RepoRoot "src"
$LogFile = Join-Path $RepoRoot "setup.log"
$StateFile = Join-Path $RepoRoot ".deploy-state.json"

if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
if (Test-Path $LogFile) { Remove-Item $LogFile -Force }

. (Join-Path $SrcDir "00-Common.ps1")

Write-Log "Iniciando despliegue de Antigravity Embedded..." "INFO"
if ($DryRun) { Write-Log "[DRYRUN] Modo simulacion activo. Ningun archivo sera modificado." "WARN" }
if ($Resume) { Write-Log "Modo -Resume activo: se intentara saltar 02/04/05 si su fingerprint no cambio desde la ultima corrida exitosa." "INFO" }

# --- Estado incremental: solo para modulos con costo recurrente real ---
# 02 (spawnea el IDE en modo headless para listar extensiones), 04 (pip install
# incondicional de dependencias de espressif32) y 05 (compila firmware real,
# ~140s sin -QuickSmoke) son los unicos con costo medido que justifica cache.
# El resto (00,01,03,06,07) ya es barato por su propio diseno interno
# (Test-Path / hash-compare por archivo) y siempre corre en vivo: cachearlos
# no ahorraria tiempo real y solo agregaria estado que puede desincronizarse.
$CacheableModules = @("02-InstallExtensions", "04-InstallPlatforms", "05-RunSmokeTests")

function Get-ModuleFingerprint {
    param(
        [string]$ScriptPath,
        [string]$CommonPath,
        [hashtable]$Params = @{},
        [string]$DependsOnFingerprint = ""
    )
    $Parts = New-Object System.Collections.Generic.List[string]
    $Parts.Add((Get-FileHash -Path $ScriptPath -Algorithm SHA256).Hash)
    $Parts.Add((Get-FileHash -Path $CommonPath -Algorithm SHA256).Hash)
    foreach ($Key in ($Params.Keys | Sort-Object)) {
        $Value = $Params[$Key]
        if ($Value -is [array]) { $Value = ($Value -join ",") }
        $Parts.Add("$Key=$Value")
    }
    if ($DependsOnFingerprint) { $Parts.Add("DependsOn=$DependsOnFingerprint") }

    $Joined = $Parts -join "|"
    $Sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $HashBytes = $Sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Joined))
        return ([System.BitConverter]::ToString($HashBytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $Sha256.Dispose()
    }
}

function Read-DeployState {
    param([string]$Path)
    $Empty = @{ SchemaVersion = 1; Modules = @{} }
    if (-not (Test-Path $Path)) { return $Empty }
    try {
        $Obj = Get-Content -Path $Path -Raw -Encoding Ascii | ConvertFrom-Json
        if ($Obj.SchemaVersion -ne 1) {
            Write-Log "Estado incremental con SchemaVersion desconocida ($($Obj.SchemaVersion)). Ignorando cache existente." "WARN"
            return $Empty
        }
        $StateModules = @{}
        if ($Obj.Modules) {
            foreach ($Prop in $Obj.Modules.psobject.properties) {
                $StateModules[$Prop.Name] = @{
                    Fingerprint = [string]$Prop.Value.Fingerprint
                    Status      = [string]$Prop.Value.Status
                    LastRunUtc  = [string]$Prop.Value.LastRunUtc
                }
            }
        }
        return @{ SchemaVersion = 1; Modules = $StateModules }
    } catch {
        Write-Log "No se pudo leer .deploy-state.json ($_). Ignorando cache existente." "WARN"
        return $Empty
    }
}

function Write-DeployStateModule {
    param([string]$Path, [string]$ModuleKey, [string]$Fingerprint, [string]$Status)
    $StateOnDisk = Read-DeployState -Path $Path
    $StateOnDisk.Modules[$ModuleKey] = @{
        Fingerprint = $Fingerprint
        Status      = $Status
        LastRunUtc  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $Json = @{ SchemaVersion = $StateOnDisk.SchemaVersion; Modules = $StateOnDisk.Modules } | ConvertTo-Json -Depth 6
    Set-Content -Path $Path -Value $Json -Encoding Ascii -Force
}

$Modules = Get-ChildItem -Path $SrcDir -Filter "*.ps1" | Where-Object { $_.Name -ne "00-Common.ps1" } | Sort-Object Name

# --- Resolucion y validacion de -OnlyModules ---
$OnlyModulesSet = $null
if ($OnlyModules) {
    $ValidKeys = $Modules | ForEach-Object { $_.BaseName }
    $Resolved = @()
    foreach ($Sel in $OnlyModules) {
        $Match = $ValidKeys | Where-Object { $_ -eq $Sel -or $_ -like "$Sel-*" } | Select-Object -First 1
        if (-not $Match) {
            Write-Log "Modulo desconocido en -OnlyModules: '$Sel'. Modulos validos: $($ValidKeys -join ', ')" "FAIL"
            exit 1
        }
        $Resolved += $Match
    }
    $OnlyModulesSet = @($Resolved | Select-Object -Unique)
    Write-Log "Modo -OnlyModules activo: se ejecutaran exclusivamente $($OnlyModulesSet -join ', ') (ningun otro modulo corre, ni siquiera 00-Preflight)." "WARN"
}

$State = if ($Resume) { Read-DeployState -Path $StateFile } else { $null }
$ModuleFingerprints = @{}

foreach ($Module in $Modules) {
    $ModuleKey = $Module.BaseName

    if ($SkipSmokeTests -and $Module.Name -like "*05-RunSmokeTests*") {
        Write-Log "Saltando $($Module.Name) por flag -SkipSmokeTests" "INFO"
        continue
    }

    if ($OnlyModulesSet -and ($OnlyModulesSet -notcontains $ModuleKey)) {
        continue
    }
    $IsExplicitlySelected = [bool]($OnlyModulesSet -and ($OnlyModulesSet -contains $ModuleKey))
    $IsCacheable = $CacheableModules -contains $ModuleKey

    $Fingerprint = $null
    if ($IsCacheable) {
        $ParamsForFingerprint = @{}
        if ($ModuleKey -eq "04-InstallPlatforms") {
            $ParamsForFingerprint["Platforms"] = $Platforms
        } elseif ($ModuleKey -eq "05-RunSmokeTests") {
            $ParamsForFingerprint["Platforms"] = $Platforms
            $ParamsForFingerprint["QuickSmoke"] = [bool]$QuickSmoke
        }

        $DependsOn = ""
        if ($ModuleKey -eq "05-RunSmokeTests" -and $ModuleFingerprints.ContainsKey("04-InstallPlatforms")) {
            # 05 compila usando las plataformas/toolchains que 04 instala (incluidas
            # las dependencias de Python de espressif32). Si 04 cambia de forma que
            # afecta lo que queda instalado, el resultado cacheado de 05 ya no es
            # confiable aunque el propio script de 05 no haya cambiado -- por eso
            # el fingerprint de 04 se pliega dentro del de 05. Esta es la unica
            # cadena de dependencia modelada; no hay grafo generico de dependencias.
            $DependsOn = $ModuleFingerprints["04-InstallPlatforms"]
        }

        $Fingerprint = Get-ModuleFingerprint -ScriptPath $Module.FullName -CommonPath (Join-Path $SrcDir "00-Common.ps1") -Params $ParamsForFingerprint -DependsOnFingerprint $DependsOn
        $ModuleFingerprints[$ModuleKey] = $Fingerprint
    }

    if ($Resume -and $IsCacheable -and -not $IsExplicitlySelected) {
        if ($Force) {
            Write-Log "$($Module.Name): -Force activo, ignorando cache." "INFO"
        } else {
            $Cached = $State.Modules[$ModuleKey]
            if ($Cached -and $Cached.Status -eq "Success" -and $Cached.Fingerprint -eq $Fingerprint) {
                Write-Log "[SKIP] $($Module.Name) ya se completo con exito (fingerprint sin cambios: $($Fingerprint.Substring(0,12))...)." "OK"
                continue
            } elseif ($Cached) {
                Write-Log "$($Module.Name): fingerprint cambio desde la ultima corrida exitosa. Re-ejecutando." "INFO"
            } else {
                Write-Log "$($Module.Name): sin estado previo exitoso. Ejecutando." "INFO"
            }
        }
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

    if ($IsCacheable -and -not $DryRun) {
        Write-DeployStateModule -Path $StateFile -ModuleKey $ModuleKey -Fingerprint $Fingerprint -Status "Success"
    }
}
Write-Log "=== Despliegue completado ===" "OK"
