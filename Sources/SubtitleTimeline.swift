import Foundation
struct SubtitleCue: Codable {
 let start: Double
 let end: Double
 let text: String
}
struct SubtitleTimeline {
 var cues: [SubtitleCue] = []
 func text(at time: Double) -> String {
  guard time.isFinite, time >= 0 else { return "" }
  return cues.last(where: { $0.start <= time && time < $0.end })?.text ?? ""
 }
}
