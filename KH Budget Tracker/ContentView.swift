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
    @State private var selectedMonthStart = Calendar.khBudget.startOfMonth(for: Date())
    @State private var budgetText = ""
    @State private var amountText = ""
    @State private var categoryName = ""
    @State private var note = ""
    @State private var expenseDate = Date()
    @State private var selectedTransactionType = TransactionType.spent
    @State private var selectedSpendingScope = SpendingScope.week
    @State private var selectedExpense: Expense?

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var selectedWeekEnd: Date {
        Calendar.khBudget.date(byAdding: .day, value: 6, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var nextWeekStart: Date {
        Calendar.khBudget.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart
    }

    private var selectedMonthEnd: Date {
        Calendar.khBudget.date(byAdding: .day, value: -1, to: nextMonthStart) ?? selectedMonthStart
    }

    private var nextMonthStart: Date {
        Calendar.khBudget.date(byAdding: .month, value: 1, to: selectedMonthStart) ?? selectedMonthStart
    }

    private var yearStart: Date {
        Calendar.khBudget.startOfYear(for: Date())
    }

    private var nextYearStart: Date {
        Calendar.khBudget.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
    }

    private var yearDisplayEnd: Date {
        Calendar.khBudget.date(byAdding: .day, value: -1, to: nextYearStart) ?? nextYearStart
    }

    private var weekExpenses: [Expense] {
        expenses.filter { expense in
            expense.date >= selectedWeekStart && expense.date < nextWeekStart
        }
    }

    private var monthExpenses: [Expense] {
        expenses.filter { expense in
            expense.date >= selectedMonthStart && expense.date < nextMonthStart
        }
    }

    private var yearExpenses: [Expense] {
        expenses.filter { expense in
            expense.date >= yearStart && expense.date < nextYearStart
        }
    }

    private var scopedExpenses: [Expense] {
        switch selectedSpendingScope {
        case .week:
            weekExpenses
        case .month:
            monthExpenses
        case .year:
            yearExpenses
        }
    }

    private var currentBudget: WeeklyBudget? {
        budgets.first { Calendar.khBudget.isDate($0.weekStart, inSameDayAs: selectedWeekStart) }
    }

    private var budgetAmount: Double {
        baseBudgetAmount(for: selectedWeekStart) ?? 0
    }

    private var spentAmount: Double {
        netSpending(for: selectedWeekStart)
    }

    private var rolloverAmount: Double {
        rolloverAmount(for: selectedWeekStart)
    }

    private var availableBudgetAmount: Double {
        availableBudgetAmount(for: selectedWeekStart)
    }

    private var remainingAmount: Double {
        availableBudgetAmount - spentAmount
    }

    private var scopedSpentAmount: Double {
        scopedExpenses
            .filter { $0.amount > 0 }
            .reduce(0) { $0 + $1.amount }
    }

    private var scopedReceivedAmount: Double {
        abs(scopedExpenses
            .filter { $0.amount < 0 }
            .reduce(0) { $0 + $1.amount })
    }

    private var scopedNetAmount: Double {
        scopedExpenses.reduce(0) { $0 + $1.amount }
    }

    private var categoryTotals: [CategoryTotal] {
        let groupedTotals = Dictionary(grouping: scopedExpenses.filter { $0.amount > 0 }, by: { $0.categoryName })
            .mapValues { expenses in expenses.reduce(0) { $0 + $1.amount } }

        return groupedTotals
            .map { CategoryTotal(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            Form {
                weekSection
                if selectedSpendingScope == .week {
                    spendingSection
                }
                chartSection
                expensesSection
            }
            .navigationTitle("Budget Tracker")
            .onAppear(perform: refreshBudgetText)
            .onChange(of: selectedWeekStart) { _, _ in
                refreshBudgetText()
                expenseDate = selectedWeekStart
            }
            .sheet(item: $selectedExpense) { expense in
                EditExpenseView(
                    expense: expense,
                    categories: categories,
                    currencyCode: currencyCode,
                    saveCategoryIfNeeded: saveCategoryIfNeeded
                )
            }
        }
    }

    private var weekSection: some View {
        Section(selectedSpendingScope.summaryTitle) {
            Picker("View", selection: $selectedSpendingScope) {
                ForEach(SpendingScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    moveSelectedPeriodBackward()
                } label: {
                    Label("Previous Period", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(selectedSpendingScope == .year)

                Spacer()

                VStack(spacing: 4) {
                    Text(selectedSpendingScope.titleText(weekStart: selectedWeekStart, monthStart: selectedMonthStart, yearStart: yearStart))
                        .font(.headline)
                    Text(selectedSpendingScope.dateRangeText(
                        weekEnd: selectedWeekEnd,
                        monthStart: selectedMonthStart,
                        monthEnd: selectedMonthEnd,
                        yearStart: yearStart,
                        yearEnd: yearDisplayEnd
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    moveSelectedPeriodForward()
                } label: {
                    Label("Next Period", systemImage: "chevron.right")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(selectedSpendingScope == .year)
            }

            if selectedSpendingScope == .week {
                TextField("Weekly base budget", text: $budgetText)
                    .keyboardType(.decimalPad)

                Button("Save Budget", action: saveBudget)
                    .disabled(parsedBudgetAmount == nil)

                LabeledContent("Base Budget", value: budgetAmount.formatted(.currency(code: currencyCode)))
                LabeledContent("Rollover", value: rolloverAmount.formatted(.currency(code: currencyCode)))
                    .foregroundStyle(rolloverAmount < 0 ? .red : .green)
                LabeledContent("Available", value: availableBudgetAmount.formatted(.currency(code: currencyCode)))
                LabeledContent("Net Spent", value: spentAmount.formatted(.currency(code: currencyCode)))
                LabeledContent("Remaining", value: remainingAmount.formatted(.currency(code: currencyCode)))
                    .foregroundStyle(remainingAmount < 0 ? .red : .primary)
            } else {
                LabeledContent("Total Spent", value: scopedSpentAmount.formatted(.currency(code: currencyCode)))
                LabeledContent("Money Received", value: scopedReceivedAmount.formatted(.currency(code: currencyCode)))
                    .foregroundStyle(.green)
                LabeledContent("Net Spending", value: scopedNetAmount.formatted(.currency(code: currencyCode)))
            }
        }
    }

    private var spendingSection: some View {
        Section("Add Spending") {
            Picker("Type", selection: $selectedTransactionType) {
                ForEach(TransactionType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)

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

            Button(selectedTransactionType.buttonTitle, action: addExpense)
                .disabled(!canAddExpense)
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        Section(selectedSpendingScope.chartTitle) {
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

                ForEach(categoryTotals) { total in
                    LabeledContent(total.category, value: total.amount.formatted(.currency(code: currencyCode)))
                }
            }
        }
    }

    private var expensesSection: some View {
        Section(selectedSpendingScope.expensesTitle) {
            if scopedExpenses.isEmpty {
                Text(selectedSpendingScope.emptyExpensesText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scopedExpenses) { expense in
                    Button {
                        selectedExpense = expense
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(expense.categoryName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Text(expense.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                                    .foregroundStyle(expense.amount < 0 ? .green : .red)
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
                    .buttonStyle(.plain)
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

    private func moveSelectedPeriodBackward() {
        switch selectedSpendingScope {
        case .week:
            moveWeek(by: -1)
        case .month:
            moveMonth(by: -1)
        case .year:
            break
        }
    }

    private func moveSelectedPeriodForward() {
        switch selectedSpendingScope {
        case .week:
            moveWeek(by: 1)
        case .month:
            moveMonth(by: 1)
        case .year:
            break
        }
    }

    private func moveMonth(by months: Int) {
        if let newMonth = Calendar.khBudget.date(byAdding: .month, value: months, to: selectedMonthStart) {
            selectedMonthStart = newMonth
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

    private func budget(for weekStart: Date) -> WeeklyBudget? {
        budgets.first { Calendar.khBudget.isDate($0.weekStart, inSameDayAs: weekStart) }
    }

    private func baseBudgetAmount(for weekStart: Date, lookbackLimit: Int = 52) -> Double? {
        if let budget = budget(for: weekStart) {
            return budget.amount
        }

        guard
            lookbackLimit > 0,
            let previousWeekStart = Calendar.khBudget.date(byAdding: .day, value: -7, to: weekStart)
        else {
            return nil
        }

        return baseBudgetAmount(for: previousWeekStart, lookbackLimit: lookbackLimit - 1)
    }

    private func availableBudgetAmount(for weekStart: Date, lookbackLimit: Int = 52) -> Double {
        guard let baseBudget = baseBudgetAmount(for: weekStart, lookbackLimit: lookbackLimit) else {
            return 0
        }

        return baseBudget + rolloverAmount(for: weekStart, lookbackLimit: lookbackLimit)
    }

    private func rolloverAmount(for weekStart: Date, lookbackLimit: Int = 52) -> Double {
        guard
            lookbackLimit > 0,
            let previousWeekStart = Calendar.khBudget.date(byAdding: .day, value: -7, to: weekStart),
            baseBudgetAmount(for: previousWeekStart, lookbackLimit: lookbackLimit - 1) != nil
        else {
            return 0
        }

        let previousAvailableBudget = availableBudgetAmount(for: previousWeekStart, lookbackLimit: lookbackLimit - 1)
        return previousAvailableBudget - netSpending(for: previousWeekStart)
    }

    private func netSpending(for weekStart: Date) -> Double {
        guard let nextWeekStart = Calendar.khBudget.date(byAdding: .day, value: 7, to: weekStart) else {
            return 0
        }

        return expenses
            .filter { $0.date >= weekStart && $0.date < nextWeekStart }
            .reduce(0) { $0 + $1.amount }
    }

    private func addExpense() {
        guard let amount = parsedExpenseAmount else { return }

        let normalizedCategory = trimmedCategoryName
        saveCategoryIfNeeded(normalizedCategory)

        let signedAmount = selectedTransactionType == .received ? -amount : amount
        let expense = Expense(
            amount: signedAmount,
            categoryName: normalizedCategory,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: expenseDate
        )
        modelContext.insert(expense)

        amountText = ""
        categoryName = ""
        note = ""
        expenseDate = Date()
        selectedTransactionType = .spent
    }

    private func deleteExpenses(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scopedExpenses[index])
        }
    }

    private func saveCategoryIfNeeded(_ name: String) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }

        if !categories.contains(where: { $0.name.caseInsensitiveCompare(normalizedName) == .orderedSame }) {
            modelContext.insert(SpendingCategory(name: normalizedName))
        }
    }

    private func refreshBudgetText() {
        budgetText = baseBudgetAmount(for: selectedWeekStart)?.formatted(.number.precision(.fractionLength(2))) ?? ""
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

private enum TransactionType: String, CaseIterable, Identifiable {
    case spent
    case received

    var id: Self { self }

    var title: String {
        switch self {
        case .spent: "Spent"
        case .received: "Received"
        }
    }

    var buttonTitle: String {
        switch self {
        case .spent: "Add Expense"
        case .received: "Add Money Received"
        }
    }
}

private struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss

    let expense: Expense
    let categories: [SpendingCategory]
    let currencyCode: String
    let saveCategoryIfNeeded: (String) -> Void

    @State private var amountText: String
    @State private var categoryName: String
    @State private var note: String
    @State private var expenseDate: Date
    @State private var selectedTransactionType: TransactionType

    init(
        expense: Expense,
        categories: [SpendingCategory],
        currencyCode: String,
        saveCategoryIfNeeded: @escaping (String) -> Void
    ) {
        self.expense = expense
        self.categories = categories
        self.currencyCode = currencyCode
        self.saveCategoryIfNeeded = saveCategoryIfNeeded
        _amountText = State(initialValue: abs(expense.amount).formatted(.number.precision(.fractionLength(2))))
        _categoryName = State(initialValue: expense.categoryName)
        _note = State(initialValue: expense.note)
        _expenseDate = State(initialValue: expense.date)
        _selectedTransactionType = State(initialValue: expense.amount < 0 ? .received : .spent)
    }

    private var parsedAmount: Double? {
        let sanitizedValue = amountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let amount = Double(sanitizedValue), amount > 0 else {
            return nil
        }

        return amount
    }

    private var trimmedCategoryName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        parsedAmount != nil && !trimmedCategoryName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    Picker("Type", selection: $selectedTransactionType) {
                        ForEach(TransactionType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

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
                }
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveChanges)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func saveChanges() {
        guard let amount = parsedAmount else { return }

        let normalizedCategory = trimmedCategoryName
        saveCategoryIfNeeded(normalizedCategory)

        expense.amount = selectedTransactionType == .received ? -amount : amount
        expense.categoryName = normalizedCategory
        expense.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.date = expenseDate
        dismiss()
    }
}

private enum SpendingScope: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var summaryTitle: String {
        switch self {
        case .week: "Budget Week"
        case .month: "Monthly Spend Summary"
        case .year: "Yearly Spend Summary"
        }
    }

    var chartTitle: String {
        switch self {
        case .week: "This Week by Category"
        case .month: "Monthly Spend by Category"
        case .year: "Yearly Spend by Category"
        }
    }

    var expensesTitle: String {
        switch self {
        case .week: "Expenses"
        case .month: "Monthly Spend Entries"
        case .year: "Yearly Spend Entries"
        }
    }

    var emptyExpensesText: String {
        switch self {
        case .week: "No expenses for this week"
        case .month: "No entries for this month"
        case .year: "No entries for this year"
        }
    }

    func titleText(weekStart: Date, monthStart: Date, yearStart: Date) -> String {
        switch self {
        case .week:
            weekStart.formatted(.dateTime.month(.abbreviated).day())
        case .month:
            monthStart.formatted(.dateTime.month(.wide).year())
        case .year:
            yearStart.formatted(.dateTime.year())
        }
    }

    func dateRangeText(weekEnd: Date, monthStart: Date, monthEnd: Date, yearStart: Date, yearEnd: Date) -> String {
        switch self {
        case .week:
            "to \(weekEnd.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            "\(monthStart.formatted(.dateTime.month(.abbreviated).day())) to \(monthEnd.formatted(.dateTime.month(.abbreviated).day()))"
        case .year:
            "\(yearStart.formatted(.dateTime.month(.abbreviated).day().year())) to \(yearEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
        }
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

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components).map { startOfDay(for: $0) } ?? startOfDay(for: date)
    }

    func startOfYear(for date: Date) -> Date {
        let components = dateComponents([.year], from: date)
        return self.date(from: components).map { startOfDay(for: $0) } ?? startOfDay(for: date)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Expense.self, SpendingCategory.self, WeeklyBudget.self], inMemory: true)
}
