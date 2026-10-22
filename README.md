# skema-buehnenprobe

Probe-App (Spike S1-H) für das Hallen-iPad des SLSHM. Bevor eine eigene Hülle für die Web-App
gebaut wird, prüft sie am echten Gerät zwei Dinge:

1. Zeigt eine eigene iPad-App über das HDMI-Kabel von selbst ein randloses Bild auf dem Fernseher,
   ohne Handgriff in den Einstellungen?
2. Zeichnet die vorhandene Bühne der Web-App auf dem Fernseher live mit, während in der Regie
   gezeichnet wird?

## Was hier liegt und was nicht

- **Kein Produktcode.** Die App selbst liegt in einem privaten Repo. Die Probe lädt nur die
  ausgelieferte Web-App vom Cloudflare-Worker: `/cockpit` in der Regie auf dem iPad, `/tv` als
  Bühne auf dem Fernseher.
- **Schlichtes UIKit in Swift**, ohne Capacitor. Das Xcode-Projekt erzeugt XcodeGen aus
  `project.yml` in jedem Lauf neu; es liegt nie im Repo.
- **Nur TestFlight intern.** Der Export setzt `testFlightInternalTestingOnly`; ein solcher Bau geht
  nur an interne Tester, nie an externe und nie in den App Store.
- Keine Zertifikate, Profile oder Schlüssel im Repo. Signiert wird erst beim Export auf dem Runner,
  mit dem API-Schlüssel aus den Repository-Secrets.

| Pfad | Inhalt |
|---|---|
| `project.yml` | Projekt für XcodeGen 2.46.0: nur iPad, ab iPadOS 26.0, Swift 5 |
| `Probe/Info.plist` | Szenen-Manifest mit Regie und TV-Szene, Launch Screen, Ausrichtungen, Exportkontrolle |
| `Probe/App.swift` | App-Delegate, Szene der Regie, Bericht je Minute (Bildraten, Akku, Wärme, Speicher) |
| `Probe/RegieController.swift` | Leiste (Testbild, Bühne, Aus, Wach), Adressfeld, `/cockpit`, Log mit „Kopieren" |
| `Probe/TvSzene.swift` | TV-Szene (`windowExternalDisplayNonInteractive`): Fenster an und ab, Inhalt umschalten |
| `Probe/Testbild.swift` | Rahmen an allen vier Kanten, Kennzahlen des Bildschirms, Bildzähler, Uhr |
| `Probe/WebAnsicht.swift` | Die zwei WKWebViews mit den Einstellungen von Capacitor und dem Diagnose-Skript |
| `Probe/Protokoll.swift` | Log-Ring mit Spiegel ins Systemlog, gemeinsamer Zustand |
| `Probe/PrivacyInfo.xcprivacy` | Datenschutz-Manifest: kein Tracking, `UserDefaults` mit Grund `CA92.1` |
| `werkzeug/erzeuge-icon.py` | Schreibt das App-Icon (Farbbalken, RGB ohne Alphakanal) |
| `werkzeug/bauen.sh` | Bau ohne Signatur und Prüfung des Archivs |
| `werkzeug/hochladen.sh` | Export, Prüfung des IPA, Upload nach App Store Connect |
| `.github/workflows/probe.yml` | Prüf-Job und Upload-Job |

## Bau

Gebaut wird auf dem macOS-Runner von GitHub (`macos-26`, Xcode 26.6). Der Name der
Workflow-Datei bleibt fest, weil die Baunummer aus `run_number.run_attempt` entsteht.

- **Prüf-Job:** bei jedem Push. XcodeGen laden und prüfen, Projekt erzeugen, Archiv ohne Signatur,
  Info.plist und Inhalt des Archivs prüfen. Braucht keine Secrets.
- **Upload-Job:** nur von Hand auf `main`:

  ```
  gh workflow run probe.yml -R alexandercarreira-arch/skema-buehnenprobe --ref main -f hochladen=true
  ```

  Wie der Prüf-Job, dann Ad-hoc-Signatur, Export als IPA, Prüfung der Entitlements, Upload.
  Mit `-f xcode=27` baut derselbe Stand auf `xcode-27`; das erst nach dem Gerätetest, weil die
  interne Gruppe jeden neuen Bau von selbst verteilt.

Logs und Artefakte sind öffentlich. Darum enthalten sie nur Auszüge aus den Verteilungs-Logs,
geschwärzt, und weder den Schlüssel noch das IPA noch `DistributionSummary.plist`.

Bauzettel und Ergebnis liegen im privaten Repo: `docs/plan/45-bauzettel-probe-s1h.md` und
`spikes/S1H/ergebnis.md`.
