import Foundation
struct TimedToken {
 let text: String
 let start: Double?
 let end: Double?
}
enum TimedCueBuilder {
 static func build(tokens: [TimedToken], fallbackStart: Double, fallbackEnd: Double) -> [SubtitleCue] {
  guard fallbackStart.isFinite, fallbackEnd.isFinite, fallbackEnd > fallbackStart else { return [] }
  var result: [SubtitleCue] = []; var text = ""; var start: Double?; var end: Double?
  func flush() {
   let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
   guard !cleaned.isEmpty else { text = ""; start = nil; end = nil; return }
   let cueStart = start ?? fallbackStart
   let cueEnd = max(end ?? fallbackEnd, cueStart + 0.001)
   result.append(SubtitleCue(start: cueStart, end: cueEnd, text: cleaned))
   text = ""; start = nil; end = nil
  }
  for token in tokens where !token.text.isEmpty {
   let valid = token.start != nil && token.end != nil && token.start!.isFinite && token.end!.isFinite && token.end! > token.start!
   let punctuationOnly = token.text.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
   if valid, let currentStart = start, !text.isEmpty, !punctuationOnly,
      token.end! - currentStart > 3.5 || text.count + token.text.count > 32 { flush() }
   if valid { if start == nil { start = token.start }; end = token.end }
   text += token.text
  }
  flush()
  return result
 }
}
