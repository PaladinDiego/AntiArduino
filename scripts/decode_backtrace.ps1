<#
.SYNOPSIS
    Decodifica un backtrace de ESP32 (Guru Meditation Error) a archivo:linea.

.DESCRIPTION
    Usa addr2line del toolchain correspondiente sobre .pio\build\<env>\firmware.elf.
    Sirve cuando el filtro esp32_exception_decoder no corrio (por ejemplo
    porque el monitor se lanzo con --filter log2file).

.EXAMPLE
    .\decode_backtrace.ps1 -Env esp32dev -Backtrace "0x400d1234:0x3ffb1f30 0x400d5678:0x3ffb1f50"
    .\decode_backtrace.ps1 -Env esp32dev -LogFile .\.antigravity-embedded\logs\monitor_COM5_x.log
#>
[CmdletBinding()]
param(
    [Alias("env")]
    [string]$Env = "esp32dev",
    [string]$Backtrace = "",
    [string]$LogFile = "",
    [string]$WorkDir = (Get-Location).Path
)

$ErrorActionPreference = "Continue"
$WorkDir = (Resolve-Path $WorkDir).Path

# --------------------------------------------------------------------------
# 1. Localizar el ELF
# --------------------------------------------------------------------------
$elf = Join-Path $WorkDir ".pio\build\$Env\firmware.elf"
if (-not (Test-Path $elf)) {
    Write-Host "[FAIL] No existe $elf"
    Write-Host "       Compila primero: pio run -e $Env"
    exit 1
}
Write-Host "[OK] ELF: $elf"

# --------------------------------------------------------------------------
# 2. Localizar addr2line del toolchain adecuado
# --------------------------------------------------------------------------
$pkgRoot = Join-Path $env:USERPROFILE ".platformio\packages"
$candidates = @(
    "toolchain-xtensa-esp32\bin\xtensa-esp32-elf-addr2line.exe",
    "toolchain-xtensa-esp32s2\bin\xtensa-esp32s2-elf-addr2line.exe",
    "toolchain-xtensa-esp32s3\bin\xtensa-esp32s3-elf-addr2line.exe",
    "toolchain-riscv32-esp\bin\riscv32-esp-elf-addr2line.exe",
    "toolchain-xtensa\bin\xtensa-lx106-elf-addr2line.exe"
)

$addr2line = $null
foreach ($c in $candidates) {
    $full = Join-Path $pkgRoot $c
    if (Test-Path $full) { $addr2line = $full; break }
}

if (-not $addr2line) {
    Write-Host "[FAIL] No se encontro addr2line en $pkgRoot"
    Write-Host "       Instala la plataforma: pio pkg install -g -p espressif32"
    exit 1
}
Write-Host "[OK] addr2line: $addr2line"

# --------------------------------------------------------------------------
# 3. Reunir las direcciones
# --------------------------------------------------------------------------
$text = $Backtrace
if (-not $text -and $LogFile) {
    if (-not (Test-Path $LogFile)) {
        Write-Host "[FAIL] No existe $LogFile"
        exit 1
    }
    $line = Select-String -Path $LogFile -Pattern 'Backtrace:' | Select-Object -Last 1
    if (-not $line) {
        Write-Host "[WARN] No se encontro ninguna linea 'Backtrace:' en el log."
        exit 0
    }
    $text = $line.Line
}

if (-not $text) {
    Write-Host "[FAIL] Indica -Backtrace '0x... 0x...' o -LogFile <ruta>"
    exit 1
}

$addresses = [regex]::Matches($text, '0x4[0-9a-fA-F]{7}') | ForEach-Object { $_.Value } | Select-Object -Unique
if ($addresses.Count -eq 0) {
    Write-Host "[WARN] No se detectaron direcciones de codigo (0x4xxxxxxx) en la entrada."
    exit 0
}

Write-Host "[OK] $($addresses.Count) direcciones a decodificar."
Write-Host ""

# --------------------------------------------------------------------------
# 4. Decodificar
# --------------------------------------------------------------------------
foreach ($addr in $addresses) {
    $out = & $addr2line -pfiaC -e $elf $addr 2>&1
    Write-Host "  $out"
}

Write-Host ""
Write-Host "[OK] Decodificacion terminada."
Write-Host "     Tip: la primera linea suele ser el punto exacto del crash."
