import AppKit
import SwiftUI

struct ContentView: View {
    let model: ScanModel

    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var showingAbout = false
    @State private var confirmingClean = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            Group {
                if model.hasStarted {
                    results
                } else {
                    EmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .confirmationDialog("Move the selected items to the Trash?", isPresented: $confirmingClean) {
            Button("Move to Trash", role: .destructive) {
                Task { await model.clean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Total: \(formatBytes(model.selectedBytes)). You can put them back from the Trash until you empty it.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "Sweeply")
                    .font(.title2.weight(.semibold))
                Text("Find junk on this Mac that's safe to remove. Nothing is deleted until you choose to.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            LanguageMenu(language: $language)
            Button {
                showingAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(Text("About Sweeply"))
            Button {
                model.scan()
            } label: {
                Text(model.hasStarted ? LocalizedStringKey("Scan Again") : LocalizedStringKey("Scan"))
                    .frame(minWidth: 70)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isBusy)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = model.lastCleanup {
                    CleanupBanner(summary: summary)
                }
                ForEach(CleanCategory.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(group.title))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        let categories = CleanCategory.all.filter { $0.group == group }
                        VStack(spacing: 0) {
                            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                                if index > 0 {
                                    Divider().padding(.leading, 44)
                                }
                                CategoryRow(category: category, model: model)
                            }
                        }
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
                    }
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 14) {
                    Text("Selected: \(formatBytes(model.selectedBytes))")
                        .fontWeight(.medium)
                    Text("Found: \(formatBytes(model.foundBytes))")
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                Text("Selected items go to the Trash, so you can put them back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isCleaning {
                ProgressView().controlSize(.small)
                Text("Moving to the Trash…")
                    .foregroundStyle(.secondary)
            }
            Button("Move to Trash") {
                confirmingClean = true
            }
            .controlSize(.large)
            .disabled(model.isBusy || model.selectedBytes == 0)
        }
    }
}

// MARK: - Rows

private struct CategoryRow: View {
    let category: CleanCategory
    let model: ScanModel

    @State private var expanded = false

    private var result: CategoryResult? { model.results[category.id] }
    private var hasItems: Bool { !(result?.items.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Checkbox(state: model.state(of: category.id)) {
                    model.setSelected(category.id, model.state(of: category.id) == .off)
                }
                .disabled(!hasItems || model.isCleaning)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(category.title))
                        .fontWeight(.medium)
                    Text(LocalizedStringKey(category.detail))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let skipped = result?.skippedRunning.count, skipped > 0 {
                        Text("Skipped because the app is running: \(skipped)")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                    if let result, hasItems {
                        Button {
                            withAnimation(.snappy) { expanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                                Text("Items: \(result.items.count)")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.tint)
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 12)
                size
            }
            if expanded, let result {
                ItemList(items: result.items, categoryID: category.id, model: model)
                    .padding(.leading, 32)
            }
        }
        .padding(12)
        .opacity(result != nil && !hasItems ? 0.55 : 1)
    }

    @ViewBuilder
    private var size: some View {
        if model.scanning.contains(category.id) {
            ProgressView().controlSize(.small)
        } else if let result {
            if hasItems {
                Text(formatBytes(result.total))
                    .fontWeight(.medium)
                    .monospacedDigit()
            } else {
                Text("Nothing found")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ItemList: View {
    let items: [FoundItem]
    let categoryID: String
    let model: ScanModel
    private let limit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.prefix(limit)) { item in
                HStack(spacing: 8) {
                    let included = model.isIncluded(item, in: categoryID)
                    Checkbox(state: included ? .on : .off, size: 14) {
                        model.setIncluded(item, in: categoryID, !included)
                    }
                    .disabled(model.isCleaning)
                    Text(verbatim: item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(Text(verbatim: item.url.path))
                    Spacer(minLength: 8)
                    Text(formatBytes(item.size))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Show in Finder"))
                }
                .font(.callout)
            }
            if items.count > limit {
                Text("Not shown: \(items.count - limit)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CleanupBanner: View {
    let summary: CleanupSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Moved to the Trash: \(formatBytes(summary.movedBytes))")
                    .fontWeight(.medium)
                Text("Empty the Trash to actually free up the space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !summary.notMoved.isEmpty {
                    Text("Not moved (in use or protected): \(summary.notMoved.count)")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .help(Text(verbatim: summary.notMoved.map(\.name).joined(separator: "\n")))
                }
            }
            Spacer()
            Button("Show Trash") {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash"))
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.25)))
    }
}

/// Drawn with SF Symbols rather than an AppKit checkbox, so it looks the same
/// everywhere, including in `--snapshot` renders.
private struct Checkbox: View {
    let state: ScanModel.CheckState
    var size: CGFloat = 17
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let symbol = switch state {
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        case .off: "square"
        }
        let active = state != .off && isEnabled
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(state == .on ? [.isSelected] : [])
    }
}

// MARK: - Header pieces

private struct LanguageMenu: View {
    @Binding var language: AppLanguage

    var body: some View {
        Menu {
            Picker(selection: $language) {
                Text("Follow System").tag(AppLanguage.system)
                Divider()
                ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                    Text(verbatim: language.nativeName).tag(language)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                if language == .system {
                    Text("Follow System")
                } else {
                    Text(verbatim: language.nativeName)
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("Language"))
        .onChange(of: language) { _, newValue in
            newValue.persistForNextLaunch()
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "internaldrive")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Scan to see how much space you can free up.")
                .font(.title3)
            Text("Only this Mac's own disk is scanned. External drives are never touched.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
