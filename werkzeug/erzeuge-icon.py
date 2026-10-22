"""Schreibt das App-Icon der Probe als Farbbalken-Testbild.

Ziel: Probe/Assets.xcassets/AppIcon.appiconset/icon-1024.png, 1024 x 1024 Pixel,
PNG in RGB ohne Alphakanal (Farbtyp 2), weil der Upload ein grosses Icon mit
Alphakanal ablehnt (ITMS-90717, Bauzettel 45, Paragraf 4). Nur Standardbibliothek.
Einmal am PC ausgefuehrt, die PNG ist eingecheckt.
"""

import pathlib
import struct
import zlib

GROESSE = 1024
ZIEL = (
    pathlib.Path(__file__).resolve().parent.parent
    / "Probe"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "icon-1024.png"
)

# Sieben Balken wie ein klassisches Testbild: Weiss, Gelb, Cyan, Gruen, Magenta, Rot, Blau.
BALKEN = [
    (235, 235, 235),
    (235, 235, 16),
    (16, 235, 235),
    (16, 235, 16),
    (235, 16, 235),
    (235, 16, 16),
    (16, 16, 235),
]
# Gegenbalken darunter: Blau, Schwarz, Magenta, Schwarz, Cyan, Schwarz, Weiss.
GEGEN = [
    (16, 16, 235),
    (16, 16, 16),
    (235, 16, 235),
    (16, 16, 16),
    (16, 235, 235),
    (16, 16, 16),
    (235, 235, 235),
]
# Unten ein dunkelgruenes Feld fuer die Buehne.
GRUEN = (8, 61, 46)


def zeile(farben):
    werte = bytearray([0])  # Filter 0 (keiner) vor jeder Zeile
    for x in range(GROESSE):
        werte.extend(farben[x * len(farben) // GROESSE])
    return bytes(werte)


def block(art, daten):
    return (
        struct.pack(">I", len(daten))
        + art
        + daten
        + struct.pack(">I", zlib.crc32(art + daten) & 0xFFFFFFFF)
    )


def main():
    oben = zeile(BALKEN)
    mitte = zeile(GEGEN)
    unten = zeile([GRUEN])
    roh = bytearray()
    for y in range(GROESSE):
        if y < GROESSE * 2 // 3:
            roh.extend(oben)
        elif y < GROESSE * 3 // 4:
            roh.extend(mitte)
        else:
            roh.extend(unten)
    kopf = struct.pack(">IIBBBBB", GROESSE, GROESSE, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + block(b"IHDR", kopf)
        + block(b"IDAT", zlib.compress(bytes(roh), 9))
        + block(b"IEND", b"")
    )
    ZIEL.write_bytes(png)
    # Kontrolle: Farbtyp 2 (RGB) steht im IHDR an Byte 25.
    assert ZIEL.read_bytes()[25] == 2
    print(f"{ZIEL} ({len(png)} Bytes, RGB ohne Alpha)")


if __name__ == "__main__":
    main()
