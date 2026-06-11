import AppKit

/// Manages the status bar item with system metrics display.
class StatusBarController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hostingView: NSView?

    let networkMonitor = NetworkMonitor()
    let diskMonitor = DiskMonitor()
    let smcMonitor = SMCMonitor()

    // MARK: - Text Fields

    private let downloadText = createLabel()
    private let uploadText = createLabel()
    private let diskText = createLabel()
    private let tempText = createLabel()
    private let fanText = createLabel()

    private static func createLabel() -> NSTextField {
        let tf = NSTextField(labelWithString: "---")
        tf.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        tf.lineBreakMode = .byClipping
        tf.cell?.truncatesLastVisibleLine = false
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        return tf
    }

    private static func createSeparator() -> NSTextField {
        let tf = NSTextField(labelWithString: "|")
        tf.font = NSFont.systemFont(ofSize: 11, weight: .light)
        tf.textColor = .separatorColor
        return tf
    }

    // MARK: - Application Delegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let barHeight = NSStatusBar.system.thickness
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: barHeight))

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 5
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        // Network
        stackView.addArrangedSubview(createSymbolView("arrow.down.circle.fill", fallback: "↓"))
        stackView.addArrangedSubview(downloadText)
        stackView.addArrangedSubview(createSymbolView("arrow.up.circle.fill", fallback: "↑"))
        stackView.addArrangedSubview(uploadText)
        stackView.addArrangedSubview(Self.createSeparator())

        // Disk
        stackView.addArrangedSubview(createSymbolView("internaldrive.fill", fallback: "▣"))
        stackView.addArrangedSubview(diskText)
        stackView.addArrangedSubview(Self.createSeparator())

        // Temperature
        stackView.addArrangedSubview(createSymbolView("thermometer", fallback: "T"))
        stackView.addArrangedSubview(tempText)
        stackView.addArrangedSubview(Self.createSeparator())

        // Fan
        stackView.addArrangedSubview(createSymbolView("wind", fallback: "≋"))
        stackView.addArrangedSubview(fanText)

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        view.wantsLayer = true

        if let button = statusItem.button {
            button.addSubview(view)
            button.frame = view.frame
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        hostingView = view

        // Add menu for right-click
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "关于 系统状态监视器", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu

        // Start monitors
        networkMonitor.start()
        diskMonitor.start()
        smcMonitor.start()

        // Periodic display update
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateDisplay()
            }
        }
    }

    private func createSymbolView(_ symbolName: String, fallback: String) -> NSView {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let imageView = NSImageView(image: image)
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            imageView.contentTintColor = .secondaryLabelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 13),
                imageView.heightAnchor.constraint(equalToConstant: 13)
            ])
            imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
            return imageView
        }

        let tf = NSTextField(labelWithString: fallback)
        tf.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        tf.textColor = .secondaryLabelColor
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        return tf
    }

    // MARK: - Display Update

    private func updateDisplay() {
        downloadText.stringValue = networkMonitor.downloadSpeed
        uploadText.stringValue = networkMonitor.uploadSpeed
        diskText.stringValue = "\(diskMonitor.diskUsage)"

        if smcMonitor.cpuTemperature != "N/A" && smcMonitor.cpuTemperature != "---" {
            tempText.stringValue = "\(smcMonitor.cpuTemperature)"
        } else {
            tempText.stringValue = "N/A"
        }

        if smcMonitor.fanSpeed != "N/A" && smcMonitor.fanSpeed != "---" {
            fanText.stringValue = "\(smcMonitor.fanSpeed)"
        } else {
            fanText.stringValue = "N/A"
        }

        // Auto-resize
        if let view = hostingView {
            view.layoutSubtreeIfNeeded()
            let contentWidth = view.subviews.first?.fittingSize.width ?? view.fittingSize.width
            let width = ceil(max(contentWidth + 12, 280))
            view.frame.size.width = width
            statusItem.length = width
            statusItem.button?.frame = view.frame
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        // Left click: toggle menu visibility is handled by statusItem.menu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "系统状态监视器"
        alert.informativeText = """
        版本 1.0

        在状态栏显示:
        • 网络上传/下载速度
        • 磁盘占用百分比
        • CPU 温度 (Intel: SMC / Apple Silicon: HID PMU)
        • 风扇转速 (通过 SMC，可用时显示)

        基于 IOKit 读取硬件传感器数据。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quitApp() {
        networkMonitor.stop()
        diskMonitor.stop()
        smcMonitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
