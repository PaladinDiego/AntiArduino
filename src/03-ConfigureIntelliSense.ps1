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

# 1. Configuración global .clangd
$ClangdTemplate = Join-Path $RepoRoot "config\.clangd.template"
$ClangdTarget = Join-Path $WorkDir ".clangd"

if (Test-Path $ClangdTemplate) {
    if ($DryRun) {
        Write-Log "[DRYRUN] Copiaria .clangd a $WorkDir" "INFO"
    } else {
        $ShouldCopyClangd = $true
        if (Test-Path $ClangdTarget) {
            $SourceHash = (Get-FileHash $ClangdTemplate -Algorithm SHA256).Hash
            $TargetHash = (Get-FileHash $ClangdTarget -Algorithm SHA256).Hash
            if ($SourceHash -eq $TargetHash) { $ShouldCopyClangd = $false }
        }

        if ($ShouldCopyClangd) {
            if (Test-Path $ClangdTarget) { Backup-File $ClangdTarget }
            Copy-Item -Path $ClangdTemplate -Destination $ClangdTarget -Force
            Write-Log ".clangd instalado en el workspace ($WorkDir)." "OK"
        } else {
            Write-Log ".clangd sin cambios. Backup omitido." "OK"
        }
    }
}

# 2. Parametrización dinámica
$AgCmd = Resolve-AntigravityProfile
$AppDataDir = Join-Path $env:APPDATA "Antigravity IDE\User"

$SettingsTarget = Join-Path $AppDataDir "settings.json"
$SettingsTemplate = Join-Path $RepoRoot "config\settings.json.template"

$Content = Get-Content $SettingsTemplate -Raw -Encoding Ascii
$PioDir = Join-Path $env:USERPROFILE ".platformio\penv\Scripts"
$Content = $Content -replace "__PIO_SCRIPTS__", $PioDir.Replace('\', '\\')

$ExtDir = Join-Path $env:USERPROFILE ".antigravity-ide\extensions"
$ClangdExePath = ""
$ClangdExt = Get-ChildItem -Path $ExtDir -Filter "llvm-vs-code-extensions.vscode-clangd-*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
if ($ClangdExt) {
    $Exe = Get-ChildItem -Path $ClangdExt.FullName -Filter "clangd.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Exe) { $ClangdExePath = $Exe.FullName.Replace('\', '\\') }
}

if ($ClangdExePath) {
    $Content = $Content -replace "__CLANGD_PATH_LINE__", "`"clangd.path`": `"$ClangdExePath`","
} else {
    $Content = $Content -replace "__CLANGD_PATH_LINE__\r?\n?", ""
}

$QueryDrivers = "$env:USERPROFILE\.platformio\packages\toolchain-*\bin\*-gcc.exe".Replace('\', '\\')
$Content = $Content -replace "__QUERY_DRIVER__", $QueryDrivers

if ($DryRun) {
    Write-Log "[DRYRUN] Configuraria settings.json, tasks.json, launch.json y keybindings.json." "INFO"
    return
}

# 3. Fusión de settings.json (o sobrescritura dura si -Force)
Write-Log "Procesando settings.json..." "INFO"
$SourceObj = Parse-JsonC $Content

if (Test-Path $SettingsTarget) {
    if ($Force) {
        Write-Log "Modo -Force activo: Sobrescribiendo settings.json..." "WARN"
        $FinalObj = $SourceObj
    } else {
        $TargetObj = Parse-JsonC (Get-Content $SettingsTarget -Raw -Encoding Ascii)
        $OwnedKeys = @("clangd.path", "clangd.arguments", "platformio-ide.activateOnlyOnPlatformIOProject", "C_Cpp.intelliSenseEngine")

        foreach ($Prop in $SourceObj.psobject.properties) {
            if ($OwnedKeys -contains $Prop.Name) {
                if ($TargetObj.psobject.properties.Match($Prop.Name).Count -eq 0) {
                    $TargetObj | Add-Member -MemberType NoteProperty -Name $Prop.Name -Value $Prop.Value
                } else {
                    $TargetObj.($Prop.Name) = $Prop.Value
                }
            } else {
                if ($TargetObj.psobject.properties.Match($Prop.Name).Count -eq 0) {
                    $TargetObj | Add-Member -MemberType NoteProperty -Name $Prop.Name -Value $Prop.Value
                }
            }
        }
        $FinalObj = $TargetObj
    }
} else {
    if (-not (Test-Path $AppDataDir)) { New-Item -ItemType Directory -Path $AppDataDir -Force | Out-Null }
    $FinalObj = $SourceObj
}

$NewJsonStr = $FinalObj | ConvertTo-Json -Depth 10
try {
    $null = $NewJsonStr | ConvertFrom-Json

    $ShouldWrite = $true
    if (Test-Path $SettingsTarget) {
        $TempCompare = Join-Path $env:TEMP "settings_compare_$(Get-Random).json"
        Set-Content -Path $TempCompare -Value $NewJsonStr -Encoding Ascii -Force
        $NewHash = (Get-FileHash $TempCompare -Algorithm SHA256).Hash
        $CurrentHash = (Get-FileHash $SettingsTarget -Algorithm SHA256).Hash
        Remove-Item -Path $TempCompare -Force
        if ($NewHash -eq $CurrentHash) { $ShouldWrite = $false }
    }

    if ($ShouldWrite) {
        if (Test-Path $SettingsTarget) { Backup-File $SettingsTarget }
        Set-Content -Path $SettingsTarget -Value $NewJsonStr -Encoding Ascii -Force
        Write-Log "settings.json configurado correctamente." "OK"
    } else {
        Write-Log "settings.json sin cambios. Backup omitido." "OK"
    }
} catch {
    Write-Log "Error al validar settings.json. Restaurando..." "FAIL"
    $BakPath = Get-ChildItem -Path $AppDataDir -Filter "settings.json.bak_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($BakPath) { Copy-Item -Path $BakPath.FullName -Destination $SettingsTarget -Force }
    exit 1
}

# 4. Fusión de tasks.json y launch.json al workspace
$VsCodeDir = Join-Path $WorkDir ".vscode"
if (-not (Test-Path $VsCodeDir)) { New-Item -ItemType Directory -Path $VsCodeDir -Force | Out-Null }

$MergeConfigs = @{
    "tasks.json" = "label"
    "launch.json" = "name"
}

foreach ($Config in $MergeConfigs.GetEnumerator()) {
    $File = $Config.Name
    $KeyName = $Config.Value
    $Source = Join-Path $RepoRoot "config\$File"
    $Target = Join-Path $VsCodeDir $File
    
    if (Test-Path $Source) {
        Write-Log "Procesando $File..." "INFO"
        $RawContent = Get-Content $Source -Raw -Encoding Ascii
        $RawContent = $RawContent -replace "__PIO_EXE__", (Join-Path $PioDir "pio.exe").Replace('\', '\\')
        $RawContent = $RawContent -replace "__PIO_PYTHON__", (Join-Path $PioDir "python.exe").Replace('\', '\\')
        $SourceObj = Parse-JsonC $RawContent
        
        if (Test-Path $Target) {
            if ($Force) {
                Write-Log "Modo -Force activo: Sobrescribiendo $File..." "WARN"
                $FinalObj = $SourceObj
            } else {
                $TargetObj = Parse-JsonC (Get-Content $Target -Raw -Encoding Ascii)
                $ArrayProp = if ($File -eq "tasks.json") { "tasks" } else { "configurations" }
                $MergedArray = @()
                if ($TargetObj.$ArrayProp) { $MergedArray = @($TargetObj.$ArrayProp) }
                
                if ($SourceObj.$ArrayProp) {
                    foreach ($NewItem in @($SourceObj.$ArrayProp)) {
                        $Exists = $false
                        foreach ($TgtItem in $MergedArray) {
                            if ($TgtItem.$KeyName -eq $NewItem.$KeyName) {
                                $Exists = $true
                                Write-Log "La entrada '$($NewItem.$KeyName)' ya existe en $File. Saltando." "WARN"
                                break
                            }
                        }
                        if (-not $Exists) { $MergedArray += $NewItem }
                    }
                }
                $TargetObj | Add-Member -MemberType NoteProperty -Name $ArrayProp -Value $MergedArray -Force
                $FinalObj = $TargetObj
            }
        } else {
            $FinalObj = $SourceObj
        }
        
        $NewJsonStr = $FinalObj | ConvertTo-Json -Depth 10
        try {
            $null = $NewJsonStr | ConvertFrom-Json

            $ShouldWrite = $true
            if (Test-Path $Target) {
                $TempCompare = Join-Path $env:TEMP "$($File)_compare_$(Get-Random).json"
                Set-Content -Path $TempCompare -Value $NewJsonStr -Encoding Ascii -Force
                $NewHash = (Get-FileHash $TempCompare -Algorithm SHA256).Hash
                $CurrentHash = (Get-FileHash $Target -Algorithm SHA256).Hash
                Remove-Item -Path $TempCompare -Force
                if ($NewHash -eq $CurrentHash) { $ShouldWrite = $false }
            }

            if ($ShouldWrite) {
                if (Test-Path $Target) { Backup-File $Target }
                Set-Content -Path $Target -Value $NewJsonStr -Encoding Ascii -Force
                Write-Log "$File configurado." "OK"
            } else {
                Write-Log "$File sin cambios. Backup omitido." "OK"
            }
        } catch {
            Write-Log "Error al validar $File. Restaurando..." "FAIL"
            $BakPath = Get-ChildItem -Path $VsCodeDir -Filter "$File.bak_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($BakPath) { Copy-Item -Path $BakPath.FullName -Destination $Target -Force }
            exit 1
        }
    }
}

# 5. Fusión Idempotente y libre de conflictos para keybindings.json
$KeybindingsTemplate = Join-Path $RepoRoot "config\keybindings.json"
$KeybindingsTarget = Join-Path $AppDataDir "keybindings.json"

if (Test-Path $KeybindingsTemplate) {
    Write-Log "Procesando keybindings.json..." "INFO"
    $NewKeyObj = Parse-JsonC (Get-Content $KeybindingsTemplate -Raw -Encoding Ascii)
    
    if (Test-Path $KeybindingsTarget) {
        if ($Force) {
            Write-Log "Modo -Force activo: Sobrescribiendo keybindings.json..." "WARN"
            $FinalKeyObj = $NewKeyObj
        } else {
            $TargetKeyObj = @(Parse-JsonC (Get-Content $KeybindingsTarget -Raw -Encoding Ascii))
            $MergedArray = $TargetKeyObj
            foreach ($NewKb in @($NewKeyObj)) {
                $Conflict = $false
                $ExactMatch = $false
                foreach ($TgtKb in $MergedArray) {
                    if ($TgtKb.key -eq $NewKb.key) {
                        if ($TgtKb.command -eq $NewKb.command) {
                            $ExactMatch = $true
                        } else {
                            $Conflict = $true
                            Write-Log "Conflicto en atajos: '$($NewKb.key)' ya esta asignado a '$($TgtKb.command)'. Saltando inyeccion." "WARN"
                        }
                        break
                    }
                }
                if (-not $ExactMatch -and -not $Conflict) { $MergedArray += $NewKb }
            }
            $FinalKeyObj = $MergedArray
        }
    } else {
        $FinalKeyObj = $NewKeyObj
    }
    
    $NewKeyStr = $FinalKeyObj | ConvertTo-Json -Depth 10
    try {
        $null = $NewKeyStr | ConvertFrom-Json

        $ShouldWrite = $true
        if (Test-Path $KeybindingsTarget) {
            $TempCompare = Join-Path $env:TEMP "keybindings_compare_$(Get-Random).json"
            Set-Content -Path $TempCompare -Value $NewKeyStr -Encoding Ascii -Force
            $NewHash = (Get-FileHash $TempCompare -Algorithm SHA256).Hash
            $CurrentHash = (Get-FileHash $KeybindingsTarget -Algorithm SHA256).Hash
            Remove-Item -Path $TempCompare -Force
            if ($NewHash -eq $CurrentHash) { $ShouldWrite = $false }
        }

        if ($ShouldWrite) {
            if (Test-Path $KeybindingsTarget) { Backup-File $KeybindingsTarget }
            Set-Content -Path $KeybindingsTarget -Value $NewKeyStr -Encoding Ascii -Force
            Write-Log "keybindings.json configurado correctamente." "OK"
        } else {
            Write-Log "keybindings.json sin cambios. Backup omitido." "OK"
        }
    } catch {
        Write-Log "Error al validar keybindings.json. Restaurando..." "FAIL"
        $BakPath = Get-ChildItem -Path $AppDataDir -Filter "keybindings.json.bak_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($BakPath) { Copy-Item -Path $BakPath.FullName -Destination $KeybindingsTarget -Force }
        exit 1
    }
}
