import SwiftUI

struct ContentView: View {
    enum Mode: Hashable { case list, map }

    @Bindable var model: PlannerModel
    @State private var mode: Mode = .list
    @State private var addressDraft = ""

    var body: some View {
        Group {
            #if os(iOS)
            phoneLayout
            #else
            macLayout
            #endif
        }
        .task {
            addressDraft = model.originAddress
            model.start()
        }
    }

    // MARK: - iOS: results on top, controls in a floating card at the bottom

    private var phoneLayout: some View {
        content
            .softScrollEdges()
            .safeAreaInset(edge: .top, spacing: 0) {
                // Floating glass capsule; the list scrolls underneath it.
                modePicker
                    .padding(4)
                    .adaptiveGlass(in: Capsule())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controlCard
            }
    }

    /// Bottom sheet-style card: one input row plus a one-line status; content stays above the home
    /// indicator and the glass runs to the screen edge.
    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                originBar
                Toggle(isOn: $model.avoidTolls) {
                    Image(systemName: "road.lanes")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(model.avoidTolls ? .blue : .secondary)
                .help("Avoid toll roads")
                .accessibilityLabel("Avoid tolls")
            }
            compactStatus
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(model.errorMessage == nil ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background {
            Color.clear
                .adaptiveGlass(in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
        }
    }

    /// Terse status for the phone card.
    @ViewBuilder
    private var compactStatus: some View {
        if model.isComputingTrips {
            let progress = model.tripProgress.map { " \($0.done)/\($0.total)" } ?? ""
            let pause = model.throttleWait > 1 ? " · pausing \(Int(model.throttleWait.rounded(.up)))s for rate limit" : ""
            Text("Computing drive times…\(progress)\(pause)").monospacedDigit()
        } else if model.isRefreshing {
            Text("Fetching wait times…")
        } else if let error = model.errorMessage {
            Text(error)
        } else if let last = model.lastRefresh {
            Text("\(hoursText(short: true)) · Waits as of \(Format.clock(last)) · Apple Maps\(model.avoidTolls ? ", no tolls" : "")")
        }
    }

    // MARK: - macOS: controls at the top, toolbar in the title bar

    private var macLayout: some View {
        NavigationStack {
            VStack(spacing: 0) {
                originBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                modePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
                content
                Divider()
                footer
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Wake Early Voting")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle("Avoid Tolls", isOn: $model.avoidTolls)
                        .toggleStyle(.button)
                        .help("Route around toll roads")
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Refresh wait times and drive times")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    // MARK: - Shared pieces

    private var modePicker: some View {
        Picker("View", selection: $mode) {
            Text("List").tag(Mode.list)
            Text("Map").tag(Mode.map)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .list: PlanListView(model: model)
        case .map: SiteMapView(model: model)
        }
    }

    private var originBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "house")
                .foregroundStyle(.secondary)
            TextField("Starting address", text: $addressDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.setOrigin(address: addressDraft) } }
                #if os(iOS)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.go)
                #endif
            if model.isLocating {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task {
                        await model.useCurrentLocation()
                        addressDraft = model.originAddress
                    }
                } label: {
                    Image(systemName: "location.fill")
                }
                .help("Use my current location")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isComputingTrips {
                ProgressView().controlSize(.mini)
                if let p = model.tripProgress, model.throttleWait > 1 {
                    Text("Computing drive times… \(p.done) of \(p.total). Pausing \(Int(model.throttleWait.rounded(.up)))s for Apple Maps' rate limit.")
                        .monospacedDigit()
                } else if let p = model.tripProgress {
                    Text("Computing drive times… \(p.done) of \(p.total) requests")
                } else {
                    Text("Computing drive times…")
                }
            } else if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Fetching wait times…")
            } else if let error = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error)
            } else if let last = model.lastRefresh {
                Text("\(hoursText(short: false)) Wait times from Wake County BOE, refreshed at \(Format.clock(last)). Drive times from Apple Maps\(model.avoidTolls ? ", avoiding tolls" : "").")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(3)
    }

    /// County-wide hours for today; every site keeps the same schedule.
    private func hoursText(short: Bool) -> String {
        let now = model.now
        guard let hours = PlannerModel.schedule.hours(on: now) else {
            return short ? "No early voting today" + nextOpeningText(after: now, short: true)
                         : "No early voting today." + nextOpeningText(after: now, short: false)
        }
        if now >= hours.close {
            return short ? "Closed" + nextOpeningText(after: now, short: true)
                         : "Sites closed for the day." + nextOpeningText(after: now, short: false)
        }
        if now < hours.open {
            return short ? "Opens \(Format.clock(hours.open))"
                         : "Sites open at \(Format.clock(hours.open)) today, until \(Format.clock(hours.close))."
        }
        return short ? "Open until \(Format.clock(hours.close))" : "Sites open until \(Format.clock(hours.close))."
    }

    private func nextOpeningText(after date: Date, short: Bool) -> String {
        guard let next = PlannerModel.schedule.nextOpening(after: date) else { return "" }
        let when = next.open.formatted(.dateTime.weekday(short ? .abbreviated : .wide).hour().minute())
        return short ? ", next \(when)" : " Next: \(when)."
    }
}
