import Foundation

enum LineEnding: String, Codable {
    case crlf, lf, cr

    var label: String {
        switch self {
        case .crlf: return "Windows (CRLF)"
        case .lf: return "Unix (LF)"
        case .cr: return "Macintosh (CR)"
        }
    }

    var sequence: String {
        switch self {
        case .crlf: return "\r\n"
        case .lf: return "\n"
        case .cr: return "\r"
        }
    }
}

enum FileEncoding: String, Codable, CaseIterable {
    case ansi, utf16le, utf16be, utf8, utf8bom

    var label: String {
        switch self {
        case .ansi: return "ANSI"
        case .utf16le: return "UTF-16 LE"
        case .utf16be: return "UTF-16 BE"
        case .utf8: return "UTF-8"
        case .utf8bom: return "UTF-8(BOM)"
        }
    }

    /// 한국어 Windows의 ANSI 코드 페이지 = CP949
    static let cp949: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
        return String.Encoding(rawValue: cf)
    }()
}

struct TextFile {
    var text: String          // 내부 표현: 줄바꿈은 항상 \n
    var encoding: FileEncoding
    var lineEnding: LineEnding

    static func normalizeNewlines(_ s: String) -> String {
        // Swift String은 "\r\n"을 한 글자로 보므로 NSString(UTF-16) 기준으로 처리
        let ns = s as NSString
        if ns.range(of: "\r", options: .literal).location == NSNotFound { return s }
        return ns.replacingOccurrences(of: "\r\n", with: "\n", options: .literal, range: NSRange(location: 0, length: ns.length))
            .replacingOccurrences(of: "\r", with: "\n", options: .literal)
    }

    static func detectLineEnding(_ s: String) -> LineEnding {
        let ns = s as NSString
        let r = ns.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n"))
        if r.location == NSNotFound { return .lf }
        let c = ns.character(at: r.location)
        if c == 0x0D {
            if r.location + 1 < ns.length, ns.character(at: r.location + 1) == 0x0A { return .crlf }
            return .cr
        }
        return .lf
    }

    static func decode(_ data: Data) -> TextFile {
        var enc: FileEncoding
        var str: String?
        let b = [UInt8](data.prefix(3))
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF {
            enc = .utf8bom
            str = String(data: data.dropFirst(3), encoding: .utf8) ?? String(decoding: data.dropFirst(3), as: UTF8.self)
        } else if b.count >= 2, b[0] == 0xFF, b[1] == 0xFE {
            enc = .utf16le
            str = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if b.count >= 2, b[0] == 0xFE, b[1] == 0xFF {
            enc = .utf16be
            str = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        } else if let s = String(data: data, encoding: .utf8) {
            enc = .utf8
            str = s
        } else if looksLikeUTF16LE(data), let s = String(data: data, encoding: .utf16LittleEndian) {
            enc = .utf16le
            str = s
        } else {
            enc = .ansi
            str = String(data: data, encoding: FileEncoding.cp949) ?? String(data: data, encoding: .windowsCP1252)
        }
        let s = str ?? String(decoding: data, as: UTF8.self)
        let eol = detectLineEnding(s)
        return TextFile(text: normalizeNewlines(s.replacingOccurrences(of: "\0", with: " ")), encoding: enc, lineEnding: eol)
    }

    private static func looksLikeUTF16LE(_ data: Data) -> Bool {
        guard data.count >= 4, data.count % 2 == 0 else { return false }
        let sample = data.prefix(512)
        var zerosOdd = 0, pairs = 0
        var i = sample.startIndex
        while i + 1 < sample.endIndex {
            pairs += 1
            if sample[i + 1] == 0 { zerosOdd += 1 }
            i += 2
        }
        return pairs > 0 && Double(zerosOdd) / Double(pairs) > 0.6
    }

    /// 손실 없이 인코딩 가능하면 Data, 아니면 nil
    func encoded(allowLossy: Bool = false) -> Data? {
        let out = (text as NSString).replacingOccurrences(of: "\n", with: lineEnding.sequence, options: .literal, range: NSRange(location: 0, length: (text as NSString).length))
        switch encoding {
        case .utf8: return out.data(using: .utf8)
        case .utf8bom: return Data([0xEF, 0xBB, 0xBF]) + (out.data(using: .utf8) ?? Data())
        case .utf16le:
            guard let d = out.data(using: .utf16LittleEndian) else { return nil }
            return Data([0xFF, 0xFE]) + d
        case .utf16be:
            guard let d = out.data(using: .utf16BigEndian) else { return nil }
            return Data([0xFE, 0xFF]) + d
        case .ansi:
            return out.data(using: FileEncoding.cp949, allowLossyConversion: allowLossy)
        }
    }
}
