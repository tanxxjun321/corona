import SwiftUI

struct LayoutEditorView: View {
    @ObservedObject var model: LayoutEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 880, minHeight: 520)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Layout Editor")
                .font(.headline)
            if model.hasUnsavedChanges {
                Text("Unsaved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let applyMessage = model.applyMessage {
                Text(applyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh detected menu bar items")

            Button("Reset") {
                model.resetToDetectedOrder()
            }

            Button("Save") {
                model.saveAndApply()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isApplying)
            if model.isApplying {
                ProgressView()
                    .controlSize(.small)
            }
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
        } else {
            HStack(alignment: .top, spacing: 0) {
                LayoutSectionColumn(
                    title: "Visible",
                    section: .visible,
                    rows: model.visibleRows,
                    model: model
                )
                Divider()
                LayoutSectionColumn(
                    title: "Hidden",
                    section: .hidden,
                    rows: model.hiddenRows,
                    model: model
                )
                Divider()
                LayoutSectionColumn(
                    title: "Always Hidden",
                    section: .alwaysHidden,
                    rows: model.alwaysHiddenRows,
                    model: model
                )
            }
        }
    }
}

private struct LayoutSectionColumn: View {
    var title: String
    var section: MenuBarSection
    var rows: [LayoutEditorViewModel.Row]
    @ObservedObject var model: LayoutEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("\(rows.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if rows.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { row in
                    LayoutRowView(row: row, section: section, model: model)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyText: String {
        switch section {
        case .visible:
            return "No visible items"
        case .hidden:
            return "Move items here to hide them later"
        case .alwaysHidden:
            return "Move items here for deep hiding"
        }
    }
}

private struct LayoutRowView: View {
    var row: LayoutEditorViewModel.Row
    var section: MenuBarSection
    @ObservedObject var model: LayoutEditorViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .lineLimit(1)
                Text(row.owner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Button {
                    model.moveUp(row.uid, in: section)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .help("Move up")

                Button {
                    model.moveDown(row.uid, in: section)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("Move down")
            }

            Menu {
                Button("Visible") {
                    model.move(row.uid, to: .visible)
                }
                Button("Hidden") {
                    model.move(row.uid, to: .hidden)
                }
                Button("Always Hidden") {
                    model.move(row.uid, to: .alwaysHidden)
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .menuStyle(.button)
            .help("Move to section")
        }
        .padding(8)
    }
}
