//
//  LogEntry.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation
import SwiftData

@Model
final class LogEntry {
    var id: UUID
    var rawJson: String
    var kind: String
    var createdAt: Date

    init(id: UUID = UUID(), rawJson: String, kind: String, createdAt: Date = Date()) {
        self.id = id
        self.rawJson = rawJson
        self.kind = kind
        self.createdAt = createdAt
    }
}
