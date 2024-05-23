// VoiceMemoModel.swift

import Foundation

struct VoiceMemo: Identifiable, Codable {
    let id: UUID
    var timestamp: Date
    var audioURL: URL
    var transcription: String
    var transcriptionStatus: String
}
