import CryptoKit
import Foundation

/// Raw content read from the pasteboard, before it is turned into a stored `ClipItem`.
enum Captured {
    case text(String, rtf: Data?)
    case image(png: Data, width: Int, height: Int)
    case files([String])

    /// Stable content hash used to de-duplicate history entries.
    var hash: String {
        var data: Data
        switch self {
        case .text(let string, _):
            data = Data("text:".utf8) + Data(string.utf8)
        case .image(let png, _, _):
            data = Data("image:".utf8) + png
        case .files(let paths):
            data = Data("files:".utf8) + Data(paths.joined(separator: "\n").utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
