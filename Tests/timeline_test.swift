import Foundation
@main struct Tests {
 static func main() {
  let t = SubtitleTimeline(cues: [.init(start: 0, end: 2, text: "第一句"), .init(start: 2.2, end: 4, text: "第二句")])
  assert(t.text(at: 1) == "第一句")
  assert(t.text(at: 2.1) == "")
  assert(t.text(at: 2.5) == "第二句")
  assert(t.text(at: 5) == "")
  assert(t.text(at: -1) == "")
  print("timeline tests passed")
 }
}
