//
//  Item.swift
//  KH Budget Tracker
//
//  Created by Karl Heinz Falderbaum on 8/13/26.
//

import Foundation
import SwiftData

@Model
final class Expense {
    var amount: Double
    var categoryName: String
    var note: String
    var date: Date
    var createdAt: Date

    init(amount: Double, categoryName: String, note: String = "", date: Date = Date(), createdAt: Date = Date()) {
        self.amount = amount
        self.categoryName = categoryName
        self.note = note
        self.date = date
        self.createdAt = createdAt
    }
}

@Model
final class SpendingCategory {
    @Attribute(.unique) var name: String
    var createdAt: Date

    init(name: String, createdAt: Date = Date()) {
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
final class WeeklyBudget {
    var weekStart: Date
    var amount: Double
    var createdAt: Date
    var updatedAt: Date

    init(weekStart: Date, amount: Double, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.weekStart = weekStart
        self.amount = amount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
