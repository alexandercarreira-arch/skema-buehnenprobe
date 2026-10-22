import UIKit
import os

/// Einstieg der Probe S1-H (Bauzettel 45, § 3.1). Gibt je Rolle die Konfiguration aus dem
/// Szenen-Manifest zurueck und protokolliert einmal je Minute Bildraten, Akku, Waerme und Speicher.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var minutenTakt: Takt?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Protokoll.shared.schreibe("Start: \(bauText()), iPadOS \(UIDevice.current.systemVersion)")
        UIDevice.current.isBatteryMonitoringEnabled = true
        let zentrale = NotificationCenter.default
        zentrale.addObserver(self, selector: #selector(akkuGeaendert), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        zentrale.addObserver(self, selector: #selector(waermeGeaendert), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        minutenTakt = Takt(intervall: 60) { [weak self] in
            self?.minutenbericht()
        }
        Protokoll.shared.schreibe("Akku: \(akkuText()); Wärme: \(waermeText(ProcessInfo.processInfo.thermalState))")
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let rolle = connectingSceneSession.role
        let name = rolle == .windowExternalDisplayNonInteractive ? "TV" : "Regie"
        Protokoll.shared.schreibe("Szene angefragt: Rolle \(rolle.rawValue), Konfiguration \(name)")
        return UISceneConfiguration(name: name, sessionRole: rolle)
    }

    @objc private func akkuGeaendert() {
        Protokoll.shared.schreibe("Akku: \(akkuText())")
    }

    /// Die Meldung kann auf einem beliebigen Thread kommen; hier wird nur gelesen und protokolliert.
    @objc nonisolated private func waermeGeaendert() {
        Protokoll.shared.schreibe("Wärme: \(waermeText(ProcessInfo.processInfo.thermalState))")
    }

    private func minutenbericht() {
        let zustand = Zustand.shared
        let freiMB = os_proc_available_memory() / 1_048_576
        let regie = zustand.regieWeb?.minutenWerte() ?? "Regie ohne Web-Ansicht"
        let buehne = zustand.buehneWeb?.minutenWerte() ?? "Bühne ohne Web-Ansicht"
        Protokoll.shared.schreibe("Minute: \(regie); \(buehne); Akku \(akkuText()); Wärme \(waermeText(ProcessInfo.processInfo.thermalState)); frei \(freiMB) MB; Neuladungen \(zustand.neuladungen); TV \(zustand.tvInhalt.rawValue), Szene \(zustand.tvSzenenZustand)")
    }
}

/// Delegate der Hauptszene (Regie).
@MainActor
final class RegieSzene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            Protokoll.shared.schreibe("Regie: Szene ist keine UIWindowScene")
            return
        }
        let fenster = UIWindow(windowScene: windowScene)
        fenster.rootViewController = RegieController()
        window = fenster
        fenster.makeKeyAndVisible()
        Protokoll.shared.schreibe("Szene verbunden: Regie (\(session.configuration.name ?? "ohne Namen")), \(bauText())")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Protokoll.shared.schreibe("Szene getrennt: Regie")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Protokoll.shared.schreibe("Regie: willEnterForeground")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Protokoll.shared.schreibe("Regie: didBecomeActive")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Protokoll.shared.schreibe("Regie: willResignActive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Protokoll.shared.schreibe("Regie: didEnterBackground")
    }
}
