<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Ablage App-Symbol">
</p>

<h1 align="center">Ablage</h1>

<p align="center">
  <strong>Bildschirmfoto, Bildschirmaufnahme und Zwischenablage-Verlauf – minimalistisch in der macOS-Menüleiste.</strong><br>
  Kostenlos · Open Source · Apple Silicon &amp; Intel · macOS 15 Sequoia oder neuer
</p>

<p align="center">
  <a href="https://github.com/TuttoBene1/Ablage-App/releases/latest/download/Ablage.dmg"><img src="https://img.shields.io/badge/Download-Ablage.dmg-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="Ablage für macOS herunterladen"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-555555" alt="Universal Binary">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/Lizenz-MIT-2EA44F" alt="MIT-Lizenz">
  <a href="https://webforging.de"><img src="https://img.shields.io/badge/by-Webforging-111111" alt="Entwickelt von Webforging"></a>
</p>

<p align="center">
  <img src="docs/screenshots/home-light.png" width="330" alt="Ablage – Menüleisten-Panel mit Bildschirmfoto und Zwischenablage">
  &nbsp;&nbsp;
  <img src="docs/screenshots/clipboard-dark.png" width="330" alt="Ablage – Zwischenablage-Verlauf mit angehefteten Einträgen">
</p>

---

Ablage ist ein kleines, natives Werkzeug für die Menüleiste deines Macs. Ein Klick auf das Symbol oben rechts
öffnet zwei Kacheln: **Bildschirmfoto** und **Zwischenablage**. Keine Dock-Symbole, keine Fenster im Weg,
kein Konto, keine Cloud – Ablage läuft komplett lokal.

Entwickelt von **[Webforging](https://webforging.de)**, der Web- & E-Commerce-Agentur aus München.

## Funktionen

**Bildschirmfoto & Bildschirmaufnahme**
- Bildschirm wird leicht abgedunkelt, der Cursor wird zum Fadenkreuz, Bereich aufziehen – fertig.
- Das Foto liegt sofort in der Zwischenablage (⌘V), in voller Retina-Auflösung.
- Vorher auf **Video** umschalten, um den Bereich als Bildschirmaufnahme (.mov, 60 fps) aufzunehmen.
  Gestoppt wird über das Symbol in der Menüleiste; das Video landet in „Filme“ und in der Zwischenablage.
- Funktioniert auf mehreren Bildschirmen, Ablage selbst ist auf Aufnahmen nie zu sehen.

**Vorschau & Editor**
- Nach jedem Foto gleitet unten rechts eine kleine Vorschau herein.
- Ein Klick öffnet den Editor: **Beschneiden**, **Pinsel** mit 8 Farben und 3 Stärken, Widerrufen.
- **Kopieren** legt das bearbeitete Bild in die Zwischenablage, **✓** übernimmt es und schließt.

**Zwischenablage-Verlauf**
- Die letzten 25 kopierten Texte, Bilder und Dateien – mit Herkunfts-App und Zeitpunkt.
- Mit der **Nadel** angeheftete Einträge bleiben dauerhaft und werden nie verdrängt.
- Klick auf einen Eintrag kopiert ihn erneut. Suche und Tastatursteuerung inklusive.
- Passwörter aus Passwort-Managern (als vertraulich markierte Inhalte) werden ignoriert.

<p align="center">
  <img src="docs/screenshots/editor-light.png" width="680" alt="Ablage – Editor mit Pinsel und Farbauswahl">
</p>

<p align="center">
  <img src="docs/screenshots/toolbar-video.png" width="257" alt="Auswahl-Leiste: Foto oder Video">
  &nbsp;
  <img src="docs/screenshots/preview-hover.png" width="252" alt="Vorschau nach dem Bildschirmfoto">
</p>

## Installation

### Variante 1: DMG herunterladen

1. **[Ablage.dmg herunterladen](https://github.com/TuttoBene1/Ablage-App/releases/latest/download/Ablage.dmg)**
2. DMG öffnen und **Ablage** in den Ordner **Programme** ziehen.
3. Ablage öffnen. Beim ersten Start meldet macOS, dass die App nicht überprüft werden kann
   (Ablage ist nicht bei Apple notarisiert). Dann einmalig:
   **Systemeinstellungen › Datenschutz & Sicherheit › ganz unten bei „Ablage“ auf „Dennoch öffnen“** klicken.

### Variante 2: Ein Befehl im Terminal

```bash
curl -fsSL https://raw.githubusercontent.com/TuttoBene1/Ablage-App/main/install.sh | bash
```

Lädt das neueste Release, installiert es nach `/Programme` und startet Ablage. Für ein Update einfach erneut ausführen.

### Berechtigung „Bildschirmaufnahme“

Für Bildschirmfotos braucht Ablage die macOS-Berechtigung **Bildschirm- & Systemaudioaufnahme**.
Beim ersten Bildschirmfoto fragt macOS danach; alternativ unter
*Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme* „Ablage“ aktivieren.

macOS fragt bei allen Apps, die den Bildschirm direkt aufnehmen, zusätzlich in regelmäßigen Abständen nach.
Dort **„Erlauben“** wählen – „Systemeinstellungen öffnen“ zählt nicht als Zustimmung.

### Systemvoraussetzungen

- macOS 15 Sequoia oder neuer (auch macOS 26 und 27)
- Apple Silicon (M1 und neuer) oder Intel – Ablage ist ein Universal-Binary

## Bedienung

| Aktion | Bedienung |
| --- | --- |
| Panel öffnen | Klick auf das Symbol in der Menüleiste |
| Schnellmenü (Über, Beim Anmelden öffnen, Beenden) | Rechtsklick auf das Symbol |
| Bereich auswählen | Ziehen mit dem Fadenkreuz |
| Foto / Video umschalten | Leiste unten oder Tasten `F` / `V` |
| Auswahl abbrechen | `esc` oder Rechtsklick |
| Aufnahme beenden | Klick auf das Stopp-Symbol in der Menüleiste |
| Editor: Beschneiden / Pinsel | `C` / `P` |
| Editor: Widerrufen / Wiederholen | `⌘Z` / `⇧⌘Z` |
| Editor: Kopieren / Fertig / Schließen | `⌘C` / `↩` / `esc` |
| Verlauf: suchen | einfach lostippen |
| Verlauf: auswählen / kopieren | `↑` `↓` / `↩` |
| Verlauf: anheften / löschen | `⌘P` / `⌘⌫` |

## Datenschutz

- Ablage stellt **keine Netzwerkverbindungen** her, sammelt keine Daten und hat kein Tracking.
- Der Verlauf liegt ausschließlich lokal unter `~/Library/Application Support/Ablage`.
- Inhalte, die Passwort-Manager als vertraulich markieren, werden nicht gespeichert.

## Deinstallieren

Ablage beenden (Rechtsklick auf das Symbol › „Ablage beenden“), dann:

```bash
rm -rf /Applications/Ablage.app ~/Library/Application\ Support/Ablage
```

## Selbst bauen

Voraussetzung sind die Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/TuttoBene1/Ablage-App.git
cd Ablage-App
./build.sh --install    # baut, installiert nach /Applications und startet
./build.sh --release    # erzeugt dist/Ablage.dmg und dist/Ablage-macOS.zip
```

Lokale Builds werden mit einem selbstsignierten Zertifikat signiert (`Scripts/signing.sh`), damit macOS
die Berechtigung „Bildschirmaufnahme“ auch nach Updates behält.

Für Entwickler: `Ablage --snapshot <ordner>` rendert alle Oberflächen mit Beispieldaten als PNG,
`Ablage --selftest` prüft Panel, Scrollen und Editor automatisch.

Releases entstehen automatisch über GitHub Actions, sobald ein Tag `v*` gepusht wird.

## English

**Ablage** is a minimal, native macOS menu bar app for **screenshots, screen recordings and clipboard history**.
Select an area with the crosshair and the screenshot is copied instantly; a small preview slides in and opens
an editor for cropping and drawing. The clipboard history keeps your last 25 items and lets you pin favourites.
Runs fully offline. Universal binary for Apple silicon and Intel, macOS 15 Sequoia or later.

[Download Ablage.dmg](https://github.com/TuttoBene1/Ablage-App/releases/latest/download/Ablage.dmg) ·
or install via Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/TuttoBene1/Ablage-App/main/install.sh | bash
```

The app is not notarized by Apple: on first launch, open *System Settings › Privacy & Security* and click
**“Open Anyway”**. Built by **[Webforging](https://webforging.de)** – web & e-commerce agency from Munich.

## Lizenz

[MIT](LICENSE) © 2026 [Webforging](https://webforging.de)

<p align="center">
  <sub>Made with ♥ in München von <a href="https://webforging.de">Webforging – Websites &amp; Onlineshops, die konvertieren</a></sub>
</p>
