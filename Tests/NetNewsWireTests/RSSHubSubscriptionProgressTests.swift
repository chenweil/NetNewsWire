import AppKit
import RSCoreResources
import Testing

@MainActor @Suite(.serialized)
struct RSSHubSubscriptionProgressTests {
	@Test("subscription progress yields to tasks after browser verification")
	func progressDoesNotBlockTheMainActor() async throws {
		let hostWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
		hostWindow.orderFront(nil)
		defer { hostWindow.orderOut(nil) }
		// A timer explicitly registered in modalPanel mode still runs when
		// runModal blocks both Swift tasks and main dispatch callbacks.
		let state = ProgressWatchdogState()
		let watchdog = Timer(timeInterval: 0.5, repeats: false) { _ in
			MainActor.assumeIsolated {
				if NSApplication.shared.modalWindow != nil {
					state.stoppedModal = true
					IndeterminateProgressController.endProgress()
				}
			}
		}
		RunLoop.main.add(watchdog, forMode: .modalPanel)
		await Task { @MainActor in
			IndeterminateProgressController.beginProgressWithMessage("Finding feed", for: hostWindow)
		}.value
		watchdog.invalidate()
		#expect(!state.stoppedModal)
		#expect(NSApplication.shared.modalWindow == nil)
		#expect(hostWindow.attachedSheet != nil)
		if !state.stoppedModal {
			IndeterminateProgressController.endProgress()
		}
		#expect(hostWindow.attachedSheet == nil)
	}
}

@MainActor private final class ProgressWatchdogState {
	var stoppedModal = false
}
