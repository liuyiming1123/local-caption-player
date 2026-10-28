import Foundation
@main struct TimedTextTests {
 static func main() {
  let tokens: [TimedToken] = [.init(text: "你好", start: 0.0, end: 1.0), .init(text: "，", start: nil, end: nil), .init(text: "世界", start: 1.1, end: 2.0), .init(text: "。", start: nil, end: nil)]
  let cues = TimedCueBuilder.build(tokens: tokens, fallbackStart: 0, fallbackEnd: 2)
  precondition(cues.map(\.text).joined() == "你好，世界。", "untimed text must not disappear")
  precondition(cues.first?.start == 0 && cues.last?.end == 2, "preserve available timing")
  let allUntimed = TimedCueBuilder.build(tokens: [.init(text: "完整句子", start: nil, end: nil)], fallbackStart: 3, fallbackEnd: 5)
  precondition(allUntimed.count == 1 && allUntimed[0].text == "完整句子", "all-untimed text must remain available")
  print("timed text tests passed")
 }
}
