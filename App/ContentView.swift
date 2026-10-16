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
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal)
                .padding(.vertical, 8)
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controlCard
        }
    }

    /// Bottom sheet-style card: content stays above the home indicator, the material runs to the screen edge.
    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            originBar
            Toggle(isOn: $model.avoidTolls) {
                Label("Avoid tolls", systemImage: "road.lanes")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
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
                Text("Wait times from Wake County BOE, refreshed at \(Format.clock(last)). Drive times from Apple Maps\(model.avoidTolls ? ", avoiding tolls" : "").")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
}
