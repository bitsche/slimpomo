import AppKit
import SwiftUI
import SlimPomoCore

struct PopoverView: View {
    var model: AppModel

    @State private var draftDescription = ""
    @State private var draftIntensity = Intensity.regular
    @State private var draftCount = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            Divider()
            queueSection
            addForm
            Divider()
            HStack {
                Spacer()
                Button("Quit") { model.quit() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            model.refresh()
            NSApp.activate()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ProgressRing(fraction: ringFraction, lineWidth: 6, tint: ringTint)
                .frame(width: 88, height: 88)
                .overlay {
                    Text(clockText)
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusLine)
                    .font(.headline)
                Text(taskLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let detail = detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if model.session.phase == .idle {
                Button("Start") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.session.hasWorkQueued)
                    .help(model.session.hasWorkQueued ? "Start the first pomodoro" : "Add a task first")
            } else if model.session.isRunning {
                Button("Pause") { model.pause() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Resume") { model.resume() }
                    .buttonStyle(.borderedProminent)
            }

            if model.session.phase == .work {
                Button("Mark Done") { model.markDone() }
                    .buttonStyle(.bordered)
                    .help("Finish this pomodoro and start its break")
            }

            if model.session.phase == .breakTime {
                Button("Skip Break") { model.skipBreak() }
                    .buttonStyle(.bordered)
                    .help("End the break and continue the queue")
            }

            Spacer(minLength: 0)
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Queue")
                .font(.headline)

            if model.session.queue.isEmpty {
                Text("Nothing queued yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if model.session.queue.count > 5 {
                ScrollView {
                    queueRows
                }
                .frame(height: 480)
            } else {
                queueRows
            }
        }
    }

    private var queueRows: some View {
        VStack(spacing: 8) {
            ForEach(Array(model.session.queue.enumerated()), id: \.element.id) { index, item in
                QueueRow(
                    item: item,
                    isFirst: index == 0,
                    isLast: index == model.session.queue.count - 1,
                    isCurrent: item.id == model.session.activeItemID && model.session.phase != .idle,
                    model: model
                )
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("New task", text: $draftDescription)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addDraft)

            HStack(spacing: 8) {
                Picker("Intensity", selection: $draftIntensity) {
                    ForEach(Intensity.allCases, id: \.self) { intensity in
                        Text(intensity.menuTitle).tag(intensity)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Stepper(value: $draftCount, in: 1...99) {
                    Text("\(draftCount)")
                        .monospacedDigit()
                        .frame(minWidth: 18, alignment: .trailing)
                }
                .fixedSize()
                .help("How many pomodoros")

                Button("Add", action: addDraft)
                    .fixedSize()
                    .disabled(draftDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var clockText: String {
        if model.session.phase == .idle {
            let duration = model.session.queue.first { $0.count > 0 }?.intensity.workDuration ?? 0
            return TimeFormat.clock(duration)
        }
        return TimeFormat.clock(model.session.displayedRemaining(at: model.now))
    }

    private var ringFraction: Double {
        model.session.phase == .idle ? 0 : model.session.elapsedFraction(at: model.now)
    }

    private var ringTint: Color {
        switch model.session.phase {
        case .work:
            Color(red: 0.82, green: 0.27, blue: 0.20)
        case .breakTime:
            Color(red: 0.16, green: 0.52, blue: 0.45)
        case .idle:
            Color.primary
        }
    }

    private var statusLine: String {
        switch model.session.phase {
        case .idle:
            model.session.hasWorkQueued ? "Up next" : "Idle"
        case .work:
            model.session.isRunning ? "Work" : "Work paused"
        case .breakTime:
            model.session.isRunning ? "Break" : "Break paused"
        }
    }

    private var taskLine: String {
        if model.session.phase != .idle, let active = model.session.activeItem {
            return active.description.isEmpty ? "Untitled" : active.description
        }
        if let next = model.session.queue.first(where: { $0.count > 0 }) {
            return next.description.isEmpty ? "Untitled" : next.description
        }
        return "Add a task to begin"
    }

    private var detailLine: String? {
        let item: QueueItem?
        if model.session.phase != .idle {
            item = model.session.activeItem
        } else {
            item = model.session.queue.first { $0.count > 0 }
        }
        guard let item else { return nil }
        let remaining = item.count == 0 ? "last one" : "\(item.count) left"
        return "\(item.intensity.shortTitle) · \(remaining)"
    }

    private func addDraft() {
        let description = draftDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        model.addItem(description: description, intensity: draftIntensity, count: draftCount)
        draftDescription = ""
        draftCount = 1
    }
}

private struct QueueRow: View {
    var item: QueueItem
    var isFirst: Bool
    var isLast: Bool
    var isCurrent: Bool
    var model: AppModel

    @State private var descriptionText: String
    @FocusState private var descriptionFocused: Bool

    init(item: QueueItem, isFirst: Bool, isLast: Bool, isCurrent: Bool, model: AppModel) {
        self.item = item
        self.isFirst = isFirst
        self.isLast = isLast
        self.isCurrent = isCurrent
        self.model = model
        _descriptionText = State(initialValue: item.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Picker("Intensity", selection: intensityBinding) {
                    ForEach(Intensity.allCases, id: \.self) { intensity in
                        Text(intensity.shortTitle).tag(intensity)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                Spacer(minLength: 0)

                Button {
                    model.moveUp(id: item.id)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(isFirst)
                .help("Move up")

                Button {
                    model.moveDown(id: item.id)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(isLast)
                .help("Move down")

                Button(role: .destructive) {
                    model.remove(id: item.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove from the queue")
            }

            TextField("Description", text: $descriptionText)
                .textFieldStyle(.roundedBorder)
                .focused($descriptionFocused)
                .onSubmit(commitDescription)
                .onChange(of: descriptionFocused) { _, isFocused in
                    if !isFocused {
                        commitDescription()
                    }
                }

            Stepper(value: countBinding, in: countRange) {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03))
        )
    }

    private var countLabel: String {
        if item.count == 1 {
            return "1 pomodoro"
        }
        return "\(item.count) pomodoros"
    }

    private var countRange: ClosedRange<Int> {
        if model.session.phase == .work, model.session.activeItemID == item.id {
            return 1...99
        }
        return 0...99
    }

    private var intensityBinding: Binding<Intensity> {
        Binding(
            get: { item.intensity },
            set: { model.updateIntensity(id: item.id, intensity: $0) }
        )
    }

    private var countBinding: Binding<Int> {
        Binding(
            get: { item.count },
            set: { model.setCount(id: item.id, count: $0) }
        )
    }

    private func commitDescription() {
        let trimmed = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        descriptionText = trimmed
        if trimmed != item.description {
            model.updateDescription(id: item.id, description: trimmed)
        }
    }
}

extension Intensity {
    var shortTitle: String {
        switch self {
        case .regular: "Regular"
        case .focus: "Focus"
        case .intense: "Intense"
        }
    }

    var menuTitle: String {
        switch self {
        case .regular: "Regular · 25/5"
        case .focus: "Focus · 50/10"
        case .intense: "Intense · 75/15"
        }
    }
}
