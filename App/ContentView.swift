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

    // MARK: - iOS: system search field for the address, picker in the nav bar, status as a list header

    #if os(iOS)
    private var phoneLayout: some View {
        NavigationStack {
            content
                .softScrollEdges()
                .overlay(alignment: .top) {
                    if mode == .map {
                        StatusLine(model: model, compact: true)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .adaptiveGlass(in: Capsule())
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        modePicker
                            .frame(maxWidth: 220)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if model.isLocating {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                Task {
                                    await model.useCurrentLocation()
                                    addressDraft = model.originAddress
                                }
                            } label: {
                                Label("Use my location", systemImage: "location.fill")
                            }
                        }
                        Menu {
                            Toggle("Avoid Tolls", isOn: $model.avoidTolls)
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .searchable(text: $addressDraft, prompt: "Starting address")
                .minimizingSearchToolbar()
                .onSubmit(of: .search) {
                    Task { await model.setOrigin(address: addressDraft) }
                }
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }
    #endif

    // MARK: - macOS: controls at the top, toolbar in the title bar

    #if os(macOS)
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
                StatusLine(model: model, compact: false)
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
    #endif

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
}
