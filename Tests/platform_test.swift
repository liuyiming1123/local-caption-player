import Foundation
@main struct Tests {
 static func main() throws {
  let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), format: nil) as! [String: Any]
  precondition(plist["LSMinimumSystemVersion"] as? String == "26.0", "SpeechAnalyzer and Liquid Glass require macOS 26 or later")
  print("platform metadata test passed")
 }
}
