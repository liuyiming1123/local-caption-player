import Foundation

struct CaptionFormatter {
    // Cut at sentence boundaries first, then at word boundaries for long phrases.
    func latest(_ input: String, maxUnits: Int = 38) -> String {
        guard maxUnits > 0 else { return "" }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let separators: Set<Character> = ["。", "！", "？", "!", "?", "\n", "；", ";"]
        var sentences: [String] = []; var sentence = ""
        for char in text {
            sentence.append(char)
            if separators.contains(char) {
                sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)); sentence = ""
            }
        }
        if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { sentences.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let last = sentences.last else { return "" }
        var chunks: [String] = []; var current = ""
        for char in last {
            if current.count >= maxUnits {
                if let space = current.lastIndex(of: " ") {
                    let suffix = String(current[current.index(after: space)...])
                    if !suffix.isEmpty {
                        chunks.append(String(current[..<space])); current = suffix
                    } else { chunks.append(current); current = "" }
                } else { chunks.append(current); current = "" }
            }
            current.append(char)
        }
        if !current.isEmpty { chunks.append(current) }
        return (chunks.last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
