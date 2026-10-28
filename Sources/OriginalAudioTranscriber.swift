import Foundation
import Speech
import AVFoundation

@available(macOS 26.0, *)
enum OriginalAudioTranscriber {
 static func run(url: URL, localeID: String, onCue: @escaping @Sendable (SubtitleCue) async -> Void) async throws {
  let locale = Locale(identifier: localeID)
  guard SpeechTranscriber.isAvailable,
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale),
        await SpeechTranscriber.installedLocales.contains(supported) else {
   throw NSError(domain: "字幕识别", code: 1, userInfo: [NSLocalizedDescriptionKey: "该语言的本机识别模型尚未安装或不可用"])
  }
  let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
  let analyzer = SpeechAnalyzer(modules: [transcriber])
  let provider = try await AssetInputSequenceProvider.provider(from: AVURLAsset(url: url), compatibleWith: [transcriber], priority: .utility)
  let reader = Task {
   for try await result in transcriber.results {
    try Task.checkCancellation()
    guard result.isFinal else { continue }
    let tokens = result.text.runs.map { run in
     let text = String(result.text[run.range].characters)
     return TimedToken(text: text, start: run.audioTimeRange?.start.seconds, end: run.audioTimeRange?.end.seconds)
    }
    let cues = TimedCueBuilder.build(tokens: tokens, fallbackStart: result.range.start.seconds, fallbackEnd: result.range.end.seconds)
    for cue in cues { await onCue(cue) }
   }
  }
  do {
   try await withTaskCancellationHandler {
    try await analyzer.start(inputSequence: provider.analyzerInputs)
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    try await reader.value
   } onCancel: { reader.cancel(); Task { await analyzer.cancelAndFinishNow() } }
  } catch { reader.cancel(); await analyzer.cancelAndFinishNow(); throw error }
 }
}
