import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Configuration

private let kQueueDir = "\(NSHomeDirectory())/.claude-notifier/queue"
private let kReminderInterval: TimeInterval = 30
private let kAlertTimeout = 10 // seconds before auto-dismiss

// MARK: - Notification Types

struct OptionItem {
    let label: String
    let keystroke: String
}

struct NotificationData {
    let title: String
    let body: String
    let type: String // "alert", "ask", "permission"
    let options: [OptionItem]
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var dirMonitorSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var reminderTimer: Timer?
    private var reminderEnabled = true
    private var unreadCount = 0
    private var history: [(title: String, body: String, date: Date)] = []
    private var currentAlertWindow: NSWindow?
    private var isProcessingAlert = false
    private var processedFiles = Set<String>()
    private var isCheckingNotifications = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureQueueDirectory()
        setupMenuBar()
        startDirectoryMonitor()
        checkForNotifications()

        // Close alert when app is deactivated (user switched to Terminal)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func appDidResignActive() {
        // Close any open alert when user switches away (only if alert is waiting for input)
        if isProcessingAlert, let window = currentAlertWindow {
            isProcessingAlert = false
            NSApp.abortModal()
            window.close()
            currentAlertWindow = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopDirectoryMonitor()
        stopReminder()
    }

    // MARK: Queue Directory

    private func ensureQueueDirectory() {
        try? FileManager.default.createDirectory(
            atPath: kQueueDir,
            withIntermediateDirectories: true
        )
    }

    // MARK: Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshIcon()
        rebuildMenu()
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }

        let symbolName = unreadCount > 0
            ? "bubble.left.and.exclamationmark.bubble.right.fill"
            : "bubble.left.and.bubble.right"
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = img.withSymbolConfiguration(config)
        }
        button.title = unreadCount > 0 ? " \(unreadCount)" : ""
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Claude \u{C54C}\u{B9AC}\u{BBF8}", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if !history.isEmpty {
            let label = NSMenuItem(title: "\u{CD5C}\u{ADF8}\u{C54C}\u{B9BC}", action: nil, keyEquivalent: "")
            label.isEnabled = false
            menu.addItem(label)

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"

            for entry in history.suffix(5).reversed() {
                let time = formatter.string(from: entry.date)
                let text = "[\(time)] \(entry.body)"
                let item = NSMenuItem(title: String(text.prefix(60)), action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.indentationLevel = 1
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem(title: "\u{D130}\u{BBF8}\u{B110} \u{C5F4}\u{AE30}", action: #selector(openTerminal), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "\u{D14C}\u{C2A4}\u{D2B8} \u{C54C}\u{B9BC}", action: #selector(sendTest), keyEquivalent: ""))
        menu.addItem(.separator())

        let reminderItem = NSMenuItem(
            title: "30\u{CD08}\u{B9C8}\u{B2E4} \u{BC18}\u{BCF5} \u{C54C}\u{B9BC}",
            action: #selector(toggleReminder),
            keyEquivalent: ""
        )
        reminderItem.state = reminderEnabled ? .on : .off
        menu.addItem(reminderItem)

        if unreadCount > 0 {
            menu.addItem(NSMenuItem(title: "\u{C77D}\u{C74C} \u{CC98}\u{B9AC} (\(unreadCount))", action: #selector(clearBadge), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "\u{C885}\u{B8CC}", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: Directory Monitor

    private func startDirectoryMonitor() {
        dirFD = open(kQueueDir, O_EVTONLY)
        guard dirFD >= 0 else {
            NSLog("[ClaudeNotifier] Cannot watch %@, falling back to polling", kQueueDir)
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                self?.checkForNotifications()
            }
            return
        }

        dirMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: .write,
            queue: .main
        )

        dirMonitorSource?.setEventHandler { [weak self] in
            self?.checkForNotifications()
        }

        dirMonitorSource?.setCancelHandler { [weak self] in
            guard let fd = self?.dirFD, fd >= 0 else { return }
            close(fd)
            self?.dirFD = -1
        }

        dirMonitorSource?.resume()
    }

    private func stopDirectoryMonitor() {
        dirMonitorSource?.cancel()
        dirMonitorSource = nil
    }

    // MARK: Process Notifications

    private func checkForNotifications() {
        // Prevent concurrent processing
        guard !isCheckingNotifications else { return }
        isCheckingNotifications = true
        defer { isCheckingNotifications = false }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: kQueueDir) else { return }

        let files = entries.filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }.sorted()
        guard !files.isEmpty else { return }

        for file in files {
            // Skip if already processed
            guard !processedFiles.contains(file) else { continue }
            processedFiles.insert(file)

            let path = "\(kQueueDir)/\(file)"

            // Read content first
            guard let data = fm.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else {
                try? fm.removeItem(atPath: path)
                continue
            }

            // Remove file immediately to prevent duplicate processing
            try? fm.removeItem(atPath: path)

            let notification = parse(text)

            switch notification.type {
            case "ask":
                showOptionsAlert(data: notification)
            case "permission":
                showPermissionAlert(data: notification)
            default:
                showSimpleAlert(title: notification.title, body: notification.body)
            }

            history.append((title: notification.title, body: notification.body, date: Date()))
            if history.count > 20 {
                history.removeFirst(history.count - 20)
            }

            unreadCount += 1

            // Clean up processedFiles set periodically
            if processedFiles.count > 100 {
                processedFiles.removeAll()
            }
        }

        refreshIcon()
        rebuildMenu()
        startReminderIfNeeded()
    }

    private func parse(_ text: String) -> NotificationData {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let lines = text.components(separatedBy: "\n")
            let title = lines.first ?? "Claude Code"
            let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return NotificationData(
                title: title,
                body: body.isEmpty ? "Action required" : body,
                type: "alert",
                options: []
            )
        }

        let title = json["title"] as? String ?? "Claude Code"
        let body = json["body"] as? String ?? "Action required"
        let type = json["type"] as? String ?? "alert"

        var options: [OptionItem] = []
        if let optionsArray = json["options"] as? [[String: String]] {
            for opt in optionsArray {
                if let label = opt["label"], let keystroke = opt["keystroke"] {
                    options.append(OptionItem(label: label, keystroke: keystroke))
                }
            }
        }

        return NotificationData(title: title, body: body, type: type, options: options)
    }

    // MARK: Alerts

    private func showSimpleAlert(title: String, body: String) {
        let escaped = { (s: String) -> String in
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let script = "display alert \"\(escaped(title))\" message \"\(escaped(body))\" giving up after \(kAlertTimeout)"

        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    private func showPermissionAlert(data: NotificationData) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = data.title
            alert.informativeText = data.body
            alert.alertStyle = .informational

            // Use options from notification data, fallback to Yes/No
            let options = data.options.isEmpty
                ? [OptionItem(label: "Yes", keystroke: "y"), OptionItem(label: "No", keystroke: "n")]
                : data.options

            for option in options {
                alert.addButton(withTitle: option.label)
            }

            // Store reference so we can close it if user switches away
            self.currentAlertWindow = alert.window
            self.isProcessingAlert = true

            let response = alert.runModal()

            // Clear state
            let wasProcessing = self.isProcessingAlert
            self.isProcessingAlert = false
            self.currentAlertWindow = nil
            alert.window.orderOut(nil)
            NSApp.hide(nil)

            // Only send keystroke if user clicked a button (not if dismissed by switching apps)
            let buttonIndex = response.rawValue - 1000  // NSAlertFirstButtonReturn = 1000
            guard wasProcessing && buttonIndex >= 0 && buttonIndex < options.count else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let keystroke = options[buttonIndex].keystroke
                self.sendKeystroke(keystroke)
            }
        }
    }

    private func showOptionsAlert(data: NotificationData) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = data.title
            alert.informativeText = data.body
            alert.alertStyle = .informational

            // Add buttons for each option (max 4, plus Other button)
            let options = Array(data.options.prefix(4))
            for option in options {
                alert.addButton(withTitle: option.label)
            }

            // Add "Other..." button for custom input
            alert.addButton(withTitle: "Other...")

            // Store reference so we can close it if user switches away
            self.currentAlertWindow = alert.window
            self.isProcessingAlert = true

            let response = alert.runModal()

            // Clear state
            let wasProcessing = self.isProcessingAlert
            self.isProcessingAlert = false
            self.currentAlertWindow = nil
            alert.window.orderOut(nil)
            NSApp.hide(nil)

            guard wasProcessing else { return }

            let buttonIndex = response.rawValue - 1000  // NSAlertFirstButtonReturn = 1000

            // "Other..." clicked - just activate Terminal for custom input
            if buttonIndex == options.count {
                if let terminalApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
                    terminalApp.activate(options: .activateIgnoringOtherApps)
                }
                return
            }

            // Send keystroke if user clicked an option button
            guard buttonIndex >= 0 && buttonIndex < options.count else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let keystroke = options[buttonIndex].keystroke
                self.sendKeystroke(keystroke)
            }
        }
    }

    private func sendKeystroke(_ key: String) {
        // Check accessibility permissions first
        let trusted = AXIsProcessTrusted()
        if !trusted {
            NSLog("[ClaudeNotifier] Accessibility permission not granted. Requesting...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            return
        }

        // Activate Terminal first
        if let terminalApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
            terminalApp.activate(options: .activateIgnoringOtherApps)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.postKeyEvents(for: key)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.postReturnKey()
            }
        }
    }

    private func postKeyEvents(for string: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        for char in string {
            guard let asciiValue = char.asciiValue else { continue }

            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                var unichar = UniChar(asciiValue)
                keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    private func postReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func playSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            proc.arguments = ["/System/Library/Sounds/Ping.aiff"]
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    // MARK: Reminder

    private func startReminderIfNeeded() {
        guard reminderEnabled, unreadCount > 0, reminderTimer == nil else { return }
        reminderTimer = Timer.scheduledTimer(withTimeInterval: kReminderInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.unreadCount > 0 else { return }
            self.playSound()
        }
    }

    private func stopReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
    }

    // MARK: Menu Actions

    @objc private func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    @objc private func sendTest() {
        showSimpleAlert(title: "Claude Code", body: "\u{D14C}\u{C2A4}\u{D2B8} - \u{C54C}\u{B9BC}\u{C774} \u{C815}\u{C0C1} \u{C791}\u{B3D9}\u{D569}\u{B2C8}\u{B2E4}!")
        unreadCount += 1
        history.append((title: "Claude Code", body: "\u{D14C}\u{C2A4}\u{D2B8} \u{C54C}\u{B9BC}", date: Date()))
        refreshIcon()
        rebuildMenu()
        startReminderIfNeeded()
    }

    @objc private func toggleReminder() {
        reminderEnabled.toggle()
        if reminderEnabled {
            startReminderIfNeeded()
        } else {
            stopReminder()
        }
        rebuildMenu()
    }

    @objc private func clearBadge() {
        unreadCount = 0
        stopReminder()
        refreshIcon()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
