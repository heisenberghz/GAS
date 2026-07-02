//
//  JSON5Parser.swift
//  Motive
//
//  Lightweight JSON5-to-JSON sanitizer for skill metadata.
//

import Foundation

enum JSON5Parser {
    static func parseObject(_ raw: String) -> [String: Any]? {
        let sanitized = sanitize(raw)
        guard let data = sanitized.data(using: .utf8) else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    private static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return text
        }

        // Remove // comments
        text = text.replacingOccurrences(
            of: "(?m)//.*$",
            with: "",
            options: .regularExpression
        )

        // Remove /* */ comments
        text = text.replacingOccurrences(
            of: "(?s)/\\*.*?\\*/",
            with: "",
            options: .regularExpression
        )

        // Remove trailing commas before } or ]
        text = text.replacingOccurrences(
            of: ",\\s*(\\}|\\])",
            with: "$1",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
