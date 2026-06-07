import AppKit
import CoronaCore
import SwiftUI

final class ScanResultsWindowController: NSWindowController {
    private let model: ScanResultsViewModel

    init(cacheController: MenuBarCacheController) {
        self.model = ScanResultsViewModel(cacheController: cacheController)
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
    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let cacheController: MenuBarCacheController

    init(cacheController: MenuBarCacheController) {
        self.cacheController = cacheController
    }

    func refresh() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let snapshot = try await cacheController.refresh()
                items = snapshot.items.sorted { lhs, rhs in
                    if lhs.bounds.minX != rhs.bounds.minX {
                        return lhs.bounds.minX < rhs.bounds.minX
                    }
                    return lhs.windowID < rhs.windowID
                }
            } catch {
                errorMessage = String(describing: error)
            }
            isLoading = false
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
        } else if model.items.isEmpty {
            Text("No menu bar item windows detected with the public fallback provider.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.items, id: \.windowID) { item in
                HStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.tag.stableIdentifier)
                            .font(.body)
                        Text("window \(item.windowID)  pid \(item.ownerPID)  x \(Int(item.bounds.minX))  width \(Int(item.bounds.width))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
    }
}
