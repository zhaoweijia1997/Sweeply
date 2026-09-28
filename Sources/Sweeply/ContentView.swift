import AppKit
import SwiftUI

struct ContentView: View {
    let model: ScanModel

    @AppStorage(AppLanguage.storageKey) private var language: AppLanguage = .system
    @State private var showingAbout = false

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
            .disabled(model.isScanning)
        }
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
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
                                CategoryRow(
                                    category: category,
                                    result: model.results[category.id],
                                    isScanning: model.scanning.contains(category.id),
                                    isSelected: Binding(
                                        get: { model.isSelected(category.id) },
                                        set: { model.setSelected(category.id, $0) }))
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
                Text("Cleaning isn't available yet — this version only scans.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Move to Trash") {}
                .controlSize(.large)
                .disabled(true)
        }
    }
}

// MARK: - Rows

private struct CategoryRow: View {
    let category: CleanCategory
    let result: CategoryResult?
    let isScanning: Bool
    @Binding var isSelected: Bool

    @State private var expanded = false

    private var hasItems: Bool { !(result?.items.isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Checkbox(isOn: $isSelected)
                    .disabled(!hasItems)
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
                ItemList(items: result.items)
                    .padding(.leading, 32)
            }
        }
        .padding(12)
        .opacity(result != nil && !hasItems ? 0.55 : 1)
    }

    @ViewBuilder
    private var size: some View {
        if isScanning {
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
    private let limit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.prefix(limit)) { item in
                HStack(spacing: 8) {
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

/// Drawn with SF Symbols rather than an AppKit checkbox, so it looks the same
/// everywhere, including in `--snapshot` renders.
private struct Checkbox: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let checked = isOn && isEnabled
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 17))
                .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
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
