import AppKit
import SwiftUI

final class ScanResultsWindowController: NSWindowController {
    private let model: ScanResultsViewModel

    init(
        cacheController: MenuBarCacheController,
        thumbnailProvider: MenuBarThumbnailProviding,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?
    ) {
        self.model = ScanResultsViewModel(
            cacheController: cacheController,
            thumbnailProvider: thumbnailProvider,
            boundaryProvider: boundaryProvider
        )
        let hostingController = NSHostingController(rootView: ScanResultsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Menu Bar Items"
        window.setContentSize(NSSize(width: 720, height: 460))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
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
final class ScanResultsViewModel: ObservableObject {
    struct Row: Identifiable {
        var id: UInt32 { windowID }
        var windowID: UInt32
        var ownerPID: Int32
        var x: Int
        var width: Int
        var title: String
        var owner: String
        var section: MenuBarSection
        var thumbnail: NSImage
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let cacheController: MenuBarCacheController
    private let thumbnailProvider: MenuBarThumbnailProviding
    private let boundaryProvider: @MainActor () -> SectionBoundary?

    init(
        cacheController: MenuBarCacheController,
        thumbnailProvider: MenuBarThumbnailProviding,
        boundaryProvider: @escaping @MainActor () -> SectionBoundary?
    ) {
        self.cacheController = cacheController
        self.thumbnailProvider = thumbnailProvider
        self.boundaryProvider = boundaryProvider
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                if let boundary = boundaryProvider() {
                    let cache = try await cacheController.cache(boundary: boundary)
                    rows = makeRows(from: cache)
                } else {
                    let snapshot = try await cacheController.refresh()
                    rows = makeRows(items: snapshot.items, section: .visible)
                }
            } catch {
                errorMessage = String(describing: error)
            }
            isLoading = false
        }
    }

    private func makeRows(from cache: ItemCache) -> [Row] {
        makeRows(items: cache.visibleItems, section: .visible)
            + makeRows(items: cache.hiddenItems, section: .hidden)
            + makeRows(items: cache.alwaysHiddenItems, section: .alwaysHidden)
    }

    private func makeRows(items: [MenuBarItem], section: MenuBarSection) -> [Row] {
        items.sorted { lhs, rhs in
            if lhs.bounds.minX != rhs.bounds.minX {
                return lhs.bounds.minX < rhs.bounds.minX
            }
            return lhs.windowID < rhs.windowID
        }.map { item in
            Row(
                windowID: item.windowID,
                ownerPID: item.ownerPID,
                x: Int(item.bounds.minX),
                width: Int(item.bounds.width),
                title: item.title ?? item.tag.title,
                owner: item.tag.namespace,
                section: section,
                thumbnail: thumbnailProvider.thumbnail(for: item)
            )
        }
    }
}

struct ScanResultsView: View {
    @ObservedObject var model: ScanResultsViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 640, minHeight: 380)
    }

    private var toolbar: some View {
        HStack {
            Text("Detected Items")
                .font(.headline)
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding(16)
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
            Text("No menu bar item windows detected with the public fallback provider.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.rows) { row in
                HStack(spacing: 12) {
                    Image(nsImage: row.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.body)
                        Text("\(row.owner)  \(sectionLabel(row.section))  window \(row.windowID)  pid \(row.ownerPID)  x \(row.x)  width \(row.width)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
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
