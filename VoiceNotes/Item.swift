//
//  Item.swift
//  VoiceNotes
//
//  Created by James Whitford on 2024/05/20.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
