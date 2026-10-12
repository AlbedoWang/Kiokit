import SwiftUI
import Charts
import OpenAnkiCore

private struct DailyStudy: Identifiable {
    var date: Date
    var count: Int
    var id: Date { date }
}

struct StatisticsView: View {
    @Environment(CollectionStore.self) private var store
    private var today: [ReviewRecord] { store.todayReviews() }
    private var week: [DailyStudy] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        return (-6...0).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return DailyStudy(date: date, count: store.snapshot.reviews.filter { calendar.isDate($0.date, inSameDayAs: date) }.count)
        }
    }
    private var recallRate: String {
        guard !today.isEmpty else { return "—" }
        return "\(Int((Double(today.filter { $0.rating != .again }.count) / Double(today.count) * 100).rounded()))%"
    }
    private var streak: Int {
        let calendar = Calendar.current
        let days = Set(store.snapshot.reviews.map { calendar.startOfDay(for: $0.date) })
        var date = calendar.startOfDay(for: .now)
        if !days.contains(date) { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        var count = 0
        while days.contains(date) {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("看见你的进步。")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("每一次认真回想，都在加深记忆。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metric("今日评分", value: "\(today.count)", unit: "次", symbol: "checkmark.circle", color: AnkiTheme.tint)
                    metric("连续学习", value: "\(streak)", unit: "天", symbol: "flame", color: .orange)
                    metric("今日回忆率", value: recallRate, unit: "", symbol: "brain.head.profile", color: .indigo)
                    metric("今日用时", value: "\(Int(today.reduce(0) { $0 + $1.duration } / 60))", unit: "分钟", symbol: "clock", color: .blue)
                }
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("最近 7 天").font(.headline)
                        Spacer()
                        Text("\(week.reduce(0) { $0 + $1.count }) 次评分").font(.caption).foregroundStyle(.secondary)
                    }
                    Chart(week) { day in
                        BarMark(x: .value("日期", day.date, unit: .day), y: .value("评分次数", day.count))
                            .foregroundStyle(AnkiTheme.tint.gradient).cornerRadius(5)
                    }
                    .chartYScale(domain: 0...max(5, week.map(\.count).max() ?? 0))
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                    .frame(height: 180)
                    .accessibilityLabel("最近七天共完成 \(week.reduce(0) { $0 + $1.count }) 次评分")
                }.ankiSurface()
                VStack(alignment: .leading, spacing: 18) {
                    Text("卡片概况").font(.headline)
                    distribution("新卡片", count: store.cards.filter { !$0.isSuspended && $0.stage == .new }.count, color: .blue)
                    distribution("学习中", count: store.cards.filter { !$0.isSuspended && ($0.stage == .learning || $0.stage == .relearning) }.count, color: .orange)
                    distribution("复习卡片", count: store.cards.filter { !$0.isSuspended && $0.stage == .review }.count, color: AnkiTheme.tint)
                    distribution("已暂停", count: store.cards.filter(\.isSuspended).count, color: .gray)
                }.ankiSurface()
                Text("评分次数包含同一卡片的多次练习。回忆率为今日「困难 / 良好 / 简单」评分占全部评分的比例。")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(AnkiTheme.background)
            .navigationTitle("学习统计")
    }

    private func metric(_ title: String, value: String, unit: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol).foregroundStyle(color)
                Spacer()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }.ankiSurface()
    }

    private func distribution(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                Spacer()
                Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
            }.font(.subheadline)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.08))
                    Capsule().fill(color.opacity(0.7)).frame(width: proxy.size.width * Double(count) / Double(max(1, store.cards.count)))
                }
            }.frame(height: 5)
        }
    }
}
