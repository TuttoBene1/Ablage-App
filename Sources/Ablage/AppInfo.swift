import AppKit

@MainActor
enum AppInfo {
    static let website = URL(string: "https://webforging.de/app-entwicklung")!
    static let repository = URL(string: "https://github.com/TuttoBene1/Ablage-App")!

    static let webforgingLogo: NSImage? = {
        let image = Bundle.main.image(forResource: "WebforgingLogo")
            ?? NSImage(contentsOfFile: "Resources/WebforgingLogo.png")
        image?.isTemplate = true
        return image
    }()

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static func showAbout() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ]
        let credits = NSMutableAttributedString(string: "Screenshots, screen recordings & clipboard history.\nMade by ", attributes: base)
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
