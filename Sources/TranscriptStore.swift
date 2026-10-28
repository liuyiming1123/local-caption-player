import Foundation

final class TranscriptStore {
    struct DataModel: Codable {
        var videoName: String
        var createdAt: Date
        var completed: [String]
        var current: String
    }
    let backupURL: URL
    private var state: DataModel
    init(directory: URL, videoName: String) {
        backupURL = directory.appendingPathComponent(UUID().uuidString + ".json")
        state = DataModel(videoName: videoName, createdAt: Date(), completed: [], current: "")
    }
    private init(url: URL, state: DataModel) { backupURL = url; self.state = state }
    static func load(_ url: URL) throws -> TranscriptStore {
        let state = try JSONDecoder().decode(DataModel.self, from: Data(contentsOf: url))
        return TranscriptStore(url: url, state: state)
    }
    var hasText: Bool { !state.completed.isEmpty || !state.current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var document: String {
        let parts = state.completed + (state.current.isEmpty ? [] : [state.current])
        return "视频：\(state.videoName)\n\n以下文字由本机语音识别生成，只包含已经识别完成的内容，可能有缺漏和识别错误。\n\n" + parts.joined(separator: "\n\n") + "\n"
    }
    func update(_ text: String) throws { state.current = text; try persist() }
    func finishSegment() throws {
        let text = state.current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { state.completed.append(text) }
        state.current = ""; try persist()
    }
    private func persist() throws {
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: backupURL, options: .atomic)
        try document.write(to: backupURL.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }
}
