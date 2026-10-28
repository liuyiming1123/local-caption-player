import Foundation
import UniformTypeIdentifiers

enum MediaOpenPolicy {
    static func accepts(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .audio)
    }
}
