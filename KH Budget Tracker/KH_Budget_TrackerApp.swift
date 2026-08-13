//
//  KH_Budget_TrackerApp.swift
//  KH Budget Tracker
//
//  Created by Karl Heinz Falderbaum on 8/13/26.
//

import SwiftData
import SwiftUI

@main
struct KH_Budget_TrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Expense.self,
            SpendingCategory.self,
            WeeklyBudget.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
