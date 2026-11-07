// Stand Up — a tiny menu bar app that reminds you to get up, move and drink water.
// 25 min sitting → reminder → "I'm up" starts a 5 min move break (or snooze 5 min).

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = StandModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private var lastSymbol = ""
    private var lastTitle: String?
    private var autoShown = false
    private var windows: [String: NSWindow] = [:]
    private var windowObservers: [String: NSObjectProtocol] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageLeading
        }

        let hc = NSHostingController(rootView: PopoverView(model: model))
        hc.sizingOptions = .preferredContentSize
        popover.contentViewController = hc
        popover.behavior = .transient
        popover.animates = false

        model.openAnalysis = { [weak self] in self?.showAnalysis() }
        model.openProfile = { [weak self] in self?.showProfile() }

        Publishers.CombineLatest3(model.$phase, model.$seconds, model.$menuBarTime)
            .sink { [weak self] phase, seconds, style in self?.updateButton(phase, seconds, style) }
            .store(in: &bag)

        // When it's time: pop the panel open from the menu bar (without stealing focus),
        // and close it again once you pick "I'm up!" or "Snooze".
        model.$phase.removeDuplicates()
            .sink { [weak self] phase in self?.phaseChanged(phase) }
            .store(in: &bag)

        if !model.profile.isSet {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showProfile() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.flush()
    }

    // MARK: Status item

    private func updateButton(_ phase: Phase, _ seconds: Int, _ style: Int) {
        guard let b = statusItem.button else { return }
        let symbol = phase.symbol
        if symbol != lastSymbol {
            lastSymbol = symbol
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: phase.title)
            img?.isTemplate = true
            b.image = img
        }
        b.contentTintColor = phase == .due ? .systemOrange : nil
        var title = ""
        if phase == .due {
            title = " Stand up"
        } else if style == 1 {
            title = " \(Int((Double(max(seconds, 0)) / 60).rounded(.up)))m"
        } else if style == 2 {
            title = String(format: " %d:%02d", seconds / 60, seconds % 60)
        }
        if title != lastTitle {
            lastTitle = title
            b.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            ])
        }
    }

    private func phaseChanged(_ phase: Phase) {
        guard let b = statusItem?.button else { return }
        if phase == .due {
            if model.popUpWhenDue && !popover.isShown {
                autoShown = true
                popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            }
        } else if autoShown && phase != .moving {
            autoShown = false
            if popover.isShown { popover.performClose(nil) }
        } else if autoShown && phase == .moving {
            // Keep it open a moment so the water nudge is visible, then tuck it away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                guard let self, self.autoShown else { return }
                self.autoShown = false
                if self.popover.isShown { self.popover.performClose(nil) }
            }
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let b = statusItem.button else { return }
        autoShown = false
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showQuickMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        add("Drink a glass (\(model.glassMl) ml)", #selector(menuDrink))
        menu.addItem(.separator())
        switch model.phase {
        case .sitting:
            add("I'm up now", #selector(menuStandUp))
            add("Pause", #selector(menuPause))
        case .paused:
            add("Resume", #selector(menuPause))
        case .due:
            add("I'm up!", #selector(menuStandUp))
            add("Snooze \(model.snoozeMinutes) min", #selector(menuSnooze))
        case .moving:
            add("I'm back at my desk", #selector(menuBack))
        }
        add("Restart timer", #selector(menuRestart))
        menu.addItem(.separator())
        add("Analysis…", #selector(menuAnalysis))
        add("Profile & water goal…", #selector(menuProfile))
        menu.addItem(.separator())
        add("Quit Stand Up", #selector(menuQuit))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuDrink() { model.addGlass() }
    @objc private func menuStandUp() { model.standUp() }
    @objc private func menuPause() { model.togglePause() }
    @objc private func menuSnooze() { model.snooze() }
    @objc private func menuBack() { model.backToDesk() }
    @objc private func menuRestart() { model.restart() }
    @objc private func menuAnalysis() { showAnalysis() }
    @objc private func menuProfile() { showProfile() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Windows

    private func showAnalysis() {
        openWindow(id: "analysis", title: "Stand Up — Analysis", view: AnalysisView(model: model))
    }

    private func showProfile() {
        openWindow(id: "profile", title: "Stand Up — Profile & Water Goal",
                   view: ProfileView(model: model, onDone: { [weak self] in self?.windows["profile"]?.close() }))
    }

    private func openWindow<V: View>(id: String, title: String, view: V) {
        popover.performClose(nil)
        autoShown = false
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = windows[id] {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.center()
        windows[id] = w
        windowObservers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowClosed(id) }
        }
        w.makeKeyAndOrderFront(nil)
    }

    private func windowClosed(_ id: String) {
        if let o = windowObservers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(o) }
        // Drop the window after AppKit is done closing it, so its memory is freed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.windows[id] = nil
            if self.windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Stand Up", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
