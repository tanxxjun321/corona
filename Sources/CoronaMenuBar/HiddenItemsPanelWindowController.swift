import AppKit
import CoronaCore
import SwiftUI

final class HiddenItemsPanelWindowController: NSWindowController {
    private let model: HiddenItemsPanelViewModel

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore
    ) {
        self.model = HiddenItemsPanelViewModel(cacheController: cacheController, layoutStore: layoutStore)
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
    struct Row: Identifiable, Equatable {
        var id: String { uid }
        var uid: String
        var title: String
        var owner: String
        var section: MenuBarSection
        var isAvailable: Bool
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let cacheController: MenuBarCacheController
    private let layoutStore: LayoutPersistenceStore

    init(
        cacheController: MenuBarCacheController,
        layoutStore: LayoutPersistenceStore
    ) {
        self.cacheController = cacheController
        self.layoutStore = layoutStore
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await cacheController.snapshot(refreshIfNeeded: false)
                let itemByUID = Dictionary(uniqueKeysWithValues: snapshot.items.map { item in
                    (item.tag.stableIdentifier, item)
                })
                let order = layoutStore.loadSavedSectionOrder()
                rows = makeRows(uids: order.hidden, section: .hidden, itemByUID: itemByUID)
                    + makeRows(uids: order.alwaysHidden, section: .alwaysHidden, itemByUID: itemByUID)
            } catch {
                errorMessage = String(describing: error)
            }
            isLoading = false
        }
    }

    private func makeRows(
        uids: [String],
        section: MenuBarSection,
        itemByUID: [String: MenuBarItem]
    ) -> [Row] {
        uids.map { uid in
            guard let item = itemByUID[uid] else {
                return Row(uid: uid, title: uid, owner: "Unavailable", section: section, isAvailable: false)
            }
            return Row(
                uid: uid,
                title: item.title ?? item.tag.title,
                owner: item.tag.namespace,
                section: section,
                isAvailable: true
            )
        }
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
            List(model.rows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.isAvailable ? "app.dashed" : "questionmark.app.dashed")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
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
                        NSSound.beep()
                    } label: {
                        Image(systemName: "arrow.up.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Temporary reveal will be enabled after the move executor is connected")
                    .disabled(!row.isAvailable)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
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
