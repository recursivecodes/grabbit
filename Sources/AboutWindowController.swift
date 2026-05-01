import AppKit

class AboutWindowController: NSWindowController {

    private static var shared: AboutWindowController?

    static func show() {
        if shared == nil {
            shared = AboutWindowController()
        }
        shared?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "About Grabbit"
        win.center()
        win.isReleasedWhenClosed = false

        super.init(window: win)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        // App icon
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Grabbit")
        nameLabel.font = .boldSystemFont(ofSize: 20)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(nameLabel)

        // Version from bundle
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionLabel = NSTextField(labelWithString: version.isEmpty ? "" : "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(versionLabel)

        // Description
        let descLabel = NSTextField(wrappingLabelWithString:
            "A lightweight, open source macOS screenshot and annotation tool that lives in your " +
            "menu bar. Trigger a capture with a global hotkey, draw a selection, then annotate " +
            "and export — all without touching the Dock.")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(descLabel)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(divider)

        // Links row
        let githubButton = makeLink(title: "View on GitHub",
                                    url: "https://github.com/recursivecodes/grabbit")
        cv.addSubview(githubButton)

        let coffeeButton = makeLink(title: "☕  Buy Me a Coffee",
                                    url: "https://buymeacoffee.com/toddraymont")
        cv.addSubview(coffeeButton)

        // Close button
        let closeButton = NSButton(title: "Close", target: self, action: #selector(close))
        closeButton.keyEquivalent = "\r"
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(closeButton)

        // Layout
        NSLayoutConstraint.activate([
            // Icon
            iconView.topAnchor.constraint(equalTo: cv.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            // Name
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            // Version
            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            versionLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Description
            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 12),
            descLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 24),
            descLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -24),

            // Divider
            divider.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 16),
            divider.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            divider.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            // Links — side by side, centred below divider
            githubButton.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 12),
            githubButton.trailingAnchor.constraint(equalTo: cv.centerXAnchor, constant: -12),

            coffeeButton.centerYAnchor.constraint(equalTo: githubButton.centerYAnchor),
            coffeeButton.leadingAnchor.constraint(equalTo: cv.centerXAnchor, constant: 12),

            // Close button — below links with breathing room
            closeButton.topAnchor.constraint(equalTo: githubButton.bottomAnchor, constant: 16),
            closeButton.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
        ])
    }

    private func makeLink(title: String, url: String) -> NSButton {
        let btn = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.identifier = NSUserInterfaceItemIdentifier(url)
        btn.translatesAutoresizingMaskIntoConstraints = false

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: 12),
        ]
        btn.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        return btn
    }

    // MARK: - Actions

    @objc private func openLink(_ sender: NSButton) {
        guard let urlString = sender.identifier?.rawValue,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
