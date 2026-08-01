import SwiftUI
import UserNotifications

// MARK: - 数据模型


/// SwiftUI 一条视图链上只有一个 .sheet 会生效，多个会互相吞掉。
/// 标准解法是单个 sheet 加一个枚举来区分内容。
enum ActiveSheet: Identifiable {
    case quickEntry
    case scheduleImport
    var id: Int { hashValue }
}

enum CheckInState {
    case beforeStudy(daysUntil: Int)
    case afterStudy
    case windowOpen(slot: Int, total: Int, closesAt: Date)
    case windowClosed(nextAt: Date?)
}


@Observable
final class StudyStore {
    private(set) var entries: [EMAEntry] = []
    var config = StudyConfig() {
        didSet { saveConfig() }
    }

    init() {
        print("Documents: \(DataFile.entriesURL.deletingLastPathComponent().path)")
        loadConfig()
        loadEntries()
    }

    // MARK: 研究进度

    /// 给定日期属于研究第几天（1-based）。开始前为 0 或负数，结束后大于 durationDays。
    func studyDay(for date: Date = .now) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: config.startDate)
        let day   = cal.startOfDay(for: date)
        let diff  = cal.dateComponents([.day], from: start, to: day).day ?? 0
        return diff + 1
    }

    var currentStudyDay: Int { studyDay() }

    var isStudyActive: Bool {
        let d = currentStudyDay
        return d >= 1 && d <= config.durationDays
    }

    /// 从开始到此刻，理论上应该完成多少次记录
    var expectedCount: Int {
        let cal = Calendar.current
        let now = Date.now
        let today = currentStudyDay

        guard today >= 1 else { return 0 }

        // 已经完整过去的天数
        let fullDays = min(today - 1, config.durationDays)
        var expected = fullDays * config.slots.count

        // 今天已经过去的时段
        if today <= config.durationDays {
            for slot in config.slots {
                if let t = cal.date(bySettingHour: slot.hour, minute: slot.minute,
                                    second: 0, of: now), t <= now {
                    expected += 1
                }
            }
        }
        return expected
    }

    /// 此刻处于哪个阶段：研究前 / 窗口内 / 窗口外 / 研究后
    var checkInState: CheckInState {
        let cal = Calendar.current
        let now = Date.now
        let today = currentStudyDay

        if today < 1 { return .beforeStudy(daysUntil: 1 - today) }
        if today > config.durationDays { return .afterStudy }

        // 是否落在某个时段的响应窗口内
        for (i, slot) in config.slots.enumerated() {
            guard let start = cal.date(bySettingHour: slot.hour, minute: slot.minute,
                                       second: 0, of: now) else { continue }
            let close = start.addingTimeInterval(config.responseWindow)
            if now >= start && now < close {
                return .windowOpen(slot: i + 1, total: config.slots.count, closesAt: close)
            }
        }

        // 不在窗口内：找今天剩下的下一个时段
        let upcoming = config.slots.compactMap {
            cal.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: now)
        }.filter { $0 > now }.min()

        if let next = upcoming { return .windowClosed(nextAt: next) }

        // 今天没有了，看明天第一个（若研究尚未结束）
        if today < config.durationDays,
           let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           let first = config.slots.compactMap({
               cal.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: tomorrow)
           }).min() {
            return .windowClosed(nextAt: first)
        }
        return .windowClosed(nextAt: nil)
    }

    var isWindowOpen: Bool {
        if case .windowOpen = checkInState { return true }
        return false
    }

    /// 已应答的时段数：窗口内有至少一条记录即算 1，多余记录不重复计分。
    /// 这是 EMA 依从率的正确分子；直接数记录条数会被同一时段的多次点击虚增。
    var answeredCount: Int {
        let cal = Calendar.current
        let now = Date.now
        let today = currentStudyDay
        guard today >= 1 else { return 0 }
        let startDay = cal.startOfDay(for: config.startDate)

        var count = 0
        for d in 1...min(today, config.durationDays) {
            guard let dayDate = cal.date(byAdding: .day, value: d - 1, to: startDay) else { continue }
            for slot in config.slots {
                guard let t = cal.date(bySettingHour: slot.hour, minute: slot.minute,
                                       second: 0, of: dayDate), t <= now else { continue }
                let deadline = t.addingTimeInterval(config.responseWindow)
                if entries.contains(where: { $0.timestamp >= t && $0.timestamp < deadline }) {
                    count += 1
                }
            }
        }
        return count
    }

    /// 没有落在任何应答窗口计分内的多余记录数（好奇心点击、窗口外补记等）
    var extraCount: Int { max(entries.count - answeredCount, 0) }

    var compliance: Double {
        guard expectedCount > 0 else { return 0 }
        return min(Double(answeredCount) / Double(expectedCount), 1.0)
    }

    // MARK: 增删

    func add(mood: Double, agency: Double, metacognition: Double, melatonin: Bool) {
        let day = currentStudyDay
        let entry = EMAEntry(timestamp: .now,
                             studyDay: day,
                             mood: mood,
                             agency: agency,
                             metacognition: metacognition,
                             melatoninTaken: melatonin,
                             scheduledCondition: config.condition(forDay: day - 1))
        entries.insert(entry, at: 0)
        saveEntries()
    }

    // MARK: 随机化方案

    /// 今晚（当前研究日）的指派；研究期外或未加载方案时为 nil
    var tonightCondition: Int? {
        guard isStudyActive else { return nil }
        return config.condition(forDay: currentStudyDay)
    }

    /// "昨晚"的指派，与 Melatonin taken 开关对照用
    var lastNightCondition: Int? {
        let d = currentStudyDay
        guard d >= 2, d <= config.durationDays + 1 else { return nil }
        return config.condition(forDay: d - 1)
    }

    /// 方案覆盖了多少天（用来提示导入是否完整）
    var scheduleCoverage: Int {
        (1...config.durationDays).filter { config.condition(forDay: $0) != nil }.count
    }

    /// 从 JSON 文本导入方案。接受 {"1":0,"2":1,...} 格式。
    /// 返回覆盖天数；格式不对则抛错。
    @discardableResult
    func importSchedule(json: String) throws -> Int {
        let data = Data(json.utf8)
        let parsed = try JSONDecoder().decode([String: Int].self, from: data)
        guard !parsed.isEmpty else {
            throw NSError(domain: "EMALogger", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Schedule is empty."])
        }
        guard parsed.values.allSatisfy({ $0 == 0 || $0 == 1 }) else {
            throw NSError(domain: "EMALogger", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Conditions must be 0 or 1."])
        }
        config.schedule = parsed
        return scheduleCoverage
    }

    func loadSampleSchedule() {
        config.schedule = SampleSchedule.meng2026
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        saveEntries()
    }

    // MARK: 持久化

    // 全部委托给 DataFile：界面和 Shortcuts 走同一套读写，不会各存各的
    private func saveEntries() { DataFile.saveEntries(entries) }
    private func saveConfig()  { DataFile.saveConfig(config) }
    private func loadEntries() { entries = DataFile.loadEntries() }
    private func loadConfig()  { config = DataFile.loadConfig() }

    /// app 回到前台时调用：Shortcuts 可能在后台写过新记录
    func reloadFromDisk() {
        entries = DataFile.loadEntries()
        config  = DataFile.loadConfig()
    }
}

// MARK: - 通知层：滚动窗口调度

@Observable
final class ReminderScheduler {
    var isAuthorized = false
    var pendingCount = 0
    var lastRefresh: Date?

    /// 一次只排未来这么多天，避开 iOS 的 64 条上限
    private let horizonDays = 14
    private let center = UNUserNotificationCenter.current()

    func requestPermission() async {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Permission failed: \(error)")
            isAuthorized = false
        }
        await refreshPending()
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
        await refreshPending()
    }

    /// 滚动补齐：清空后重排未来 horizonDays 天内、仍在研究期内、且尚未过去的所有时段。
    /// 每次 app 启动或回到前台时调用，窗口就永远向前滚动。
    func refreshSchedule(for store: StudyStore) async {
        guard isAuthorized else { return }
        center.removeAllPendingNotificationRequests()

        let cal = Calendar.current
        let now = Date.now
        let slotCount = store.config.slots.count

        for offset in 0..<horizonDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let studyDay = store.studyDay(for: day)
            guard studyDay >= 1, studyDay <= store.config.durationDays else { continue }

            for (i, slot) in store.config.slots.enumerated() {
                guard let fire = cal.date(bySettingHour: slot.hour, minute: slot.minute,
                                          second: 0, of: day),
                      fire > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Day \(studyDay) of \(store.config.durationDays)"
                content.body  = "Check-in \(i + 1) of \(slotCount). How are you right now?"
                content.sound = .default

                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

                // 确定性 id：同一天同一时段永远是同一个 id，重排只会替换不会堆积
                let request = UNNotificationRequest(identifier: "ema-d\(studyDay)-s\(i)",
                                                    content: content,
                                                    trigger: trigger)
                do { try await center.add(request) }
                catch { print("Schedule failed: \(error)") }
            }
        }
        lastRefresh = now
        await refreshPending()
    }

    func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "Test check-in"
        content.body  = "How are you right now?"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "ema-test-\(UUID())",
                                            content: content, trigger: trigger)
        do { try await center.add(request) } catch { print("Test failed: \(error)") }
        await refreshPending()
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
        await refreshPending()
    }

    private func refreshPending() async {
        pendingCount = await center.pendingNotificationRequests().count
    }
}

// MARK: - 组件

struct RatingSlider: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(value))").font(.headline).monospacedDigit()
            }
            Slider(value: $value, in: 0...100, step: 1)
        }
        .padding(.vertical, 4)
    }
}

struct EntryRow: View {
    let entry: EMAEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Day \(entry.studyDay)")
                    .font(.caption.weight(.medium))
                Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if entry.isOverride {
                    Text("override")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if entry.melatoninTaken {
                    Image(systemName: "moon.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
            }
            HStack(spacing: 16) {
                Label("\(Int(entry.mood))", systemImage: "face.smiling")
                Label("\(Int(entry.agency))", systemImage: "figure.walk")
                Label("\(Int(entry.metacognition))", systemImage: "brain")
            }
            .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}

struct ProgressCard: View {
    let store: StudyStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if store.isStudyActive {
                    Text("Day \(store.currentStudyDay) of \(store.config.durationDays)")
                        .font(.title3.weight(.semibold))
                } else if store.currentStudyDay < 1 {
                    Text("Starts in \(1 - store.currentStudyDay) day(s)")
                        .font(.title3.weight(.semibold))
                } else {
                    Text("Study complete")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                Text("\(store.answeredCount) / \(store.expectedCount) check-ins")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            ProgressView(value: store.compliance)

            HStack {
                Text("Compliance \(store.compliance * 100, format: .number.precision(.fractionLength(1)))%")
                if store.extraCount > 0 {
                    Text("· \(store.extraCount) off-window")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            // 当前窗口状态：受试者最需要知道的一行
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch store.checkInState {
        case .windowOpen:   return "circle.fill"
        case .windowClosed: return "clock"
        case .beforeStudy:  return "calendar"
        case .afterStudy:   return "checkmark.circle"
        }
    }

    private var statusColor: Color {
        if case .windowOpen = store.checkInState { return .green }
        return .secondary
    }

    private var statusText: String {
        switch store.checkInState {
        case .windowOpen(let slot, let total, let closesAt):
            return "Check-in \(slot) of \(total) open until \(closesAt.formatted(date: .omitted, time: .shortened))"
        case .windowClosed(let next):
            if let next {
                return "Next check-in at \(next.formatted(date: .omitted, time: .shortened))"
            }
            return "No further check-ins scheduled"
        case .beforeStudy(let days):
            return "Study starts in \(days) day\(days == 1 ? "" : "s")"
        case .afterStudy:
            return "Study complete"
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    let router: NotificationRouter
    @State private var store = StudyStore()
    @State private var scheduler = ReminderScheduler()
    @Environment(\.scenePhase) private var scenePhase


    @State private var activeSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            Form {
                Section { ProgressCard(store: store) }

                Section {
                    Button {
                        activeSheet = .quickEntry
                    } label: {
                        Label("Quick check-in", systemImage: "bolt.fill")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }

                // MARK: 今晚的随机化指派
                Section {
                    if let tonight = store.tonightCondition {
                        HStack(spacing: 10) {
                            Image(systemName: tonight == 1 ? "moon.fill" : "moon.zzz")
                                .font(.title3)
                                .foregroundStyle(tonight == 1 ? .indigo : .secondary)
                            VStack(alignment: .leading) {
                                Text(tonight == 1 ? "Take melatonin tonight" : "No melatonin tonight")
                                    .font(.headline)
                                Text("Preregistered assignment for day \(store.currentStudyDay)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    } else if store.scheduleCoverage == 0 {
                        Button("Load schedule…") { activeSheet = .scheduleImport }
                        Button("Use built-in sample (Meng 2026, 70 days)") {
                            store.loadSampleSchedule()
                        }
                    } else {
                        Text("No assignment for today")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Tonight")
                } footer: {
                    if store.scheduleCoverage > 0 {
                        Text("Schedule covers \(store.scheduleCoverage) of \(store.config.durationDays) days.")
                    } else {
                        Text("Import the preregistered schedule JSON, e.g. the output of nof1kit::write_schedule().")
                    }
                }

                // 评分与提交只存在于快速记录卡里：一个动作一个入口。
                // 主界面留给仪表盘、方案、设置和历史。

                ProtocolSection(store: store,
                                onLoadSchedule: { activeSheet = .scheduleImport })

                Section {
                    if scheduler.isAuthorized {
                        Button("Refresh schedule") {
                            Task { await scheduler.refreshSchedule(for: store) }
                        }
                        Button("Send a test in 5 seconds") {
                            Task { await scheduler.sendTest() }
                        }
                        HStack {
                            Text("Queued")
                            Spacer()
                            Text("\(scheduler.pendingCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        if scheduler.pendingCount > 0 {
                            Button("Cancel all", role: .destructive) {
                                Task { await scheduler.cancelAll() }
                            }
                        }
                    } else {
                        Button("Allow notifications") {
                            Task {
                                await scheduler.requestPermission()
                                await scheduler.refreshSchedule(for: store)
                            }
                        }
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text(scheduler.isAuthorized
                         ? "Reminders are re-queued for the next 14 days each time the app opens, so the 64-notification limit is never reached."
                         : "Notifications are off. Tap to allow them.")
                }

                if !store.entries.isEmpty {
                    Section {
                        ShareLink(item: store.writeCSVFile(),
                                  preview: SharePreview("EMA data")) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        if store.scheduleCoverage > 0 {
                            ShareLink(item: store.writeScheduleFile(),
                                      preview: SharePreview("Randomization schedule")) {
                                Label("Export schedule", systemImage: "list.number")
                            }
                        }
                    } header: {
                        Text("Data")
                    } footer: {
                        Text("CSV is ISO 8601 timestamps, NA for missing, 0/1 for logicals. read.csv() takes it as is.")
                    }

                    Section("Entries (\(store.entries.count))") {
                        ForEach(store.entries) { entry in
                            EntryRow(entry: entry)
                        }
                        .onDelete { store.delete(at: $0) }
                    }
                }
            }
            .navigationTitle("EMA Logger")
        }
        .task {
            await scheduler.refreshStatus()
            await scheduler.refreshSchedule(for: store)
        }
        // 全 app 只有这一个 sheet，靠枚举区分内容
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .quickEntry:
                QuickEntrySheet(store: store)
            case .scheduleImport:
                ScheduleImportSheet(store: store) { activeSheet = nil }
            }
        }
        // 点通知进来：直接弹快速记录卡，跳过整屏界面
        .onChange(of: router.openQuickEntry) { _, shouldOpen in
            if shouldOpen {
                activeSheet = .quickEntry
                router.openQuickEntry = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Shortcuts 可能在后台写过记录，先同步磁盘，再据此重排提醒
            store.reloadFromDisk()
            Task {
                await scheduler.refreshStatus()
                await scheduler.refreshSchedule(for: store)
            }
        }
    }
}

// 独立成 View：SwiftUI 的类型推断在深层嵌套 + 多个 Binding 闭包时会超时，
// 拆分是标准解法，顺带让 body 读得清楚。
struct ProtocolSection: View {
    let store: StudyStore
    let onLoadSchedule: () -> Void

    var body: some View {
        Section("Protocol") {
            Button(store.scheduleCoverage > 0 ? "Replace schedule…" : "Load schedule…") {
                onLoadSchedule()
            }

            DatePicker("Start date", selection: startDate, displayedComponents: .date)

            Stepper("Duration: \(store.config.durationDays) days",
                    value: duration, in: 1...365)

            Stepper("Response window: \(store.config.responseWindowHours) h",
                    value: window, in: 1...12)

            ForEach(Array(store.config.slots.enumerated()), id: \.element.id) { index, slot in
                DatePicker("Slot \(index + 1)",
                           selection: slotBinding(index),
                           displayedComponents: .hourAndMinute)
            }
        }
    }

    private var startDate: Binding<Date> {
        Binding(get: { store.config.startDate },
                set: { store.config.startDate = Calendar.current.startOfDay(for: $0) })
    }
    private var duration: Binding<Int> {
        Binding(get: { store.config.durationDays },
                set: { store.config.durationDays = $0 })
    }
    private var window: Binding<Int> {
        Binding(get: { store.config.responseWindowHours },
                set: { store.config.responseWindowHours = $0 })
    }
    private func slotBinding(_ index: Int) -> Binding<Date> {
        Binding(get: { store.config.slots[index].todayAt },
                set: { newValue in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    store.config.slots[index].hour   = c.hour ?? 0
                    store.config.slots[index].minute = c.minute ?? 0
                })
    }
}

#Preview {
    ContentView(router: NotificationRouter())
}

// 方案导入界面。原先内联在 ContentView 里，抽出来后 sheet 内容一目了然。
struct ScheduleImportSheet: View {
    let store: StudyStore
    let onDone: () -> Void

    @State private var json = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $json)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                } header: {
                    Text("Paste schedule JSON")
                } footer: {
                    Text("Format: {\"1\": 0, \"2\": 1, …} — day number to condition. This is what nof1kit::write_schedule() produces.")
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }

                Section {
                    Button("Import") {
                        do {
                            let n = try store.importSchedule(json: json)
                            print("Imported schedule covering \(n) days")
                            onDone()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                    .fontWeight(.semibold)

                    Button("Use built-in sample instead") {
                        store.loadSampleSchedule()
                        onDone()
                    }
                }
            }
            .navigationTitle("Import schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
            }
        }
    }
}
