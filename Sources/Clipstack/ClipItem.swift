import Foundation

/// One entry in the clipboard history. Text and file lists are stored inline in the
/// JSON index; image bytes live as PNG files next to it and are referenced by name.
struct ClipItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text, image, files
    }

    let id: UUID
    let kind: Kind
    var date: Date
    var pinned: Bool
    let hash: String
    var sourceBundleID: String? = nil

    // kind == .text
    var text: String? = nil
    var rtf: Data? = nil
    var charCount: Int? = nil
    var lineCount: Int? = nil

    // kind == .image
    var imageFile: String? = nil
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil

    // kind == .files
    var files: [String]? = nil

    // MARK: - Display helpers

    var previewText: String {
        guard let text else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(400))
    }

    var fileNames: [String] {
        (files ?? []).map { ($0 as NSString).lastPathComponent }
    }

    var subtitle: String {
        switch kind {
        case .text:
            let chars = charCount ?? 0
            let lines = lineCount ?? 1
            let charText = chars == 1 ? "1 character" : "\(chars) characters"
            return lines > 1 ? "\(charText), \(lines) lines" : charText
        case .image:
            return "Image \(imageWidth ?? 0) × \(imageHeight ?? 0)"
        case .files:
            let n = files?.count ?? 0
            return n == 1 ? "1 file" : "\(n) files"
        }
    }

    func matches(_ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        switch kind {
        case .text:
            return text?.range(of: query, options: options) != nil
        case .image:
            return "image".range(of: query, options: options) != nil
                || subtitle.range(of: query, options: options) != nil
        case .files:
            return (files ?? []).contains { $0.range(of: query, options: options) != nil }
        }
    }
}
