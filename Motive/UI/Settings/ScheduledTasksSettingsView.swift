//
//  ScheduledTasksSettingsView.swift
//  Motive
//
//  Created by Codex on 2026/2/16.
//

import SwiftData
import SwiftUI

struct ScheduledTasksSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configManager: ConfigManager

    @State private var tasks: [ScheduledTask] = []
    @State private var latestRunsByTaskID: [UUID: ScheduledTaskRun] = [:]
    @State private var editorState: ScheduledTaskEditorState?
    @State private var inlineError: String?
    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingSection(L10n.Settings.schedulerRuntimeSection) {
                SettingRow(
                    L10n.Settings.schedulerScope,
                    description: L10n.Settings.schedulerScopeDesc,
                    showDivider: false
                ) {
                    Text(L10n.Settings.schedulerInAppOnly)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.Aurora.textSecondary)
                }
            }

            SettingSection(L10n.Settings.scheduledTasksSection) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    scheduledTaskRow(task: task, showDivider: index < tasks.count - 1)
                }
                if tasks.isEmpty {
                    SettingRow(L10n.Settings.noTasksYet, description: L10n.Settings.noTasksYetDesc, showDivider: false) {
                        EmptyView()
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    editorState = .create
                } label: {
                    Label(L10n.Settings.newTask, systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(SettingsUIStyle.actionTint)

                Button {
                    reloadData()
                } label: {
                    Label(L10n.Settings.refresh, systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let inlineError, !inlineError.isEmpty {
                Text(inlineError)
                    .font(.system(size: 12))
                    .foregroundColor(Color.Aurora.warning)
            }

            Spacer()
        }
        .task {
            reloadData()
            isLoaded = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                reloadData()
            }
        }
        .sheet(item: $editorState) { state in
            ScheduledTaskEditorSheet(
                existingTask: state.existingTask,
                defaultProjectPath: configManager.currentProjectURL.path
            ) { draft in
                saveDraft(draft, editingTask: state.existingTask)
            }
        }
    }

    private func scheduledTaskRow(task: ScheduledTask, showDivider: Bool) -> some View {
        SettingRow(
            task.name,
            description: scheduleDescription(for: task),
            showDivider: showDivider
        ) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { task.isEnabled },
                    set: { value in
                        task.isEnabled = value
                        task.updatedAt = Date()
                        task.lastError = nil
                        recalculate(task: task)
                        persistAndRefresh()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(SettingsUIStyle.actionTint)

                Button(L10n.Settings.runNow) {
                    runNow(task)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    editorState = .edit(task)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    delete(task)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func scheduleDescription(for task: ScheduledTask) -> String {
        let nextText: String = if let nextRunAt = task.nextRunAt {
            Self.relativeFormatter.localizedString(for: nextRunAt, relativeTo: Date())
        } else {
            L10n.Settings.notScheduled
        }
        let runText: String = if let run = latestRunsByTaskID[task.id] {
            run.status
        } else {
            L10n.Settings.neverRun
        }
        return L10n.Settings.scheduleSummaryFormat.localized(with: nextText, runText)
    }

    private func saveDraft(_ draft: ScheduledTaskDraft, editingTask: ScheduledTask?) {
        guard let modelContext = appState.modelContext else { return }
        inlineError = nil

        do {
            let payload = try draft.payloadString()
            let now = Date()
            let task = editingTask ?? ScheduledTask(
                name: draft.name,
                prompt: draft.prompt,
                scheduleType: draft.scheduleType,
                schedulePayload: payload,
                timezoneIdentifier: draft.timezoneIdentifier,
                isEnabled: draft.isEnabled,
                projectPath: draft.projectPath,
                agent: draft.agent,
                createdAt: now,
                updatedAt: now
            )

            task.name = draft.name
            task.prompt = draft.prompt
            task.scheduleKind = draft.scheduleType
            task.schedulePayload = payload
            task.timezoneIdentifier = draft.timezoneIdentifier
            task.isEnabled = draft.isEnabled
            task.projectPath = draft.projectPath.nilIfBlank
            task.agent = draft.agent.nilIfBlank
            task.updatedAt = now
            task.lastError = nil
            task.nextRunAt = try NextRunCalculator.nextRun(for: task, from: now)

            if editingTask == nil {
                modelContext.insert(task)
            }
            try modelContext.save()
            appState.refreshScheduledTaskSystem()
            reloadData()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func runNow(_ task: ScheduledTask) {
        inlineError = nil
        appState.runScheduledTaskNow(task.id)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            reloadData()
        }
    }

    private func delete(_ task: ScheduledTask) {
        guard let modelContext = appState.modelContext else { return }
        modelContext.delete(task)
        do {
            try modelContext.save()
            appState.refreshScheduledTaskSystem()
            reloadData()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func recalculate(task: ScheduledTask) {
        do {
            task.nextRunAt = try NextRunCalculator.nextRun(for: task, from: Date())
            task.lastError = nil
        } catch {
            task.lastError = error.localizedDescription
            task.nextRunAt = nil
            inlineError = error.localizedDescription
        }
    }

    private func persistAndRefresh() {
        guard let modelContext = appState.modelContext else { return }
        do {
            try modelContext.save()
            appState.refreshScheduledTaskSystem()
            reloadData()
        } catch {
            inlineError = error.localizedDescription
        }
    }

    private func reloadData() {
        guard let modelContext = appState.modelContext else { return }
        let taskDescriptor = FetchDescriptor<ScheduledTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        tasks = (try? modelContext.fetch(taskDescriptor)) ?? []

        var latest: [UUID: ScheduledTaskRun] = [:]
        for task in tasks {
            let taskID = task.id
            var runDescriptor = FetchDescriptor<ScheduledTaskRun>(
                predicate: #Predicate { $0.taskID == taskID },
                sortBy: [SortDescriptor(\.triggeredAt, order: .reverse)]
            )
            runDescriptor.fetchLimit = 1
            if let run = (try? modelContext.fetch(runDescriptor))?.first {
                latest[taskID] = run
            }
        }
        latestRunsByTaskID = latest
    }
}

private enum ScheduledTaskEditorState: Identifiable {
    case create
    case edit(ScheduledTask)

    var id: String {
        switch self {
        case .create:
            "create"
        case let .edit(task):
            "edit-\(task.id.uuidString)"
        }
    }

    var existingTask: ScheduledTask? {
        switch self {
        case .create:
            nil
        case let .edit(task):
            task
        }
    }
}

private struct ScheduledTaskEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingTask: ScheduledTask?
    let defaultProjectPath: String
    let onSave: (ScheduledTaskDraft) -> Void

    @State private var draft: ScheduledTaskDraft
    @State private var errorMessage: String?

    init(existingTask: ScheduledTask?, defaultProjectPath: String, onSave: @escaping (ScheduledTaskDraft) -> Void) {
        self.existingTask = existingTask
        self.defaultProjectPath = defaultProjectPath
        self.onSave = onSave
        if let existingTask {
            _draft = State(initialValue: ScheduledTaskDraft(task: existingTask))
        } else {
            _draft = State(initialValue: ScheduledTaskDraft(defaultProjectPath: defaultProjectPath))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existingTask == nil ? L10n.Settings.editorNewTitle : L10n.Settings.editorEditTitle)
                .font(.system(size: 16, weight: .semibold))

            TextField(L10n.Settings.taskName, text: $draft.name)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.Settings.prompt, text: $draft.prompt, axis: .vertical)
                .lineLimit(3 ... 8)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.Settings.workingDirectoryOptional, text: $draft.projectPath)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.Settings.agentOptional, text: $draft.agent)
                .textFieldStyle(.roundedBorder)

            Picker(L10n.Settings.scheduleType, selection: $draft.scheduleType) {
                Text(L10n.Settings.scheduleOnce).tag(ScheduledTaskScheduleType.once)
                Text(L10n.Settings.scheduleInterval).tag(ScheduledTaskScheduleType.interval)
                Text(L10n.Settings.scheduleDaily).tag(ScheduledTaskScheduleType.daily)
                Text(L10n.Settings.scheduleWeekly).tag(ScheduledTaskScheduleType.weekly)
                Text(L10n.Settings.scheduleCron).tag(ScheduledTaskScheduleType.cron)
            }
            .pickerStyle(.segmented)

            scheduleEditor

            Toggle(L10n.Settings.enabled, isOn: $draft.isEnabled)

            Text(previewText)
                .font(.system(size: 12))
                .foregroundColor(Color.Aurora.textSecondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(Color.Aurora.warning)
            }

            HStack {
                Spacer()
                Button(L10n.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.save) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    @ViewBuilder
    private var scheduleEditor: some View {
        switch draft.scheduleType {
        case .once:
            DatePicker(L10n.Settings.runAt, selection: $draft.onceAt)
        case .interval:
            TextField(L10n.Settings.intervalSeconds, value: $draft.intervalSeconds, format: .number)
                .textFieldStyle(.roundedBorder)
        case .daily:
            DatePicker(L10n.Settings.time, selection: $draft.dailyTime, displayedComponents: .hourAndMinute)
        case .weekly:
            HStack {
                Picker(L10n.Settings.weekday, selection: $draft.weeklyWeekday) {
                    ForEach(1 ... 7, id: \.self) { day in
                        Text(weekdayName(day)).tag(day)
                    }
                }
                .frame(width: 180)
                DatePicker(L10n.Settings.time, selection: $draft.weeklyTime, displayedComponents: .hourAndMinute)
            }
        case .cron:
            TextField(L10n.Settings.cronExpression, text: $draft.cronExpression)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var previewText: String {
        do {
            let payload = try draft.payloadString()
            let temporaryTask = ScheduledTask(
                name: draft.name.ifBlank("Preview"),
                prompt: draft.prompt.ifBlank("Preview"),
                scheduleType: draft.scheduleType,
                schedulePayload: payload,
                timezoneIdentifier: draft.timezoneIdentifier,
                isEnabled: draft.isEnabled,
                projectPath: draft.projectPath.nilIfBlank,
                agent: draft.agent.nilIfBlank,
                createdAt: Date(),
                updatedAt: Date(),
                lastRunAt: draft.lastRunAt
            )
            if let next = try NextRunCalculator.nextRun(for: temporaryTask, from: Date()) {
                return L10n.Settings.nextRunFormat.localized(with: next.formatted(date: .abbreviated, time: .shortened))
            }
            return L10n.Settings.nextRunUnavailable
        } catch {
            return L10n.Settings.nextRunFormat.localized(with: error.localizedDescription)
        }
    }

    private func save() {
        errorMessage = nil
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = L10n.Settings.taskNameRequired
            return
        }
        guard !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = L10n.Settings.promptRequired
            return
        }
        if draft.scheduleType == .interval, draft.intervalSeconds < 60 {
            errorMessage = L10n.Settings.intervalMinimum
            return
        }
        do {
            _ = try draft.payloadString()
            onSave(draft)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let formatter = DateFormatter()
        let names = formatter.weekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names[max(0, min(weekday - 1, names.count - 1))]
    }
}

private struct ScheduledTaskDraft {
    var name: String
    var prompt: String
    var scheduleType: ScheduledTaskScheduleType
    var timezoneIdentifier: String
    var isEnabled: Bool
    var projectPath: String
    var agent: String
    var lastRunAt: Date?

    var onceAt: Date
    var intervalSeconds: Int
    var dailyTime: Date
    var weeklyWeekday: Int
    var weeklyTime: Date
    var cronExpression: String

    init(defaultProjectPath: String) {
        let now = Date()
        name = ""
        prompt = ""
        scheduleType = .once
        timezoneIdentifier = TimeZone.current.identifier
        isEnabled = true
        projectPath = defaultProjectPath
        agent = ""
        lastRunAt = nil
        onceAt = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        intervalSeconds = 3600
        dailyTime = now
        weeklyWeekday = Calendar.current.component(.weekday, from: now)
        weeklyTime = now
        cronExpression = "0 9 * * 1-5"
    }

    init(task: ScheduledTask) {
        name = task.name
        prompt = task.prompt
        scheduleType = task.scheduleKind
        timezoneIdentifier = task.timezoneIdentifier
        isEnabled = task.isEnabled
        projectPath = task.projectPath ?? ""
        agent = task.agent ?? ""
        lastRunAt = task.lastRunAt

        let now = Date()
        onceAt = task.nextRunAt ?? now
        intervalSeconds = 3600
        dailyTime = now
        weeklyWeekday = Calendar.current.component(.weekday, from: now)
        weeklyTime = now
        cronExpression = "0 9 * * 1-5"

        switch task.scheduleKind {
        case .once:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: OnceSchedulePayload.self) {
                onceAt = payload.runAt
            }
        case .interval:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: IntervalSchedulePayload.self) {
                intervalSeconds = payload.intervalSeconds
            }
        case .daily:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: DailySchedulePayload.self) {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
                components.hour = payload.hour
                components.minute = payload.minute
                dailyTime = Calendar.current.date(from: components) ?? now
            }
        case .weekly:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: WeeklySchedulePayload.self) {
                weeklyWeekday = payload.weekday
                var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
                components.hour = payload.hour
                components.minute = payload.minute
                weeklyTime = Calendar.current.date(from: components) ?? now
            }
        case .cron:
            if let payload = try? ScheduleRuleParser.decode(task.schedulePayload, as: CronSchedulePayload.self) {
                cronExpression = payload.expression
            }
        }
    }

    func payloadString() throws -> String {
        switch scheduleType {
        case .once:
            return try ScheduleRuleParser.encode(OnceSchedulePayload(runAt: onceAt))
        case .interval:
            return try ScheduleRuleParser.encode(IntervalSchedulePayload(intervalSeconds: intervalSeconds))
        case .daily:
            let c = Calendar.current.dateComponents([.hour, .minute], from: dailyTime)
            return try ScheduleRuleParser.encode(DailySchedulePayload(hour: c.hour ?? 0, minute: c.minute ?? 0))
        case .weekly:
            let c = Calendar.current.dateComponents([.hour, .minute], from: weeklyTime)
            return try ScheduleRuleParser.encode(
                WeeklySchedulePayload(
                    weekday: weeklyWeekday,
                    hour: c.hour ?? 0,
                    minute: c.minute ?? 0
                )
            )
        case .cron:
            return try ScheduleRuleParser.encode(CronSchedulePayload(expression: cronExpression))
        }
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }

    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
