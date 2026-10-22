import UIKit
import WebKit

enum WebRolle: String {
    case regie = "Regie"
    case buehne = "Bühne"

    var pfad: String { self == .regie ? "/cockpit" : "/tv" }
    var kennung: String { self == .regie ? "regie" : "buehne" }
}

/// Eine der beiden WKWebViews (Bauzettel 45, § 3.4 und § 3.5). Beide nutzen den Standard-Datenspeicher
/// und dieselben Einstellungen wie Capacitor, damit P3, P8 und P9 die WebView der spaeteren Huelle messen.
@MainActor
final class WebAnsicht: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let rolle: WebRolle
    let webView: WKWebView

    private(set) var raf = 0
    private(set) var sichtbarkeit = "unbekannt"
    private(set) var fokus = false
    private var letzteMeldung: Date?
    private var still = false
    private var protokollierteStufe: Int?
    private var minutenMeldungen = 0
    private var minutenRafSumme = 0
    private var minutenRafMin = Int.max
    private var takt: Takt?

    init(rolle: WebRolle) {
        self.rolle = rolle
        let inhalt = WKUserContentController()
        inhalt.addUserScript(WKUserScript(source: WebAnsicht.skript(kennung: rolle.kennung), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let konfiguration = WKWebViewConfiguration()
        konfiguration.websiteDataStore = WKWebsiteDataStore.default()
        konfiguration.userContentController = inhalt
        konfiguration.mediaTypesRequiringUserActionForPlayback = []
        konfiguration.allowsInlineMediaPlayback = true
        konfiguration.allowsAirPlayForMediaPlayback = true
        konfiguration.suppressesIncrementalRendering = false
        konfiguration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: konfiguration)
        super.init()
        inhalt.add(SchwacherBote(self), name: "probe")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        NotificationCenter.default.addObserver(self, selector: #selector(adresseGeaendert), name: Zustand.adresseGeaendert, object: nil)
        takt = Takt(intervall: 1) { [weak self] in
            self?.pruefeStille()
        }
        lade()
    }

    func lade() {
        let adresse = Zustand.shared.adresse + rolle.pfad
        guard let url = URL(string: adresse) else {
            Protokoll.shared.schreibe("\(rolle.rawValue): Adresse ungültig: \(adresse)")
            return
        }
        Protokoll.shared.schreibe("\(rolle.rawValue) lädt \(adresse)")
        webView.load(URLRequest(url: url))
    }

    @objc private func adresseGeaendert() {
        lade()
    }

    /// Kurzer Stand fuer den Text unten rechts auf der Buehne.
    var statusText: String {
        var text = "rAF \(raf)/s · \(sichtbarkeit)"
        if let letzte = letzteMeldung {
            let alter = Int(Date().timeIntervalSince(letzte))
            if alter >= 2 {
                text += " · still seit \(alter) s"
            }
        } else {
            text += " · noch keine Meldung"
        }
        return text
    }

    /// Zusammenfassung der letzten Minute fuer das Log; setzt die Zaehler zurueck.
    func minutenWerte() -> String {
        defer {
            minutenMeldungen = 0
            minutenRafSumme = 0
            minutenRafMin = Int.max
        }
        guard minutenMeldungen > 0 else {
            return "\(rolle.rawValue) ohne Meldung"
        }
        return "\(rolle.rawValue) rAF Mittel \(minutenRafSumme / minutenMeldungen)/s, min \(minutenRafMin)/s, \(minutenMeldungen) Meldungen, \(sichtbarkeit)"
    }

    // MARK: Meldungen des eingespielten Skripts

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let daten = message.body as? [String: Any], let art = daten["art"] as? String else {
            return
        }
        switch art {
        case "takt":
            verarbeiteTakt(
                raf: daten["raf"] as? Int ?? -1,
                sichtbar: daten["sichtbar"] as? String ?? "unbekannt",
                fokus: daten["fokus"] as? Bool ?? false
            )
        case "fehler":
            Protokoll.shared.schreibe("\(rolle.rawValue) JS-Fehler: \(kurz(daten["text"] as? String ?? "?")) \(daten["ort"] as? String ?? "")")
        case "paket":
            Protokoll.shared.schreibe("\(rolle.rawValue) Paket: \(daten["namen"] as? String ?? "?") (\(kurz(daten["adresse"] as? String ?? "?")))")
        default:
            Protokoll.shared.schreibe("\(rolle.rawValue): unbekannte Meldung \(art)")
        }
    }

    /// Protokolliert nur Wechsel: Sichtbarkeit, Fokus oder eine andere Stufe der Bildrate.
    private func verarbeiteTakt(raf: Int, sichtbar: String, fokus: Bool) {
        let jetzt = Date()
        if still, let letzte = letzteMeldung {
            Protokoll.shared.schreibe("\(rolle.rawValue): Meldungen wieder da nach \(Int(jetzt.timeIntervalSince(letzte))) s")
        }
        still = false
        letzteMeldung = jetzt
        minutenMeldungen += 1
        minutenRafSumme += raf
        minutenRafMin = min(minutenRafMin, raf)
        let stufe = rafStufe(raf)
        if sichtbar != sichtbarkeit || fokus != self.fokus || stufe != protokollierteStufe {
            Protokoll.shared.schreibe("\(rolle.rawValue): visibilityState \(sichtbar), hasFocus \(fokus ? "ja" : "nein"), rAF \(raf)/s")
            protokollierteStufe = stufe
        }
        self.raf = raf
        sichtbarkeit = sichtbar
        self.fokus = fokus
    }

    private func pruefeStille() {
        guard !still, let letzte = letzteMeldung else {
            return
        }
        let sekunden = Date().timeIntervalSince(letzte)
        if sekunden >= 3 {
            still = true
            Protokoll.shared.schreibe("\(rolle.rawValue): keine Meldung seit \(Int(sekunden)) s (zuletzt \(sichtbarkeit), rAF \(raf)/s)")
        }
    }

    // MARK: WKNavigationDelegate

    /// Immer `.allow`, nie `.download`, wie Capacitor fuer Adressen der Web-App. Protokolliert wird
    /// jede Navigation im Hauptrahmen und jede, die einen Download ausloest (P9).
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let adresse = kurz(navigationAction.request.url?.absoluteString ?? "?")
        let typ = navigationTypText(navigationAction.navigationType)
        if navigationAction.shouldPerformDownload {
            Protokoll.shared.schreibe("\(rolle.rawValue): Navigation mit shouldPerformDownload, Typ \(typ), \(adresse)")
        } else if navigationAction.targetFrame?.isMainFrame ?? false {
            Protokoll.shared.schreibe("\(rolle.rawValue): Navigation, Typ \(typ), \(adresse)")
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Protokoll.shared.schreibe("\(rolle.rawValue) geladen: \(kurz(webView.url?.absoluteString ?? "?"))")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Protokoll.shared.schreibe("\(rolle.rawValue) Fehler beim Laden: \(fehlerText(error))")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Protokoll.shared.schreibe("\(rolle.rawValue) Fehler beim Start der Navigation: \(fehlerText(error))")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Zustand.shared.neuladungen += 1
        Protokoll.shared.schreibe("\(rolle.rawValue): Web-Inhalt beendet, lade neu (Neuladungen gesamt \(Zustand.shared.neuladungen))")
        if webView.url == nil {
            lade()
        } else {
            webView.reload()
        }
    }

    // MARK: WKUIDelegate

    /// `target=_blank` oeffnet in der Probe nichts (Capacitor oeffnet es im System, Bauzettel 45, § 3.4).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        Protokoll.shared.schreibe("\(rolle.rawValue): neues Fenster verlangt, nicht geöffnet: \(kurz(navigationAction.request.url?.absoluteString ?? "?"))")
        return nil
    }

    // MARK: Eingespieltes Skript

    /// Meldet je Sekunde Rolle, visibilityState, hasFocus und rAF-Rueckrufe, dazu globale Fehler
    /// und einmal nach dem Laden den Namen des JS-Pakets. Keine Inhalte der Tafel, keine Eingaben.
    private static func skript(kennung: String) -> String {
        """
        (function () {
          if (window.__probe) { return; }
          window.__probe = true;
          var rolle = "\(kennung)";
          function melde(daten) {
            try { window.webkit.messageHandlers.probe.postMessage(daten); } catch (e) {}
          }
          var bilder = 0;
          function zaehle() { bilder += 1; window.requestAnimationFrame(zaehle); }
          window.requestAnimationFrame(zaehle);
          window.setInterval(function () {
            melde({ art: "takt", rolle: rolle, sichtbar: document.visibilityState, fokus: document.hasFocus(), raf: bilder });
            bilder = 0;
          }, 1000);
          window.addEventListener("error", function (e) {
            melde({ art: "fehler", text: String(e.message || e.type), ort: String(e.filename || "") + ":" + String(e.lineno || 0) + ":" + String(e.colno || 0) });
          });
          window.addEventListener("unhandledrejection", function (e) {
            var grund = e.reason;
            var text = grund && grund.message ? grund.message : String(grund);
            melde({ art: "fehler", text: "unhandledrejection: " + text, ort: "" });
          });
          window.addEventListener("load", function () {
            var namen = [];
            var skripte = document.querySelectorAll("script[src]");
            for (var i = 0; i < skripte.length; i++) {
              var quelle = String(skripte[i].src);
              var stelle = quelle.indexOf("/assets/index-");
              if (stelle >= 0) { namen.push(quelle.substring(stelle + 1)); }
            }
            melde({ art: "paket", namen: namen.length ? namen.join(", ") : "kein assets/index-*.js", adresse: String(location.href) });
          });
        })();
        """
    }
}

/// Haelt den Empfaenger der Skript-Meldungen schwach; `WKUserContentController` haelt seine Boten stark.
@MainActor
private final class SchwacherBote: NSObject, WKScriptMessageHandler {
    weak var ziel: WKScriptMessageHandler?

    init(_ ziel: WKScriptMessageHandler) {
        self.ziel = ziel
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        ziel?.userContentController(userContentController, didReceive: message)
    }
}

private func rafStufe(_ raf: Int) -> Int {
    switch raf {
    case ..<1: return 0
    case 1..<30: return 1
    case 30..<55: return 2
    default: return 3
    }
}

private func navigationTypText(_ typ: WKNavigationType) -> String {
    switch typ {
    case .linkActivated: return "linkActivated"
    case .formSubmitted: return "formSubmitted"
    case .backForward: return "backForward"
    case .reload: return "reload"
    case .formResubmitted: return "formResubmitted"
    case .other: return "other"
    @unknown default: return "unbekannt"
    }
}

private func fehlerText(_ fehler: Error) -> String {
    let ns = fehler as NSError
    return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
}
