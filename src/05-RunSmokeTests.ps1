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

$BoardsToTest = if ($QuickSmoke) { @("uno") } else { @("esp32dev", "uno") }

foreach ($Board in $BoardsToTest) {
    if ($DryRun) {
        Write-Log "[DRYRUN] Ejecutaria smoke test para $Board (compilacion y compiledb)." "INFO"
        continue
    }

    $TestDir = Join-Path $env:TEMP "SmokeTest_$Board"

    if (Test-Path $TestDir) { Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
    Set-Location -Path $TestDir

    Write-Log "=== Smoke Test para placa: $Board ===" "INFO"
    
    Write-Log "Inicializando proyecto pio..." "INFO"
    $Proc = Start-Process -FilePath "pio.exe" -ArgumentList "project init -b $Board" -Wait -NoNewWindow -PassThru
    if ($Proc.ExitCode -ne 0) {
        Write-Log "Fallo pio project init para $Board." "FAIL"
        exit 1
    }

    $SrcDir = Join-Path $TestDir "src"
    $MainCpp = Join-Path $SrcDir "main.cpp"

    @"
#include <Arduino.h>
void setup() { Serial.begin(115200); }
void loop() { }
"@ | Set-Content -Path $MainCpp -Encoding Ascii

    Write-Log "Compilando firmware de prueba ($Board)..." "INFO"
    $Proc = Start-Process -FilePath "pio.exe" -ArgumentList "run -e $Board" -Wait -NoNewWindow -PassThru
    if ($Proc.ExitCode -ne 0) {
        Write-Log "El Smoke Test de compilacion fallo para $Board." "FAIL"
        exit 1
    }
    Write-Log "El firmware compila perfectamente para $Board." "OK"

    Write-Log "Generando compiledb..." "INFO"
    $Proc = Start-Process -FilePath "pio.exe" -ArgumentList "run -e $Board -t compiledb" -Wait -NoNewWindow -PassThru
    
    $CompileDb = Join-Path $TestDir ".pio\build\$Board\compile_commands.json"
    if (Test-Path $CompileDb) {
        Write-Log "compile_commands.json generado exitosamente para $Board." "OK"
    } else {
        Write-Log "compile_commands.json no generado para $Board." "FAIL"
        exit 1
    }

    Write-Log "Limpiando directorio de prueba de $Board..." "INFO"
    Set-Location -Path $WorkDir
    Remove-Item -Path $TestDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Log "=== Todos los Smoke Tests superados con exito ===" "OK"
