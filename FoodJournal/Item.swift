//
//  Item.swift
//  FoodJournal
//
//  Created by Mike Shaw on 4/30/26.
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
