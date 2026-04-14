//
//  Item.swift
//  Hephaestus
//
//  Created by Joshua Sumskas on 14/4/2026.
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
