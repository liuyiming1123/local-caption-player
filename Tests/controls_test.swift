import Foundation
@main struct Tests {
 static func main() {
  let state = ControlsVisibilityPolicy(delay: 3)
  assert(!state.shouldHide(hasVideo: false, isPlaying: true, hoveringControls: false, idleSeconds: 10))
  assert(!state.shouldHide(hasVideo: true, isPlaying: false, hoveringControls: false, idleSeconds: 10))
  assert(!state.shouldHide(hasVideo: true, isPlaying: true, hoveringControls: true, idleSeconds: 10))
  assert(!state.shouldHide(hasVideo: true, isPlaying: true, hoveringControls: false, idleSeconds: 2.9))
  assert(state.shouldHide(hasVideo: true, isPlaying: true, hoveringControls: false, idleSeconds: 3))
  print("controls visibility tests passed")
 }
}
