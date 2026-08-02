#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
detect_board.py - Identifica placas conectadas por VID:PID y dice exactamente
que driver hace falta.

ASCII-ONLY a proposito: la terminal de Windows corre en cp1252 y un emoji
rompe el script con UnicodeEncodeError.

Uso:
    python detect_board.py            # tabla legible
    python detect_board.py --json     # salida JSON para el agente IA
    python detect_board.py --quiet    # solo el primer puerto detectado
"""

from __future__ import print_function

import json
import os
import subprocess
import sys

PIO_EXE = os.path.join(
    os.path.expanduser("~"), ".platformio", "penv", "Scripts", "pio.exe"
)

# --------------------------------------------------------------------------
# Mapa VID:PID -> chip / placa probable / driver
# Formato: (vid, pid_o_None) -> dict
# pid None significa "cualquier PID de ese fabricante"
# --------------------------------------------------------------------------
DRIVER_CP210X = {
    "name": "CP210x VCP (Silicon Labs)",
    "url": "https://www.silabs.com/developers/usb-to-uart-bridge-vcp-drivers",
}
DRIVER_CH34X = {
    "name": "CH340/CH341 (WCH)",
    "url": "https://www.wch-ic.com/downloads/CH341SER_ZIP.html",
}
DRIVER_FTDI = {
    "name": "FTDI VCP",
    "url": "https://ftdichip.com/drivers/vcp-drivers/",
}
DRIVER_NATIVE = {"name": "Ninguno (CDC nativo de Windows)", "url": ""}
DRIVER_STLINK = {
    "name": "ST-LINK / STSW-LINK009",
    "url": "https://www.st.com/en/development-tools/stsw-link009.html",
}

VID_PID_MAP = {
    # --- Silicon Labs CP210x ---
    ("10C4", "EA60"): ("CP2102/CP2102N", "ESP32 DevKit, NodeMCU-32S, LOLIN32", DRIVER_CP210X),
    ("10C4", "EA70"): ("CP2105", "Adaptador serie dual", DRIVER_CP210X),
    ("10C4", "EA71"): ("CP2108", "Adaptador serie quad", DRIVER_CP210X),
    # --- WCH CH34x ---
    ("1A86", "7523"): ("CH340G", "Arduino Nano clon, ESP8266 NodeMCU v3", DRIVER_CH34X),
    ("1A86", "7522"): ("CH340K", "Placa china generica", DRIVER_CH34X),
    ("1A86", "5523"): ("CH341", "Adaptador USB-serie", DRIVER_CH34X),
    ("1A86", "55D4"): ("CH9102F", "ESP32 DevKit reciente", DRIVER_CH34X),
    ("1A86", "55D3"): ("CH343", "Adaptador USB-serie moderno", DRIVER_CH34X),
    # --- FTDI ---
    ("0403", "6001"): ("FT232R", "Arduino Nano original, Duemilanove", DRIVER_FTDI),
    ("0403", "6010"): ("FT2232", "ESP-Prog, JTAG dual", DRIVER_FTDI),
    ("0403", "6014"): ("FT232H", "Adaptador de alta velocidad", DRIVER_FTDI),
    ("0403", "6015"): ("FT231X", "Sparkfun/Adafruit varios", DRIVER_FTDI),
    # --- Arduino oficial (CDC nativo) ---
    ("2341", "0043"): ("ATmega16U2", "Arduino Uno R3", DRIVER_NATIVE),
    ("2341", "0001"): ("ATmega8U2", "Arduino Uno R1/R2", DRIVER_NATIVE),
    ("2341", "0010"): ("ATmega16U2", "Arduino Mega 2560", DRIVER_NATIVE),
    ("2341", "0042"): ("ATmega16U2", "Arduino Mega 2560 R3", DRIVER_NATIVE),
    ("2341", "8036"): ("ATmega32U4", "Arduino Leonardo", DRIVER_NATIVE),
    ("2341", "8037"): ("ATmega32U4", "Arduino Micro", DRIVER_NATIVE),
    ("2341", "003D"): ("SAM3X8E", "Arduino Due (Programming Port)", DRIVER_NATIVE),
    ("2341", "804D"): ("SAMD21", "Arduino Zero", DRIVER_NATIVE),
    ("2341", "0070"): ("ESP32-S3", "Arduino Nano ESP32", DRIVER_NATIVE),
    ("2341", "0069"): ("RA4M1", "Arduino Uno R4 WiFi", DRIVER_NATIVE),
    ("2341", "1002"): ("RA4M1", "Arduino Uno R4 Minima", DRIVER_NATIVE),
    ("2A03", None): ("Arduino.org", "Arduino (marca .org)", DRIVER_NATIVE),
    # --- Espressif USB nativo ---
    ("303A", "1001"): ("ESP32-S2/S3/C3 USB-CDC", "DevKit con USB nativo", DRIVER_NATIVE),
    ("303A", "0002"): ("ESP32-S2", "ESP32-S2 en modo DFU", DRIVER_NATIVE),
    ("303A", "1002"): ("ESP32-S3 USB-JTAG", "ESP32-S3 DevKitC-1", DRIVER_NATIVE),
    ("303A", None): ("Espressif USB nativo", "ESP32-S2/S3/C3/C6/H2", DRIVER_NATIVE),
    # --- Raspberry Pi ---
    ("2E8A", "0003"): ("RP2040 BOOTSEL", "Raspberry Pi Pico (modo arrastrar UF2)", DRIVER_NATIVE),
    ("2E8A", "000A"): ("RP2040 CDC", "Raspberry Pi Pico corriendo firmware", DRIVER_NATIVE),
    ("2E8A", "0005"): ("RP2040 CDC", "Pico con Arduino core", DRIVER_NATIVE),
    ("2E8A", None): ("RP2040/RP2350", "Raspberry Pi Pico family", DRIVER_NATIVE),
    # --- STM32 ---
    ("0483", "374B"): ("ST-LINK/V2-1", "STM32 Nucleo", DRIVER_STLINK),
    ("0483", "3748"): ("ST-LINK/V2", "Sonda ST-LINK externa (Blue Pill)", DRIVER_STLINK),
    ("0483", "DF11"): ("STM32 DFU", "Blue Pill en modo bootloader DFU", DRIVER_NATIVE),
    ("0483", "5740"): ("STM32 CDC", "STM32 con firmware USB CDC", DRIVER_NATIVE),
    # --- Otros habituales ---
    ("239A", None): ("SAMD/nRF/ESP", "Adafruit (Feather, ItsyBitsy, QT Py)", DRIVER_NATIVE),
    ("1B4F", None): ("SAMD/32U4", "SparkFun", DRIVER_NATIVE),
    ("16C0", "0483"): ("MK20/IMXRT", "Teensy", DRIVER_NATIVE),
    ("1209", None): ("Varios", "pid.codes (proyectos open hardware)", DRIVER_NATIVE),
}

BOARD_HINT = {
    "Arduino Uno R3": "uno",
    "Arduino Mega 2560": "megaatmega2560",
    "Arduino Mega 2560 R3": "megaatmega2560",
    "Arduino Nano clon, ESP8266 NodeMCU v3": "nanoatmega328new",
    "Arduino Nano original, Duemilanove": "nanoatmega328",
    "Arduino Leonardo": "leonardo",
    "Arduino Micro": "micro",
    "Arduino Due (Programming Port)": "due",
    "Arduino Zero": "zeroUSB",
    "ESP32 DevKit, NodeMCU-32S, LOLIN32": "esp32dev",
    "ESP32 DevKit reciente": "esp32dev",
    "ESP32-S3 DevKitC-1": "esp32-s3-devkitc-1",
    "DevKit con USB nativo": "esp32-s3-devkitc-1",
    "Raspberry Pi Pico (modo arrastrar UF2)": "pico",
    "Raspberry Pi Pico corriendo firmware": "pico",
    "STM32 Nucleo": "nucleo_f401re",
    "Sonda ST-LINK externa (Blue Pill)": "bluepill_f103c8",
}


def parse_hwid(hwid):
    """Extrae (VID, PID) en mayusculas de un hwid tipo 'USB VID:PID=2341:0043 ...'."""
    if not hwid:
        return (None, None)
    upper = hwid.upper()
    if "VID:PID=" not in upper:
        return (None, None)
    chunk = upper.split("VID:PID=", 1)[1]
    chunk = chunk.split()[0]
    if ":" not in chunk:
        return (None, None)
    vid, pid = chunk.split(":", 1)
    return (vid.strip(), pid.strip()[:4])


def lookup(vid, pid):
    if vid is None:
        return ("Desconocido", "Desconocida", DRIVER_NATIVE)
    if (vid, pid) in VID_PID_MAP:
        return VID_PID_MAP[(vid, pid)]
    if (vid, None) in VID_PID_MAP:
        return VID_PID_MAP[(vid, None)]
    return ("Desconocido (VID %s)" % vid, "Desconocida", DRIVER_NATIVE)


def get_devices():
    if not os.path.exists(PIO_EXE):
        return None, "pio.exe no encontrado en %s" % PIO_EXE
    try:
        raw = subprocess.check_output(
            [PIO_EXE, "device", "list", "--json-output"],
            stderr=subprocess.STDOUT,
        )
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8", "replace")
        return json.loads(raw), None
    except Exception as exc:  # noqa: BLE001
        return None, str(exc)


def main():
    as_json = "--json" in sys.argv
    quiet = "--quiet" in sys.argv

    devices, err = get_devices()
    if err:
        payload = {"ok": False, "error": err, "devices": []}
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            print("[FAIL] %s" % err)
        return 1

    results = []
    for dev in devices or []:
        vid, pid = parse_hwid(dev.get("hwid", ""))
        chip, board_desc, driver = lookup(vid, pid)
        results.append(
            {
                "port": dev.get("port"),
                "description": dev.get("description"),
                "hwid": dev.get("hwid"),
                "vid": vid,
                "pid": pid,
                "chip": chip,
                "board_probable": board_desc,
                "pio_board_id": BOARD_HINT.get(board_desc, ""),
                "driver_needed": driver["name"],
                "driver_url": driver["url"],
            }
        )

    if as_json:
        print(json.dumps({"ok": True, "count": len(results), "devices": results}, indent=2))
        return 0

    if quiet:
        print(results[0]["port"] if results else "")
        return 0 if results else 1

    if not results:
        print("[WARN] Ninguna placa detectada.")
        print("       Causas por probabilidad real:")
        print("         1. Cable USB de solo carga (sin lineas de datos)")
        print("         2. Driver ausente (CP210x / CH340 / FTDI)")
        print("         3. Placa en modo boot o colgada")
        return 1

    print("[OK] %d dispositivo(s) detectado(s)" % len(results))
    print("")
    for r in results:
        print("  Puerto        : %s" % r["port"])
        print("  Chip          : %s" % r["chip"])
        print("  Placa probable: %s" % r["board_probable"])
        if r["pio_board_id"]:
            print("  board = %s   (para platformio.ini)" % r["pio_board_id"])
        print("  VID:PID       : %s:%s" % (r["vid"], r["pid"]))
        print("  Driver        : %s" % r["driver_needed"])
        if r["driver_url"]:
            print("  Descarga      : %s" % r["driver_url"])
        print("")
    return 0


if __name__ == "__main__":
    sys.exit(main())
