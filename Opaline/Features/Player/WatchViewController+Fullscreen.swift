import UIKit

#if targetEnvironment(macCatalyst)
private func toggleMacFullscreenSpace() -> Bool {
    let appClass = NSClassFromString("NSApplication") as? NSObject.Type
    let sharedApplication = NSSelectorFromString("sharedApplication")
    let application = appClass?.perform(sharedApplication)?.takeUnretainedValue() as? NSObject
    let keyWindow = NSSelectorFromString("keyWindow")
    let window = application?.perform(keyWindow)?.takeUnretainedValue() as? NSObject
    let toggleFullscreen = NSSelectorFromString("toggleFullScreen:")
    guard let window, window.responds(to: toggleFullscreen) else { return false }
    window.perform(toggleFullscreen, with: nil)
    return true
}
#endif

/// Where the player has to go back to once fullscreen ends.
struct FullscreenSnapshot {
    let superview: UIView
    let frame: CGRect
#if targetEnvironment(macCatalyst)
    let scene: UIWindowScene?
    let priorToolbarAutoHide: Bool?
    var geometryObservation: NSKeyValueObservation?
    var didEnterNativeFullscreen = false
#endif
}

// MARK: - Fullscreen

extension WatchViewController {
    func enterFullscreen(playerView: VideoPlayerView, animated: Bool = true) {
        guard let window = view.window else {
            return
        }
        detachPlayerToWindow(playerView, window: window)
#if targetEnvironment(macCatalyst)
        if #available(macCatalyst 16.0, *),
           fullscreenSnapshot?.scene?.isFullScreen == false {
            // shortcut: Catalyst hides NSWindow; replace when UIKit adds this request.
            _ = toggleMacFullscreenSpace()
        }
#endif
        updateQueueBar()
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        guard animated else {
            playerView.frame = window.bounds
            playerView.applyAutoZoomIfNeeded()
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = window.bounds
            },
            completion: { _ in
                playerView.applyAutoZoomIfNeeded()
            }
        )
    }

    private func detachPlayerToWindow(
        _ playerView: VideoPlayerView,
        window: UIWindow
    ) {
        let frameInWindow = playerView.convert(
            playerView.bounds, to: window
        )
#if targetEnvironment(macCatalyst)
        let scene = window.windowScene
        let isFullScreen: Bool
        if #available(macCatalyst 16.0, *) {
            isFullScreen = scene?.isFullScreen ?? false
        } else {
            isFullScreen = false
        }
        fullscreenSnapshot = FullscreenSnapshot(
            superview: playerView.superview ?? view,
            frame: playerView.frame,
            scene: scene,
            priorToolbarAutoHide: scene?.titlebar?.autoHidesToolbarInFullScreen,
            geometryObservation: nil,
            didEnterNativeFullscreen: isFullScreen
        )
        // Keep the macOS fullscreen control available if the runtime bridge can't resolve.
        if #available(macCatalyst 16.0, *) {
            scene?.sizeRestrictions?.allowsFullScreen = true
        }
#else
        fullscreenSnapshot = FullscreenSnapshot(
            superview: playerView.superview ?? view,
            frame: playerView.frame
        )
#endif
        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = true
        // Allow the player to resize with the window when the device rotates while
        // in fullscreen, so the video fills the screen in the new orientation.
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.frame = frameInWindow
        window.addSubview(playerView)
        playerView.isFullscreen = true
#if targetEnvironment(macCatalyst)
        if let scene = fullscreenSnapshot?.scene {
            scene.titlebar?.autoHidesToolbarInFullScreen = true
            if #available(macCatalyst 16.0, *) {
                fullscreenSnapshot?.geometryObservation = scene.observe(
                    \.effectiveGeometry,
                    options: [.new]
                ) { [weak self, weak playerView, weak window] scene, _ in
                    guard let self, let playerView, let window,
                          var snapshot = self.fullscreenSnapshot else { return }
                    if scene.isFullScreen {
                        snapshot.didEnterNativeFullscreen = true
                        self.fullscreenSnapshot = snapshot
                        playerView.frame = window.bounds
                    } else if snapshot.didEnterNativeFullscreen {
                        self.restoreFromFullscreen(
                            playerView: playerView, snapshot: snapshot
                        )
                    }
                }
            }
        }
#endif
    }

    func exitFullscreen(playerView: VideoPlayerView, animated: Bool = true) {
        guard let window = view.window,
              let snap = fullscreenSnapshot else {
            return
        }
#if targetEnvironment(macCatalyst)
        if #available(macCatalyst 16.0, *),
           snap.scene?.isFullScreen == true,
           toggleMacFullscreenSpace() {
            isLeavingFullscreen = true
            setNeedsStatusBarAppearanceUpdate()
            return
        }
#endif
        // Ask for the status bar now, so it slides back in alongside the
        // shrinking player. Asked for at the end of the animation instead, it
        // arrives half a second late and shoves the settled layout down.
        isLeavingFullscreen = true
        setNeedsStatusBarAppearanceUpdate()
        let target = snap.superview.convert(snap.frame, to: window)
        guard animated else {
            restoreFromFullscreen(playerView: playerView, snapshot: snap)
            return
        }
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = target
            }, completion: { [weak self] _ in
                self?.restoreFromFullscreen(
                    playerView: playerView, snapshot: snap
                )
            }
        )
    }

    func restoreFromFullscreen(
        playerView: VideoPlayerView,
        snapshot: FullscreenSnapshot
    ) {
#if targetEnvironment(macCatalyst)
        snapshot.geometryObservation?.invalidate()
        if let scene = snapshot.scene,
           let priorToolbarAutoHide = snapshot.priorToolbarAutoHide {
            scene.titlebar?.autoHidesToolbarInFullScreen = priorToolbarAutoHide
        }
#endif
        playerView.removeFromSuperview()
        let sv = snapshot.superview
        playerView.transform = .identity
        playerView.bounds = CGRect(origin: .zero, size: snapshot.frame.size)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.autoresizingMask = []
        sv.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: sv.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: sv.bottomAnchor)
        ])
        playerView.isFullscreen = false
        fullscreenSnapshot = nil
        isLeavingFullscreen = false
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        updateLayoutForSize()
        updateQueueBar()
    }
}
