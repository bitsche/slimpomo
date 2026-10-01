import Foundation

/// Display and grouping rules for task names. Stored names stay exactly as typed.
public enum TaskName {
    /// A short project label at the start of a name, such as `PRJX: Look Into Notion first`.
    public struct Parts: Equatable, Sendable {
        /// The label without its colon. Nil when the name has no label.
        public var prefix: String?
        /// The name after the label and the space that follows it. The whole name when there is no label.
        public var rest: String
        /// Where `rest` starts in the raw name, in UTF-16 units. Zero when there is no label.
        public var restOffset: Int
    }

    /// Labels are 1 to 12 characters without spaces or colons, then a colon and at least one space.
    /// A name that is only a label stays whole.
    public static func split(_ raw: String) -> Parts {
        let whole = Parts(prefix: nil, rest: raw, restOffset: 0)
        var index = raw.startIndex
        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        let labelStart = index
        var length = 0
        while index < raw.endIndex, raw[index] != ":", !raw[index].isWhitespace {
            length += 1
            index = raw.index(after: index)
        }
        guard length >= 1, length <= 12, index < raw.endIndex, raw[index] == ":" else { return whole }
        let labelEnd = index
        index = raw.index(after: index)
        guard index < raw.endIndex, raw[index].isWhitespace else { return whole }
        while index < raw.endIndex, raw[index].isWhitespace {
            index = raw.index(after: index)
        }
        guard index < raw.endIndex else { return whole }
        return Parts(
            prefix: String(raw[labelStart..<labelEnd]),
            rest: String(raw[index...]),
            restOffset: raw.utf16.distance(from: raw.startIndex, to: index)
        )
    }

    /// Trimmed, with every run of whitespace collapsed to one space. Case is kept.
    public static func normalized(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Done and History rows with the same key are one row.
    public static func groupKey(name: String, mode: Intensity) -> String {
        "\(mode.rawValue)|\(normalized(name))"
    }

    /// Line breaks become spaces, so a name stays one line of text. A CR LF pair is one space.
    public static func singleLine(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n":
                if !previousWasCarriageReturn { result.append(" ") }
                previousWasCarriageReturn = false
            case "\r":
                result.append(" ")
                previousWasCarriageReturn = true
            case "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}":
                result.append(" ")
                previousWasCarriageReturn = false
            default:
                result.unicodeScalars.append(scalar)
                previousWasCarriageReturn = false
            }
        }
        return result
    }
}
