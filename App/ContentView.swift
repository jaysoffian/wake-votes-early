import SwiftUI

struct ContentView: View {
    enum Mode: Hashable { case list, map }

    @Bindable var model: PlannerModel
    @State private var mode: Mode = .list
    @State private var addressDraft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                originBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                Picker("View", selection: $mode) {
                    Text("List").tag(Mode.list)
                    Text("Map").tag(Mode.map)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.vertical, 8)
                Divider()
                switch mode {
                case .list: PlanListView(model: model)
                case .map: SiteMapView(model: model)
                }
                Divider()
                footer
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Wake Early Voting")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)   // one compact bar for title + buttons
            #endif
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
        .task {
            addressDraft = model.originAddress
            model.start()
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
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
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
}
