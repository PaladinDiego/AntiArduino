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

Write-Log "Iniciando despliegue de assets al workspace ($WorkDir)..." "INFO"

if (-not $DryRun) {
    # Crear directorio de logs del monitor serial
    $LogsDir = Join-Path $WorkDir ".antigravity-embedded\logs"
    if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
    
    # Mover serial_plotter_live.html si existe
    $PlotterSrc = Join-Path $RepoRoot "config\serial_plotter_live.html"
    if (Test-Path $PlotterSrc) {
        Copy-Item -Path $PlotterSrc -Destination (Join-Path $WorkDir ".antigravity-embedded\") -Force
    }
}

$AssetMappings = @{
    "scripts"   = "scripts"
    "templates" = "templates"
    "skills"    = ".agents\skills"
    "snippets"  = ".vscode"
}

foreach ($Map in $AssetMappings.GetEnumerator()) {
    $SourceDir = Join-Path $RepoRoot $Map.Name
    $TargetDir = Join-Path $WorkDir $Map.Value
    
    if (Test-Path $SourceDir) {
        Write-Log "Desplegando $($Map.Name) hacia $($Map.Value)..." "INFO"
        
        if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
        
        $Files = Get-ChildItem -Path $SourceDir -File -Recurse
        foreach ($File in $Files) {
            $RelativePath = $File.FullName.Substring($SourceDir.Length).Trim('\')
            $TargetFile = Join-Path $TargetDir $RelativePath
            
            $TargetParent = Split-Path $TargetFile -Parent
            if (-not (Test-Path $TargetParent)) { New-Item -ItemType Directory -Path $TargetParent -Force | Out-Null }
            
            if (Test-Path $TargetFile) {
                if (-not $Force) {
                    $SourceHash = (Get-FileHash $File.FullName -Algorithm SHA256).Hash
                    $TargetHash = (Get-FileHash $TargetFile -Algorithm SHA256).Hash
                    if ($SourceHash -eq $TargetHash) { continue }
                }
                
                if ($DryRun) {
                    Write-Log "[DRYRUN] Copiaria y reemplazaria $TargetFile." "INFO"
                    continue
                }
                Backup-File $TargetFile
            }
            if (-not $DryRun) { Copy-Item -Path $File.FullName -Destination $TargetFile -Force }
        }
        Write-Log "Directorio $($Map.Name) copiado exitosamente." "OK"
    } else {
        Write-Log "El directorio origen $($Map.Name) no existe en el repositorio." "WARN"
    }
}

# 2. Copiar AGENTS.md (Root File)
$AgentsTemplate = Join-Path $RepoRoot "config\AGENTS.md.template"
$AgentsTarget = Join-Path $WorkDir "AGENTS.md"

if (-not (Test-Path $AgentsTemplate)) {
    Write-Log "AGENTS.md.template no encontrado en config/. Este archivo es critico." "FAIL"
    throw "Falta AGENTS.md.template. Abortando despliegue de assets."
}

if (Test-Path $AgentsTarget) {
    $SrcHash = (Get-FileHash $AgentsTemplate -Algorithm SHA256).Hash
    $TgtHash = (Get-FileHash $AgentsTarget -Algorithm SHA256).Hash
    if ($SrcHash -ne $TgtHash -or $Force) {
        if ($DryRun) {
            Write-Log "[DRYRUN] Actualizaria AGENTS.md en $WorkDir." "INFO"
        } else {
            Backup-File $AgentsTarget
            Copy-Item -Path $AgentsTemplate -Destination $AgentsTarget -Force
            Write-Log "AGENTS.md actualizado en el workspace." "OK"
        }
    }
} else {
    if ($DryRun) {
        Write-Log "[DRYRUN] Copiaria AGENTS.md a $WorkDir." "INFO"
    } else {
        Copy-Item -Path $AgentsTemplate -Destination $AgentsTarget -Force
        Write-Log "AGENTS.md copiado al workspace." "OK"
    }
}

# 3. Doble escritura de Skills
$GlobalSkillsDir = Join-Path $env:USERPROFILE ".gemini\config\skills"
if (-not (Test-Path $GlobalSkillsDir) -and -not $DryRun) { New-Item -ItemType Directory -Path $GlobalSkillsDir -Force | Out-Null }

$LocalSkills = Join-Path $RepoRoot "skills"
if (Test-Path $LocalSkills) {
    Write-Log "Duplicando skills al repositorio global del IDE ($GlobalSkillsDir)..." "INFO"
    
    $SkillFiles = Get-ChildItem -Path $LocalSkills -File -Recurse
    foreach ($File in $SkillFiles) {
        $Relative = $File.FullName.Substring($LocalSkills.Length).Trim('\')
        $Target = Join-Path $GlobalSkillsDir $Relative
        
        $TargetParent = Split-Path $Target -Parent
        if (-not (Test-Path $TargetParent) -and -not $DryRun) { New-Item -ItemType Directory -Path $TargetParent -Force | Out-Null }
        
        if (Test-Path $Target) {
            if (-not $Force) {
                $SrcHash = (Get-FileHash $File.FullName -Algorithm SHA256).Hash
                $TgtHash = (Get-FileHash $Target -Algorithm SHA256).Hash
                if ($SrcHash -eq $TgtHash) { continue }
            }
            if ($DryRun) {
                Write-Log "[DRYRUN] Copiaria skill global: $Target." "INFO"
                continue
            }
            Backup-File $Target
        }
        if (-not $DryRun) { Copy-Item -Path $File.FullName -Destination $Target -Force }
    }
    Write-Log "Sincronizacion de skills globales completada." "OK"
}
Write-Log "=== Despliegue de assets completado ===" "OK"
