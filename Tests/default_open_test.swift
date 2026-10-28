import Foundation
import UniformTypeIdentifiers

@main struct Tests {
 static func main() throws {
  let url = URL(fileURLWithPath: CommandLine.arguments[1])
  let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
  let types = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
  precondition(types.contains { ($0["LSItemContentTypes"] as? [String] ?? []).contains("public.movie") && ($0["CFBundleTypeRole"] as? String) == "Viewer" }, "App must register as a movie viewer")
  precondition(MediaOpenPolicy.accepts(URL(fileURLWithPath:"/tmp/example.mp4")), "MP4 should open")
  precondition(!MediaOpenPolicy.accepts(URL(fileURLWithPath:"/tmp/example.png")), "An image must not be treated as a movie")
  precondition(!MediaOpenPolicy.accepts(URL(string:"https://example.com/film.mp4")!), "Only local files are accepted")
  print("default-open tests passed")
 }
}
