import SwiftUI
import WeatherCore

/// City search — recents and favorites when idle, Open-Meteo results while typing.
struct SearchSheet: View {
    enum Status: Equatable {
        case idle
        case searching
        case results([GeocodingResponse.Result])
        case empty(String)
        case failed
    }

    @Bindable var store: WeatherStore
    let onSelect: (GeocodingResponse.Result) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var status: Status = .idle
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    private let client = OpenMeteoClient()

    var body: some View {
        NavigationStack {
            List {
                switch status {
                case .idle:
                    if !store.favoriteLocations.isEmpty {
                        Section("Favorites") {
                            ForEach(store.favoriteLocations, id: \.cacheKey) { place in
                                locationRow(place, starred: true)
                            }
                        }
                    }
                    if !store.recentLocations.isEmpty {
                        Section("Recent") {
                            ForEach(store.recentLocations, id: \.cacheKey) { place in
                                locationRow(place, starred: store.isFavorite(place))
                            }
                        }
                    }
                    if store.favoriteLocations.isEmpty && store.recentLocations.isEmpty {
                        Text("Search any city or town.")
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                case .searching:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching…").foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                case .results(let results):
                    ForEach(results) { result in
                        Button {
                            onSelect(result)
                            dismiss()
                        } label: {
                            row(result)
                        }
                        .buttonStyle(.plain)
                    }
                case .empty(let term):
                    Text("No results for \"\(term)\"")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                case .failed:
                    Text("Search failed — check your connection.")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search city or location…", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isFieldFocused)
                    if !query.isEmpty {
                        Button {
                            query = ""
                            status = .idle
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom, 6)
                .background(.bar)
            }
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue)
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func locationRow(_ place: WeatherLocation, starred: Bool) -> some View {
        HStack {
            Button {
                Task { await store.loadFavorite(place) }
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.shortName)
                        if place.name != place.shortName {
                            Text(place.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                store.toggleFavorite(place)
            } label: {
                Image(systemName: starred ? "star.fill" : "star")
                    .foregroundStyle(starred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(starred ? "Remove from favorites" : "Add to favorites")
        }
    }

    private func row(_ result: GeocodingResponse.Result) -> some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(Palette.accent)
            Text(result.name)
            Spacer(minLength: 8)
            Text(result.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func scheduleSearch(for term: String) {
        searchTask?.cancel()
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = .idle
            return
        }
        status = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let results = try await client.search(query: trimmed)
                guard !Task.isCancelled else { return }
                status = results.isEmpty ? .empty(trimmed) : .results(results)
            } catch {
                guard !Task.isCancelled else { return }
                status = .failed
            }
        }
    }
}
