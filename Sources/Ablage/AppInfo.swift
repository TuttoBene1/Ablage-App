import AppKit

@MainActor
enum AppInfo {
    static let website = URL(string: "https://webforging.de")!
    static let repository = URL(string: "https://github.com/TuttoBene1/Ablage-App")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// Standard macOS “About” window with credits linking to Webforging and the repository.
    static func showAbout() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(string: "Bildschirmfoto, Bildschirmaufnahme & Zwischenablage.\nEntwickelt von ", attributes: base)
        var link = base
        link[.link] = website
        credits.append(NSAttributedString(string: "Webforging", attributes: link))
        credits.append(NSAttributedString(string: " · ", attributes: base))
        link[.link] = repository
        credits.append(NSAttributedString(string: "GitHub", attributes: link))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Ablage",
            .applicationVersion: version,
            .credits: credits,
        ])
    }
}
