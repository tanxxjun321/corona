import AppKit
import CoronaCore
import SwiftUI
import UniformTypeIdentifiers

final class HiddenItemsPanelWindowController: NSWindowController {
    private let model: HiddenItemsPanelViewModel

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        thumbnailProvider: MenuBarThumbnailProviding,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        revealHandler: @escaping @MainActor (String) async -> LayoutApplicationResult
    ) {
        self.model = HiddenItemsPanelViewModel(
            cacheController: cacheController,
            layoutStore: layoutStore,
            thumbnailProvider: thumbnailProvider,
            boundaryProvider: boundaryProvider,
            revealHandler: revealHandler
        )
        let hostingController = NSHostingController(rootView: HiddenItemsPanelView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Hidden Items"
        window.setContentSize(NSSize(width: 420, height: 460))
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        model.refresh()
    }
}

@MainActor
final class HiddenItemsPanelViewModel: ObservableObject {
    struct Row: Identifiable {
        var id: String { uid }
        var uid: String
        var title: String
        var owner: String
        var section: MenuBarSection
        var isAvailable: Bool
        var thumbnail: NSImage
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var revealMessage: String?
    @Published private(set) var revealingUID: String?

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore
    private let thumbnailProvider: MenuBarThumbnailProviding
    private let boundaryProvider: @MainActor () -> SectionBoundary?
    private let revealHandler: @MainActor (String) async -> LayoutApplicationResult

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore,
        thumbnailProvider: MenuBarThumbnailProviding,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?,
        revealHandler: @escaping @MainActor (String) async -> LayoutApplicationResult
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
        self.thumbnailProvider = thumbnailProvider
        self.boundaryProvider = boundaryProvider
        self.revealHandler = revealHandler
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let cache: ItemCache
                if let boundary = boundaryProvider() {
                    cache = try await cacheController.cache(boundary: boundary, refreshIfNeeded: false)
                } else {
                    let snapshot = try await cacheController.snapshot(refreshIfNeeded: false)
                    cache = ItemCache(displayID: snapshot.displayID, visibleItems: snapshot.items, hiddenItems: [], alwaysHiddenItems: [])
                }
                let itemByUID = Dictionary(uniqueKeysWithValues: cache.allItems.map { item in
                    (item.tag.stableIdentifier, item)
                })
                let order = layoutStore.loadSavedSectionOrder()
                let physicalHiddenUIDs = (cache.hiddenItems + cache.alwaysHiddenItems)
                    .map(\.tag.stableIdentifier)
                    .filter { !MenuBarController.isCoronaSelfIdentifier($0) }
                rows = makeRows(
                    uids: mergedHiddenUIDs(saved: order.hidden, physical: physicalHiddenUIDs),
                    section: .hidden,
                    itemByUID: itemByUID
                )
            } catch {
                errorMessage = String(describing: error)
            }
            isLoading = false
        }
    }

    func reveal(uid: String) {
        revealingUID = uid
        revealMessage = nil
        Task {
            let result = await revealHandler(uid)
            revealMessage = result.statusTitle
            revealingUID = nil
            refresh()
        }
    }

    private func makeRows(
        uids: [String],
        section: MenuBarSection,
        itemByUID: [String: MenuBarItem]
    ) -> [Row] {
        uids.map { uid in
            guard let item = itemByUID[uid] else {
                return Row(
                    uid: uid,
                    title: uid,
                    owner: "Unavailable",
                    section: section,
                    isAvailable: false,
                    thumbnail: NSImage(systemSymbolName: "questionmark.app.dashed", accessibilityDescription: uid)
                        ?? NSWorkspace.shared.icon(for: .applicationBundle)
                )
            }
            return Row(
                uid: uid,
                title: item.title ?? item.tag.title,
                owner: item.tag.namespace,
                section: section,
                isAvailable: true,
                thumbnail: thumbnailProvider.thumbnail(for: item)
            )
        }
    }

    private func mergedHiddenUIDs(saved: [String], physical: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for uid in saved + physical where !seen.contains(uid) {
            seen.insert(uid)
            result.append(uid)
        }
        return result
    }
}

struct HiddenItemsPanelView: View {
    @ObservedObject var model: HiddenItemsPanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    private var toolbar: some View {
        HStack {
            Text("Hidden Items")
                .font(.headline)
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.rows.isEmpty {
            Text("No hidden items saved yet")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if let revealMessage = model.revealMessage {
                    Text(revealMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    Divider()
                }

                List(model.rows) { row in
                    HStack(spacing: 10) {
                        Image(nsImage: row.thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(row.owner)
                                Text(sectionLabel(row.section))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.reveal(uid: row.uid)
                        } label: {
                            if model.revealingUID == row.uid {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up.right")
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal")
                        .disabled(!row.isAvailable || model.revealingUID != nil)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
    }

    private func sectionLabel(_ section: MenuBarSection) -> String {
        switch section {
        case .visible:
            return "Visible"
        case .hidden:
            return "Hidden"
        case .alwaysHidden:
            return "Always Hidden"
        }
    }
}
