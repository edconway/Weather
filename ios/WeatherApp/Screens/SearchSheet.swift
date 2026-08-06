import SwiftUI
import WeatherCore

/// City search (§8.3) — a port of `search.js`: 300 ms debounce, ≥1 character,
/// Open-Meteo geocoding, and the same two failure messages.
struct SearchSheet: View {
    enum Status: Equatable {
        case idle
        case searching
        case results([GeocodingResponse.Result])
        case empty(String)
        case failed
    }

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
                    Text("Search any city or town.")
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
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
