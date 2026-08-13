//
//  ContentView.swift
//  KH Budget Tracker
//
//  Created by Karl Heinz Falderbaum on 8/13/26.
//

import Charts
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query(sort: \SpendingCategory.name) private var categories: [SpendingCategory]
    @Query(sort: \WeeklyBudget.weekStart, order: .reverse) private var budgets: [WeeklyBudget]

    @State private var selectedWeekStart = Calendar.khBudget.startOfWeek(for: Date())
    @State private var budgetText = ""
    @State private var amountText = ""
    @State private var categoryName = ""
    @State private var note = ""
    @State private var expenseDate = Date()

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var selectedWeekEnd: Date {
        Calendar.khBudget.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var nextWeekStart: Date {
        Calendar.khBudget.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var weekExpenses: [Expense] {
        expenses.filter { expense in
            expense.date >= selectedWeekStart && expense.date < nextWeekStart
        }
    }

    private var currentBudget: WeeklyBudget? {
        budgets.first { Calendar.khBudget.isDate($0.weekStart, inSameDayAs: selectedWeekStart) }
    }

    private var budgetAmount: Double {
        currentBudget?.amount ?? 0
    }

    private var spentAmount: Double {
        weekExpenses.reduce(0) { $0 + $1.amount }
    }

    private var remainingAmount: Double {
        budgetAmount - spentAmount
    }

    private var categoryTotals: [CategoryTotal] {
        let groupedTotals = Dictionary(grouping: weekExpenses, by: { $0.categoryName })
            .mapValues { expenses in expenses.reduce(0) { $0 + $1.amount } }

        return groupedTotals
            .map { CategoryTotal(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            Form {
                weekSection
                spendingSection
                chartSection
                expensesSection
            }
            .navigationTitle("Weekly Spending")
            .onAppear(perform: refreshBudgetText)
            .onChange(of: selectedWeekStart) { _, _ in
                refreshBudgetText()
                expenseDate = selectedWeekStart
            }
        }
    }

    private var weekSection: some View {
        Section("Budget Week") {
            HStack {
                Button {
                    moveWeek(by: -1)
                } label: {
                    Label("Previous Week", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)

                Spacer()

                VStack(spacing: 4) {
                    Text(selectedWeekStart, format: .dateTime.month(.abbreviated).day())
                        .font(.headline)
                    Text("to \(selectedWeekEnd.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    moveWeek(by: 1)
                } label: {
                    Label("Next Week", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
            }

            TextField("Weekly budget", text: $budgetText)
                .keyboardType(.decimalPad)

            Button("Save Budget", action: saveBudget)
                .disabled(parsedBudgetAmount == nil)

            LabeledContent("Budget", value: budgetAmount.formatted(.currency(code: currencyCode)))
            LabeledContent("Spent", value: spentAmount.formatted(.currency(code: currencyCode)))
            LabeledContent("Remaining", value: remainingAmount.formatted(.currency(code: currencyCode)))
                .foregroundStyle(remainingAmount < 0 ? .red : .primary)
        }
    }

    private var spendingSection: some View {
        Section("Add Spending") {
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)

            TextField("Category", text: $categoryName)
                .textInputAutocapitalization(.words)

            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(categories) { category in
                            Button(category.name) {
                                categoryName = category.name
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            TextField("Note", text: $note)
            DatePicker("Date", selection: $expenseDate, displayedComponents: .date)

            Button("Add Expense", action: addExpense)
                .disabled(!canAddExpense)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        Section("This Week by Category") {
            if categoryTotals.isEmpty {
                ContentUnavailableView("No spending yet", systemImage: "chart.bar.xaxis")
            } else {
                Chart(categoryTotals) { total in
                    BarMark(
                        x: .value("Category", total.category),
                        y: .value("Amount", total.amount)
                    )
                    .foregroundStyle(by: .value("Category", total.category))
                }
                .frame(height: 220)
                .chartLegend(.hidden)
            }
        }
    }

    private var expensesSection: some View {
        Section("Expenses") {
            if weekExpenses.isEmpty {
                Text("No expenses for this week")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(weekExpenses) { expense in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(expense.categoryName)
                                .font(.headline)
                            Spacer()
                            Text(expense.amount, format: .currency(code: currencyCode))
                                .font(.headline)
                        }

                        HStack {
                            Text(expense.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            if !expense.note.isEmpty {
                                Text(expense.note)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteExpenses)
            }
        }
    }

    private var parsedBudgetAmount: Double? {
        parseMoney(budgetText)
    }

    private var parsedExpenseAmount: Double? {
        parseMoney(amountText)
    }

    private var canAddExpense: Bool {
        guard let amount = parsedExpenseAmount else { return false }
        return amount > 0 && !trimmedCategoryName.isEmpty
    }

    private var trimmedCategoryName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func moveWeek(by weeks: Int) {
        if let newWeek = Calendar.khBudget.date(byAdding: .day, value: weeks * 7, to: selectedWeekStart) {
            selectedWeekStart = newWeek
        }
    }

    private func saveBudget() {
        guard let amount = parsedBudgetAmount else { return }

        if let currentBudget {
            currentBudget.amount = amount
            currentBudget.updatedAt = Date()
        } else {
            modelContext.insert(WeeklyBudget(weekStart: selectedWeekStart, amount: amount))
        }
    }

    private func addExpense() {
        guard let amount = parsedExpenseAmount else { return }

        let normalizedCategory = trimmedCategoryName
        if !categories.contains(where: { $0.name.caseInsensitiveCompare(normalizedCategory) == .orderedSame }) {
            modelContext.insert(SpendingCategory(name: normalizedCategory))
        }

        let expense = Expense(
            amount: amount,
            categoryName: normalizedCategory,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: expenseDate
        )
        modelContext.insert(expense)

        amountText = ""
        categoryName = ""
        note = ""
        expenseDate = Date()
    }

    private func deleteExpenses(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(weekExpenses[index])
        }
    }

    private func refreshBudgetText() {
        budgetText = currentBudget?.amount.formatted(.number.precision(.fractionLength(2))) ?? ""
    }

    private func parseMoney(_ value: String) -> Double? {
        let sanitizedValue = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amount = Double(sanitizedValue), amount >= 0 else {
            return nil
        }

        return amount
    }
}

private struct CategoryTotal: Identifiable {
    let category: String
    let amount: Double

    var id: String { category }
}

private extension Calendar {
    static var khBudget: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    func startOfWeek(for date: Date) -> Date {
        let interval = dateInterval(of: .weekOfYear, for: date)
        return startOfDay(for: interval?.start ?? date)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Expense.self, SpendingCategory.self, WeeklyBudget.self], inMemory: true)
}
