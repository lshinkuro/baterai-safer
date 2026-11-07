import Foundation
import CryptoKit

/// One conversion result shown in the Dev Utils tab.
struct Conversion: Identifiable, Equatable {
    let title: String
    let output: String
    var id: String { title }
}

func prettyJSON(_ s: String) -> String? {
    guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]),
          !(o is String || o is NSNumber) || s.trimmingCharacters(in: .whitespaces).hasPrefix("\""),
          let out = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
    else { return nil }
    return String(decoding: out, as: UTF8.self)
}

func minifiedJSON(_ s: String) -> String? {
    guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d),
          let out = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) else { return nil }
    return String(decoding: out, as: UTF8.self)
}

/// Accepts standard and URL-safe Base64, with or without padding.
func base64Decode(_ s: String) -> Data? {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    guard !t.isEmpty, t.range(of: "^[A-Za-z0-9+/]+=*$", options: .regularExpression) != nil else { return nil }
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)
}

func dateText(_ d: Date) -> String {
    let local = DateFormatter()
    local.locale = Locale(identifier: "id_ID")
    local.dateFormat = "EEEE, d MMM yyyy HH:mm:ss zzz"
    let iso = ISO8601DateFormatter()
    return "\(local.string(from: d))\n\(iso.string(from: d))"
}

/// Everything useful we can derive from `input`; detection is purely local (nothing leaves the Mac).
func conversions(_ raw: String, now: Date = Date()) -> [Conversion] {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return [] }
    var out: [Conversion] = []

    // JWT: three base64url parts, header/payload are JSON
    let parts = s.split(separator: ".", omittingEmptySubsequences: false)
    if parts.count == 3, let h = base64Decode(String(parts[0])), let p = base64Decode(String(parts[1])),
       let hs = prettyJSON(String(decoding: h, as: UTF8.self)), let ps = prettyJSON(String(decoding: p, as: UTF8.self)) {
        out.append(Conversion(title: "JWT header", output: hs))
        out.append(Conversion(title: "JWT payload", output: ps))
        if let obj = (try? JSONSerialization.jsonObject(with: p)) as? [String: Any] {
            for key in ["exp", "iat", "nbf"] {
                guard let t = (obj[key] as? NSNumber)?.doubleValue else { continue }
                let d = Date(timeIntervalSince1970: t)
                let note = key == "exp" ? (d < now ? " — SUDAH KEDALUWARSA" : " — masih berlaku") : ""
                out.append(Conversion(title: "JWT \(key)\(note)", output: dateText(d)))
            }
        }
        return out
    }

    if let j = prettyJSON(s), s.first == "{" || s.first == "[" {
        out.append(Conversion(title: "JSON rapi", output: j))
        if let m = minifiedJSON(s) { out.append(Conversion(title: "JSON ringkas", output: m)) }
    }

    // Unix timestamp in seconds or milliseconds
    if s.range(of: "^\\d{10}(\\d{3})?$", options: .regularExpression) != nil, let n = Double(s) {
        out.append(Conversion(title: "Timestamp → tanggal", output: dateText(Date(timeIntervalSince1970: s.count == 13 ? n / 1000 : n))))
    }

    if s.contains("%"), let d = s.removingPercentEncoding, d != s { out.append(Conversion(title: "URL decode", output: d)) }

    if let d = base64Decode(s), s.count >= 8, let text = String(data: d, encoding: .utf8),
       !text.unicodeScalars.contains(where: { $0.value < 9 || ($0.value > 13 && $0.value < 32) }) {
        out.append(Conversion(title: "Base64 decode", output: prettyJSON(text) ?? text))
    }

    out.append(Conversion(title: "Base64 encode", output: Data(s.utf8).base64EncodedString()))
    if let e = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?/"))), e != s {
        out.append(Conversion(title: "URL encode", output: e))
    }
    let hex = { (d: any Sequence<UInt8>) in d.map { String(format: "%02x", $0) }.joined() }
    out.append(Conversion(title: "SHA-256", output: hex(SHA256.hash(data: Data(s.utf8)))))
    out.append(Conversion(title: "MD5", output: hex(Insecure.MD5.hash(data: Data(s.utf8)))))
    return out
}
