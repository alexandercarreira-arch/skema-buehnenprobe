import Foundation
import UIKit
import os

/// Log-Ring der Probe: 2 000 Zeilen mit Uhrzeit, gespiegelt nach `os.Logger`, damit
/// `pymobiledevice3 syslog live` mitlesen kann (Bauzettel 45, § 3.1 und § 3.5).
/// Jeder eingesetzte Text steht mit `privacy: .public`, sonst schwaerzt das System ihn als `<private>`.
final class Protokoll: @unchecked Sendable {
    static let shared = Protokoll()
    static let geaendert = Notification.Name("ProbeProtokollGeaendert")

    private let grenze = 2_000
    private let sperre = NSLock()
    private var zeilen: [String] = []
    private let uhr: DateFormatter
    private let logger = Logger(subsystem: "io.github.alexandercarreira-arch.skema-buehnenprobe", category: "probe")

    private init() {
        uhr = DateFormatter()
        uhr.locale = Locale(identifier: "en_US_POSIX")
        uhr.dateFormat = "HH:mm:ss.SSS"
    }

    func schreibe(_ text: String) {
        sperre.lock()
        let zeile = "\(uhr.string(from: Date())) \(text)"
        zeilen.append(zeile)
        if zeilen.count > grenze {
            zeilen.removeFirst(zeilen.count - grenze)
        }
        sperre.unlock()
        logger.log("\(zeile, privacy: .public)")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Protokoll.geaendert, object: nil)
        }
    }

    /// Der ganze Ring, fuer „Kopieren".
    func text() -> String {
        sperre.lock()
        defer { sperre.unlock() }
        return zeilen.joined(separator: "\n")
    }

    /// Die letzten Zeilen, fuer die Log-Ansicht der Regie.
    func letzte(_ anzahl: Int) -> String {
        sperre.lock()
        defer { sperre.unlock() }
        return zeilen.suffix(anzahl).joined(separator: "\n")
    }

    /// Uhrzeit ohne Datum, etwa fuer „seit" im Testbild.
    func uhrzeit(_ datum: Date) -> String {
        sperre.lock()
        defer { sperre.unlock() }
        return String(uhr.string(from: datum).prefix(8))
    }
}

/// Was die TV-Szene zeigt.
enum TvInhalt: String, CaseIterable {
    case testbild = "Testbild"
    case buehne = "Bühne"
    case aus = "Aus"
}

/// Gemeinsamer Zustand von Regie und TV-Szene: Inhalt des TV, Adresse, Wach.
@MainActor
final class Zustand {
    static let shared = Zustand()
    static let geaendert = Notification.Name("ProbeZustandGeaendert")
    static let adresseGeaendert = Notification.Name("ProbeAdresseGeaendert")
    private static let standardAdresse = "https://skema-pro.alexandercarreira.workers.dev"
    private static let adressSchluessel = "adresse"

    var tvInhalt: TvInhalt = .testbild {
        didSet {
            guard tvInhalt != oldValue else { return }
            Protokoll.shared.schreibe("TV-Inhalt: \(tvInhalt.rawValue)")
            NotificationCenter.default.post(name: Zustand.geaendert, object: nil)
        }
    }

    var wach = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = wach
            Protokoll.shared.schreibe("Wach: \(wach ? "an" : "aus") (isIdleTimerDisabled \(UIApplication.shared.isIdleTimerDisabled))")
            NotificationCenter.default.post(name: Zustand.geaendert, object: nil)
        }
    }

    /// Basisadresse der Web-App, in `UserDefaults` gemerkt (Grund CA92.1 im Datenschutz-Manifest).
    var adresse: String {
        get { UserDefaults.standard.string(forKey: Zustand.adressSchluessel) ?? Zustand.standardAdresse }
        set {
            UserDefaults.standard.set(newValue, forKey: Zustand.adressSchluessel)
            NotificationCenter.default.post(name: Zustand.adresseGeaendert, object: nil)
        }
    }

    private(set) var tvSzenenZustand = "nicht verbunden"
    private(set) var tvSzenenSeit = Date()
    var neuladungen = 0
    weak var regieWeb: WebAnsicht?
    /// Die Bühne lebt so lange wie die App: Ein Wechsel zwischen Testbild und Bühne und ein
    /// Wiederverbinden des Kabels laden die Seite nicht neu.
    private(set) var buehneWeb: WebAnsicht?

    private init() {}

    func setzeTvSzene(_ zustand: String) {
        guard zustand != tvSzenenZustand else { return }
        tvSzenenZustand = zustand
        tvSzenenSeit = Date()
    }

    func buehne() -> WebAnsicht {
        if let vorhanden = buehneWeb {
            return vorhanden
        }
        let neu = WebAnsicht(rolle: .buehne)
        buehneWeb = neu
        return neu
    }
}

/// Wiederkehrender Takt auf dem Haupt-Thread, ueber Ziel und Selektor statt Block.
@MainActor
final class Takt: NSObject {
    private var timer: Timer?
    private let aktion: () -> Void

    init(intervall: TimeInterval, aktion: @escaping () -> Void) {
        self.aktion = aktion
        super.init()
        let neu = Timer(timeInterval: intervall, target: self, selector: #selector(feuer), userInfo: nil, repeats: true)
        RunLoop.main.add(neu, forMode: .common)
        timer = neu
    }

    @objc private func feuer() {
        aktion()
    }

    func stopp() {
        timer?.invalidate()
        timer = nil
    }
}

/// „Bühnenprobe 0.1 Bau 17.1, Xcode 26.6" aus der Info.plist.
func bauText() -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let bau = info["CFBundleVersion"] as? String ?? "?"
    let xcode = info["ProbeXcode"] as? String ?? "?"
    return "Bühnenprobe \(version) Bau \(bau), \(xcode)"
}

func zustandText(_ zustand: UIScene.ActivationState) -> String {
    switch zustand {
    case .unattached: return "unattached"
    case .foregroundActive: return "foregroundActive"
    case .foregroundInactive: return "foregroundInactive"
    case .background: return "background"
    @unknown default: return "unbekannt"
    }
}

func waermeText(_ zustand: ProcessInfo.ThermalState) -> String {
    switch zustand {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unbekannt"
    }
}

@MainActor
func akkuText() -> String {
    let geraet = UIDevice.current
    let stand = geraet.batteryLevel < 0 ? "unbekannt" : "\(Int((geraet.batteryLevel * 100).rounded())) %"
    let laden: String
    switch geraet.batteryState {
    case .charging: laden = "lädt"
    case .full: laden = "voll"
    case .unplugged: laden = "nicht angeschlossen"
    case .unknown: laden = "unbekannt"
    @unknown default: laden = "unbekannt"
    }
    return "\(stand), \(laden)"
}

func zahl(_ wert: CGFloat) -> String {
    if wert.rounded() == wert {
        return String(Int(wert))
    }
    return String(format: "%.2f", Double(wert))
}

func groesse(_ wert: CGSize) -> String {
    "\(zahl(wert.width)) × \(zahl(wert.height))"
}

func kurz(_ text: String, _ grenze: Int = 200) -> String {
    text.count > grenze ? String(text.prefix(grenze)) + "…" : text
}
