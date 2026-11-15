#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI has no scroll-wheel, free pinch or canvas-wide key input for a plain view, so this listens
/// for those events. Two-finger scrolling pans, a pinch or a mouse wheel zooms.
struct TrackpadCatcher: NSViewRepresentable {
    var onPan: (Double, Double) -> Void
    var onZoom: (CGPoint, Double) -> Void
    /// Key code, typed characters and whether a text field is being edited; returns true when the key was used.
    var onKey: (UInt16, String, Bool) -> Bool

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
        view.onKey = onKey
    }

    final class CatcherView: NSView {
        var onPan: ((Double, Double) -> Void)?
        var onZoom: ((CGPoint, Double) -> Void)?
        var onKey: ((UInt16, String, Bool) -> Bool)?
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown]) { [weak self] event in
                // AppKit delivers local monitor events on the main thread.
                nonisolated(unsafe) let mainThreadEvent = event
                let handled = MainActor.assumeIsolated { self?.handle(mainThreadEvent) ?? false }
                return handled ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            if event.type == .keyDown {
                // Shortcuts such as Cmd+Z belong to the menus.
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
                let editingText = window?.firstResponder is NSText
                return onKey?(event.keyCode, event.characters ?? "", editingText) ?? false
            }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return false }
            if event.type == .magnify {
                onZoom?(location, 1 + event.magnification)
            } else if event.hasPreciseScrollingDeltas {
                onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
            } else {
                onZoom?(location, exp(event.scrollingDeltaY * 0.05))
            }
            return true
        }
    }
}
#endif
