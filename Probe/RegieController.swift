import UIKit
import WebKit

/// Hauptszene, die Regie (Bauzettel 45, § 3.2): oben die Leiste mit Testbild, Bühne, Aus, Wach
/// und dem Adressfeld, darunter /cockpit ueber die volle Breite, unten das Log mit „Kopieren".
@MainActor
final class RegieController: UIViewController, UITextFieldDelegate {
    private static let logHoeheOffen: CGFloat = 112

    private var web: WebAnsicht?
    private let adressFeld = UITextField()
    private var inhaltKnoepfe: [(TvInhalt, UIButton)] = []
    private var wachKnopf: UIButton?
    private var overscanKnopf: UIButton?
    private var logSchalter: UIButton?
    private let logAnsicht = UITextView()
    private var logHoehe: NSLayoutConstraint?
    private var logOffen = true
    private var logGeplant = false
    /// Nur mit Xcode 27 im Bau (E6): die `UISceneAccessoryRegistration`. Als `AnyObject` gehalten,
    /// weil eine gespeicherte Eigenschaft nicht hinter `#available` stehen kann.
    private var tvRegistrierung: AnyObject?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let web = WebAnsicht(rolle: .regie)
        self.web = web
        Zustand.shared.regieWeb = web

        let leiste = UIStackView()
        leiste.axis = .horizontal
        leiste.spacing = 8
        leiste.alignment = .center
        for inhalt in TvInhalt.allCases {
            let knopf = macheKnopf(inhalt.rawValue) { [weak self] in
                self?.waehle(inhalt)
            }
            inhaltKnoepfe.append((inhalt, knopf))
            leiste.addArrangedSubview(knopf)
        }
        let wach = macheKnopf("Wach") { [weak self] in
            self?.schalteWach()
        }
        wachKnopf = wach
        leiste.addArrangedSubview(wach)
        let overscan = macheKnopf("Overscan") { [weak self] in
            self?.schalteOverscan()
        }
        overscanKnopf = overscan
        leiste.addArrangedSubview(overscan)

        adressFeld.text = Zustand.shared.adresse
        adressFeld.borderStyle = .roundedRect
        adressFeld.keyboardType = .URL
        adressFeld.autocapitalizationType = .none
        adressFeld.autocorrectionType = .no
        adressFeld.spellCheckingType = .no
        adressFeld.returnKeyType = .go
        adressFeld.clearButtonMode = .whileEditing
        adressFeld.delegate = self
        adressFeld.setContentHuggingPriority(.defaultLow, for: .horizontal)
        adressFeld.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leiste.addArrangedSubview(adressFeld)
        leiste.addArrangedSubview(macheKnopf("Laden") { [weak self] in
            self?.laden()
        })

        let logLeiste = UIStackView()
        logLeiste.axis = .horizontal
        logLeiste.spacing = 8
        logLeiste.alignment = .center
        let schalter = macheKnopf("Log") { [weak self] in
            self?.schalteLog()
        }
        logSchalter = schalter
        logLeiste.addArrangedSubview(schalter)
        logLeiste.addArrangedSubview(macheKnopf("Kopieren") { [weak self] in
            self?.kopieren()
        })
        let bau = UILabel()
        bau.text = bauText()
        bau.font = .preferredFont(forTextStyle: .footnote)
        bau.textColor = .secondaryLabel
        bau.textAlignment = .right
        bau.setContentHuggingPriority(.defaultLow, for: .horizontal)
        logLeiste.addArrangedSubview(bau)

        logAnsicht.isEditable = false
        logAnsicht.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logAnsicht.backgroundColor = .secondarySystemBackground
        logAnsicht.layer.cornerRadius = 8

        let webView = web.webView
        for teil in [leiste, webView, logLeiste, logAnsicht] as [UIView] {
            teil.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(teil)
        }
        let rand = view.safeAreaLayoutGuide
        let hoehe = logAnsicht.heightAnchor.constraint(equalToConstant: RegieController.logHoeheOffen)
        logHoehe = hoehe
        NSLayoutConstraint.activate([
            leiste.topAnchor.constraint(equalTo: rand.topAnchor, constant: 8),
            leiste.leadingAnchor.constraint(equalTo: rand.leadingAnchor, constant: 12),
            leiste.trailingAnchor.constraint(equalTo: rand.trailingAnchor, constant: -12),
            webView.topAnchor.constraint(equalTo: leiste.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            logLeiste.topAnchor.constraint(equalTo: webView.bottomAnchor, constant: 6),
            logLeiste.leadingAnchor.constraint(equalTo: rand.leadingAnchor, constant: 12),
            logLeiste.trailingAnchor.constraint(equalTo: rand.trailingAnchor, constant: -12),
            logAnsicht.topAnchor.constraint(equalTo: logLeiste.bottomAnchor, constant: 6),
            logAnsicht.leadingAnchor.constraint(equalTo: rand.leadingAnchor, constant: 12),
            logAnsicht.trailingAnchor.constraint(equalTo: rand.trailingAnchor, constant: -12),
            logAnsicht.bottomAnchor.constraint(equalTo: rand.bottomAnchor, constant: -8),
            hoehe,
        ])

        let zentrale = NotificationCenter.default
        zentrale.addObserver(self, selector: #selector(zustandGeaendert), name: Zustand.geaendert, object: nil)
        zentrale.addObserver(self, selector: #selector(protokollGeaendert), name: Protokoll.geaendert, object: nil)
        registriereTvFuerIPadOS27()
        zeigeZustand()
        aktualisiereLog()
    }

    /// Jede Groessenaenderung der Regie ins Log (nur Wechsel, WebAnsicht.messeGeometrie).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        web?.messeGeometrie("Layout Regie")
    }

    // MARK: Leiste

    private func macheKnopf(_ titel: String, aktion: @escaping () -> Void) -> UIButton {
        var stil = UIButton.Configuration.gray()
        stil.title = titel
        let knopf = UIButton(configuration: stil)
        knopf.addAction(UIAction { _ in aktion() }, for: .touchUpInside)
        knopf.setContentHuggingPriority(.required, for: .horizontal)
        knopf.setContentCompressionResistancePriority(.required, for: .horizontal)
        return knopf
    }

    /// Der Knopf zeigt, was gerade gilt: gefuellt heisst an.
    private func setzeStil(_ knopf: UIButton?, aktiv: Bool) {
        guard let knopf else {
            return
        }
        var stil: UIButton.Configuration = aktiv ? .filled() : .gray()
        stil.title = knopf.configuration?.title
        knopf.configuration = stil
    }

    private func waehle(_ inhalt: TvInhalt) {
        Protokoll.shared.schreibe("Knopf: \(inhalt.rawValue)")
        Zustand.shared.tvInhalt = inhalt
    }

    private func schalteWach() {
        Protokoll.shared.schreibe("Knopf: Wach")
        Zustand.shared.wach.toggle()
    }

    /// Reihum none, scale, insetBounds; wirkt live am Bildschirm der TV-Szene, ohne die Buehne neu zu laden.
    private func schalteOverscan() {
        let neu = Zustand.shared.naechsterOverscan()
        Protokoll.shared.schreibe("Knopf: Overscan \(overscanText(neu))")
        Zustand.shared.overscan = neu
    }

    @objc private func zustandGeaendert() {
        zeigeZustand()
    }

    private func zeigeZustand() {
        let zustand = Zustand.shared
        for (inhalt, knopf) in inhaltKnoepfe {
            setzeStil(knopf, aktiv: inhalt == zustand.tvInhalt)
        }
        setzeStil(wachKnopf, aktiv: zustand.wach)
        setzeStil(logSchalter, aktiv: logOffen)
        if let knopf = overscanKnopf {
            var stil = UIButton.Configuration.gray()
            stil.title = "Overscan \(overscanText(zustand.overscan))"
            knopf.configuration = stil
        }
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let registrierung = tvRegistrierung as? UISceneAccessoryRegistration {
            registrierung.isEnabled = zustand.tvInhalt != .aus
        }
        #endif
    }

    // MARK: Adresse

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        laden()
        return false
    }

    private func laden() {
        adressFeld.resignFirstResponder()
        var text = (adressFeld.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let url = URL(string: text), let schema = url.scheme?.lowercased(), schema == "https" || schema == "http", url.host() != nil else {
            Protokoll.shared.schreibe("Knopf: Laden, Adresse ungültig: \(kurz(text))")
            adressFeld.text = Zustand.shared.adresse
            return
        }
        adressFeld.text = text
        Protokoll.shared.schreibe("Knopf: Laden \(text)")
        Zustand.shared.adresse = text
    }

    // MARK: Log

    @objc private func protokollGeaendert() {
        guard logOffen, !logGeplant else {
            return
        }
        logGeplant = true
        perform(#selector(logJetzt), with: nil, afterDelay: 0.1)
    }

    @objc private func logJetzt() {
        aktualisiereLog()
    }

    private func aktualisiereLog() {
        logGeplant = false
        guard logOffen else {
            return
        }
        logAnsicht.text = Protokoll.shared.letzte(200)
        let laenge = (logAnsicht.text as NSString).length
        if laenge > 0 {
            logAnsicht.scrollRangeToVisible(NSRange(location: laenge - 1, length: 1))
        }
    }

    private func schalteLog() {
        logOffen.toggle()
        logHoehe?.constant = logOffen ? RegieController.logHoeheOffen : 0
        logAnsicht.isHidden = !logOffen
        setzeStil(logSchalter, aktiv: logOffen)
        Protokoll.shared.schreibe("Knopf: Log \(logOffen ? "offen" : "zu")")
        aktualisiereLog()
    }

    private func kopieren() {
        Protokoll.shared.schreibe("Knopf: Kopieren")
        UIPasteboard.general.string = Protokoll.shared.text()
    }

    // MARK: Weg fuer iPadOS 27 (E6)

    /// Ab iOS 27 kommt die TV-Szene erst nach Registrierung eines Szenen-Zubehoers (Release Note 177015874,
    /// nur fuer Bauten mit SDK 27). Der Code ist nur mit Xcode 27 (Swift 6.4) im Bau und greift nur unter
    /// iPadOS 27; am Hallen-iPad mit 26.5 laeuft er nie. Ungeprueft (RP23).
    private func registriereTvFuerIPadOS27() {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let konfiguration = UISceneConfiguration(name: "TV", sessionRole: .windowExternalDisplayNonInteractive)
            konfiguration.delegateClass = TvSzene.self
            let zubehoer = UISceneAccessory.externalNonInteractive(sceneConfiguration: konfiguration)
            tvRegistrierung = registerSceneAccessory(zubehoer)
            Protokoll.shared.schreibe("iPadOS 27: Szenen-Zubehör für den TV registriert")
        } else {
            Protokoll.shared.schreibe("iPadOS 27: Weg im Bau, unter dieser Fassung nicht genutzt")
        }
        #else
        Protokoll.shared.schreibe("iPadOS 27: Weg nicht im Bau (Compiler vor Swift 6.4)")
        #endif
    }
}
