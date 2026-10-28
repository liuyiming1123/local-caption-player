import Foundation
struct ControlsVisibilityPolicy {
 let delay: TimeInterval
 func shouldHide(hasVideo: Bool, isPlaying: Bool, hoveringControls: Bool, idleSeconds: TimeInterval) -> Bool {
  hasVideo && isPlaying && !hoveringControls && idleSeconds >= delay
 }
}
