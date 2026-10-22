import UIKit

/// Testbild der TV-Szene (Bauzettel 45, § 3.3): Rahmenlinie von 2 Pixeln genau an allen vier Kanten,
/// rote Eckmarken, graue Hilfsrahmen bei 5 und 10 Prozent, mittig ein 16:9-Rahmen mit Kreis,
/// dazu die Kennzahlen des Bildschirms, ein Bildzaehler und eine Uhr mit Zehntelsekunden (P1, P5).
/// Kein Moduswechsel (E13): Die Modi werden nur abgelesen.
@MainActor
final class Testbild: UIView {
    private let text = UILabel()
    private var link: CADisplayLink?
    private var bilderGesamt = 0
    private var bilderInSekunde = 0
    private var sekundenBeginn = Date()
    private var gemessen = 0
    private var letztesZehntel = -1
    private let uhr = DateFormatter()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        contentMode = .redraw
        uhr.locale = Locale(identifier: "en_US_POSIX")
        uhr.dateFormat = "HH:mm:ss.S"
        text.numberOfLines = 0
        text.textColor = .white
        text.backgroundColor = UIColor(white: 0, alpha: 0.55)
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: centerXAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.84),
            text.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.84),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) wird nicht benutzt")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let schrift = max(12, (min(bounds.width, bounds.height) / 40).rounded())
        if text.font.pointSize != schrift {
            text.font = .monospacedSystemFont(ofSize: schrift, weight: .regular)
        }
        let breite = (bounds.width * 0.84).rounded()
        if text.preferredMaxLayoutWidth != breite {
            text.preferredMaxLayoutWidth = breite
        }
    }

    /// Der Bildzaehler laeuft am Bildschirm der Szene, nicht am iPad (`windowScene.screen`, [A1]).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard let bildschirm = window?.windowScene?.screen else {
            return
        }
        if let neu = bildschirm.displayLink(withTarget: SchwachesZiel(self), selector: #selector(SchwachesZiel.tick(_:))) {
            neu.add(to: .main, forMode: .common)
            link = neu
        } else {
            Protokoll.shared.schreibe("Testbild: kein CADisplayLink vom Bildschirm der Szene")
        }
        sekundenBeginn = Date()
        bilderInSekunde = 0
        setNeedsDisplay()
        aktualisiereText(Date())
    }

    fileprivate func tick() {
        bilderGesamt += 1
        bilderInSekunde += 1
        let jetzt = Date()
        let dauer = jetzt.timeIntervalSince(sekundenBeginn)
        if dauer >= 1 {
            gemessen = Int((Double(bilderInSekunde) / dauer).rounded())
            bilderInSekunde = 0
            sekundenBeginn = jetzt
        }
        let zehntel = Int(jetzt.timeIntervalSince1970 * 10)
        if zehntel != letztesZehntel {
            letztesZehntel = zehntel
            aktualisiereText(jetzt)
        }
    }

    private func aktualisiereText(_ jetzt: Date) {
        guard let bildschirm = window?.windowScene?.screen else {
            return
        }
        let punkte = bildschirm.bounds.size
        let pixel = CGSize(width: punkte.width * bildschirm.scale, height: punkte.height * bildschirm.scale)
        var zeilen: [String] = [bauText()]
        zeilen.append("Auflösung \(groesse(pixel)) px (bounds \(groesse(punkte)) pt, scale \(zahl(bildschirm.scale)))")
        zeilen.append("nativeBounds \(groesse(bildschirm.nativeBounds.size)), nativeScale \(zahl(bildschirm.nativeScale))")
        if let modus = bildschirm.currentMode {
            zeilen.append("currentMode \(groesse(modus.size)), pixelAspectRatio \(zahl(modus.pixelAspectRatio))")
        } else {
            zeilen.append("currentMode keiner")
        }
        let bevorzugt = bildschirm.preferredMode.map { groesse($0.size) } ?? "keiner"
        zeilen.append("preferredMode \(bevorzugt)")
        let modi = bildschirm.availableModes.map { groesse($0.size) }.joined(separator: ", ")
        zeilen.append("availableModes \(modi.isEmpty ? "keine" : modi)")
        let rand = bildschirm.overscanCompensationInsets
        zeilen.append("Overscan \(overscanText(bildschirm.overscanCompensation)), Insets \(zahl(rand.top)) \(zahl(rand.left)) \(zahl(rand.bottom)) \(zahl(rand.right))")
        zeilen.append("maximumFramesPerSecond \(bildschirm.maximumFramesPerSecond), gemessen \(gemessen) Bilder/s, Zähler \(bilderGesamt)")
        zeilen.append("Uhr \(uhr.string(from: jetzt))")
        zeilen.append("Szene \(Zustand.shared.tvSzenenZustand) seit \(Protokoll.shared.uhrzeit(Zustand.shared.tvSzenenSeit))")
        text.text = zeilen.joined(separator: "\n")
    }

    override func draw(_ rect: CGRect) {
        let skala = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        let pixel = 1 / skala
        let b = bounds
        UIColor.black.setFill()
        UIRectFill(b)

        // Rahmenlinie: 2 Pixel genau an allen vier Kanten.
        let linie = 2 * pixel
        UIColor.white.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: b.width, height: linie))
        UIRectFill(CGRect(x: 0, y: b.height - linie, width: b.width, height: linie))
        UIRectFill(CGRect(x: 0, y: 0, width: linie, height: b.height))
        UIRectFill(CGRect(x: b.width - linie, y: 0, width: linie, height: b.height))

        // Eckmarken: rote Winkel direkt innen an der Rahmenlinie.
        let laenge = min(b.width, b.height) * 0.08
        let dicke = 8 * pixel
        let ecken: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: linie, y: linie), 1, 1),
            (CGPoint(x: b.width - linie, y: linie), -1, 1),
            (CGPoint(x: linie, y: b.height - linie), 1, -1),
            (CGPoint(x: b.width - linie, y: b.height - linie), -1, -1),
        ]
        UIColor.red.setFill()
        for (punkt, sx, sy) in ecken {
            UIRectFill(CGRect(x: punkt.x, y: punkt.y, width: sx * laenge, height: sy * dicke).standardized)
            UIRectFill(CGRect(x: punkt.x, y: punkt.y, width: sx * dicke, height: sy * laenge).standardized)
        }

        // Hilfsrahmen bei 5 und 10 Prozent: zeigen auf dem Foto, wie viel Overscan abschneidet.
        UIColor(white: 0.45, alpha: 1).setStroke()
        for anteil: CGFloat in [0.05, 0.10] {
            let pfad = UIBezierPath(rect: b.insetBy(dx: b.width * anteil, dy: b.height * anteil))
            pfad.lineWidth = linie
            pfad.stroke()
        }

        // 16:9-Rahmen mit Kreis: Ein verzerrter Kreis zeigt ein falsches Seitenverhaeltnis.
        let hoehe = min(b.height, b.width * 9 / 16) * 0.6
        let breite = hoehe * 16 / 9
        UIColor.cyan.setStroke()
        let rahmen = UIBezierPath(rect: CGRect(x: (b.width - breite) / 2, y: (b.height - hoehe) / 2, width: breite, height: hoehe))
        rahmen.lineWidth = linie
        rahmen.stroke()
        let kreis = UIBezierPath(ovalIn: CGRect(x: b.midX - hoehe / 2, y: b.midY - hoehe / 2, width: hoehe, height: hoehe))
        kreis.lineWidth = linie
        kreis.stroke()
    }
}

/// Haelt das Testbild schwach; `CADisplayLink` haelt sein Ziel stark.
@MainActor
private final class SchwachesZiel: NSObject {
    weak var ziel: Testbild?

    init(_ ziel: Testbild) {
        self.ziel = ziel
        super.init()
    }

    @objc func tick(_ link: CADisplayLink) {
        ziel?.tick()
    }
}

private func overscanText(_ art: UIScreen.OverscanCompensation) -> String {
    switch art {
    case .scale: return "scale"
    case .insetBounds: return "insetBounds"
    case .none: return "none"
    @unknown default: return "unbekannt"
    }
}
