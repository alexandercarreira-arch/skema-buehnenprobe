import UIKit

/// Delegate der TV-Szene, Rolle `windowExternalDisplayNonInteractive` (Bauzettel 45, § 3.3).
/// Haengt ein Fenster an und ab, schaltet zwischen Testbild, Buehne und Aus und protokolliert
/// jeden Zustand der Szene mit Uhrzeit (UM11).
@MainActor
final class TvSzene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private weak var szene: UIWindowScene?
    private var tv: TvController?
    private var testbild: Testbild?
    private var angezeigt: TvInhalt?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            Protokoll.shared.schreibe("TV: Szene ist keine UIWindowScene")
            return
        }
        szene = windowScene
        let bildschirm = windowScene.screen
        Protokoll.shared.schreibe("Szene verbunden: TV (\(session.configuration.name ?? "ohne Namen"), Rolle \(session.role.rawValue)), Bildschirm \(groesse(bildschirm.bounds.size)) pt, scale \(zahl(bildschirm.scale)), Zustand \(zustandText(windowScene.activationState))")
        Zustand.shared.setzeTvSzene(zustandText(windowScene.activationState))
        NotificationCenter.default.addObserver(self, selector: #selector(zustandGeaendert), name: Zustand.geaendert, object: nil)
        // Vor dem ersten Fenster, bei jedem Verbinden und Wiederverbinden (jede Verbindung ist eine neue Szene).
        wendeOverscanAn("beim Verbinden")
        wendeInhaltAn()
    }

    /// Setzt `overscanCompensation` am Bildschirm der Szene auf den gewaehlten Wert. Apple: „For an external
    /// screen, this property sets the desired technique to compensate for overscan"; `.scale` skaliert den
    /// fertigen Framebuffer, `.insetBounds` verkleinert die Bounds, `.none` skaliert nicht.
    private func wendeOverscanAn(_ anlass: String) {
        guard let windowScene = szene else {
            return
        }
        let bildschirm = windowScene.screen
        let vorher = bildschirm.overscanCompensation
        let soll = Zustand.shared.overscan
        if vorher != soll {
            bildschirm.overscanCompensation = soll
        }
        Protokoll.shared.schreibe("TV Overscan \(overscanText(vorher)) → \(overscanText(bildschirm.overscanCompensation)) (\(anlass)): \(bildschirmText(bildschirm, fenster: window))")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        NotificationCenter.default.removeObserver(self)
        nimmFensterAb(grund: "Szene getrennt")
        szene = nil
        Zustand.shared.setzeTvSzene("nicht verbunden")
        Protokoll.shared.schreibe("Szene getrennt: TV")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        melde("willEnterForeground", scene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        melde("didBecomeActive", scene)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        melde("willResignActive", scene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        melde("didEnterBackground", scene)
    }

    private func melde(_ ereignis: String, _ scene: UIScene) {
        Zustand.shared.setzeTvSzene(zustandText(scene.activationState))
        Protokoll.shared.schreibe("TV: \(ereignis), Zustand \(zustandText(scene.activationState))")
    }

    @objc private func zustandGeaendert() {
        if szene?.screen.overscanCompensation != Zustand.shared.overscan {
            wendeOverscanAn("Knopf")
        }
        wendeInhaltAn()
    }

    private func wendeInhaltAn() {
        guard let windowScene = szene else {
            return
        }
        let inhalt = Zustand.shared.tvInhalt
        if inhalt == .aus {
            nimmFensterAb(grund: "Aus")
            return
        }
        if window != nil, angezeigt == inhalt {
            return
        }
        let ziel = tv ?? haengeFensterAn(windowScene)
        switch inhalt {
        case .testbild:
            let bild = testbild ?? Testbild(frame: .zero)
            testbild = bild
            ziel.zeige(bild, mitStatus: false)
        case .buehne:
            let buehne = Zustand.shared.buehne()
            ziel.zeige(buehne.webView, mitStatus: true)
            ziel.view.layoutIfNeeded()
            buehne.messeGeometrie("am TV angehängt", erzwungen: true)
        case .aus:
            break
        }
        angezeigt = inhalt
        Protokoll.shared.schreibe("TV zeigt: \(inhalt.rawValue)")
    }

    private func haengeFensterAn(_ windowScene: UIWindowScene) -> TvController {
        let neu = TvController()
        let fenster = UIWindow(windowScene: windowScene)
        fenster.rootViewController = neu
        window = fenster
        tv = neu
        fenster.makeKeyAndVisible()
        Protokoll.shared.schreibe("TV: Fenster angehängt, \(groesse(fenster.bounds.size)) pt")
        return neu
    }

    /// „Aus": Fenster ab, damit das System wieder spiegelt (NB1, P1).
    private func nimmFensterAb(grund: String) {
        guard let fenster = window else {
            return
        }
        tv?.beende()
        fenster.isHidden = true
        window = nil
        tv = nil
        angezeigt = nil
        Protokoll.shared.schreibe("TV: Fenster abgenommen (\(grund))")
    }
}

/// Wurzel des TV-Fensters: zeigt randlos eine Ansicht und, fuer die Buehne, unten rechts einen
/// kleinen Text mit rAF, visibilityState und dem Zustand der Szene (P4).
@MainActor
final class TvController: UIViewController {
    private var inhalt: UIView?
    private let status = UILabel()
    private var takt: Takt?
    private var letzteBildschirmZeile = ""

    override func loadView() {
        let grund = UIView()
        grund.backgroundColor = .black
        view = grund
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        status.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        status.textColor = UIColor(white: 1, alpha: 0.6)
        status.backgroundColor = UIColor(white: 0, alpha: 0.35)
        status.isHidden = true
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
        takt = Takt(intervall: 1) { [weak self] in
            self?.aktualisiereStatus()
        }
    }

    /// Jede Aenderung von Bildschirm und Fenster (etwa nach dem Umschalten des Overscan) und jede
    /// Groessenaenderung der Buehne ins Log, jeweils nur Wechsel.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let fenster = view.window, let bildschirm = fenster.windowScene?.screen {
            let zeile = bildschirmText(bildschirm, fenster: fenster)
            if zeile != letzteBildschirmZeile {
                letzteBildschirmZeile = zeile
                Protokoll.shared.schreibe("TV Bildschirm (Layout): \(zeile)")
            }
        }
        if let buehne = Zustand.shared.buehneWeb, inhalt === buehne.webView {
            buehne.messeGeometrie("Layout am TV")
        }
    }

    func zeige(_ neu: UIView, mitStatus: Bool) {
        loadViewIfNeeded()
        if inhalt !== neu {
            inhalt?.removeFromSuperview()
            neu.removeFromSuperview()
            neu.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(neu, belowSubview: status)
            NSLayoutConstraint.activate([
                neu.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                neu.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                neu.topAnchor.constraint(equalTo: view.topAnchor),
                neu.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            inhalt = neu
        }
        status.isHidden = !mitStatus
        aktualisiereStatus()
    }

    func beende() {
        takt?.stopp()
        takt = nil
        inhalt?.removeFromSuperview()
        inhalt = nil
    }

    private func aktualisiereStatus() {
        guard !status.isHidden else {
            return
        }
        let buehne = Zustand.shared.buehneWeb?.statusText ?? "keine Bühne"
        status.text = " \(buehne) · Szene \(Zustand.shared.tvSzenenZustand) "
    }
}
