import Foundation
@main struct Tests {
 static func main() throws {
   let folder = FileManager.default.temporaryDirectory.appendingPathComponent("caption-test-\(UUID())")
   defer { try? FileManager.default.removeItem(at: folder) }
   let s = TranscriptStore(directory: folder, videoName: "测试.mp4")
   try s.update("你好")
   try s.update("你好世界")
   precondition(s.document.contains("你好世界") && !s.document.contains("你好\n你好世界"), "partial revisions must replace, not duplicate")
   try s.finishSegment()
   try s.update("第二段")
   precondition(s.document.contains("你好世界") && s.document.contains("第二段"), "restart preserves previous text")
   let readableBackup = s.backupURL.deletingPathExtension().appendingPathExtension("txt")
   let backupText = try String(contentsOf: readableBackup, encoding: .utf8)
   precondition(backupText == s.document, "backup must be directly readable")
   let restored = try TranscriptStore.load(s.backupURL)
   precondition(restored.document == s.document, "backup must survive reload")
   print("transcript tests passed")
 }
}
