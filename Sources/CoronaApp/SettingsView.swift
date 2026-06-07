import CoronaCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var selection: SettingsSection = .permissions

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection {
            case .permissions:
                PermissionsPane(model: model)
            case .general:
                GeneralSettingsPane(model: model)
            case .behavior:
                BehaviorSettingsPane(model: model)
            case .diagnostics:
                DiagnosticsPane(model: model)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case permissions
    case general
    case behavior
    case diagnostics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .permissions:
            return "Permissions"
        case .general:
            return "General"
        case .behavior:
            return "Behavior"
        case .diagnostics:
            return "Diagnostics"
        }
    }

    var symbolName: String {
        switch self {
        case .permissions:
            return "lock.shield"
        case .general:
            return "gearshape"
        case .behavior:
            return "arrow.triangle.2.circlepath"
        case .diagnostics:
            return "waveform.path.ecg"
        }
    }
}

private struct PermissionsPane: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text(statusText)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(statusDetail)
                    .foregroundStyle(.secondary)
            }

            PermissionRow(
                title: "Accessibility",
                state: model.permissions.accessibility,
                required: true,
                detail: "Required to identify and move menu bar items after explicit user actions.",
                actionTitle: "Open System Prompt",
                action: model.requestAccessibility
            )

            PermissionRow(
                title: "Screen Recording",
                state: model.permissions.screenRecording,
                required: false,
                detail: "Only used for local icon previews and menu bar appearance. Hiding still works without it.",
                actionTitle: "Open Settings",
                action: model.openScreenRecordingSettings
            )

            Button("Refresh Status") {
                model.refreshPermissions()
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var statusText: String {
        switch model.permissions.capabilityStatus {
        case .missing:
            return "Core permission required"
        case .hasRequired:
            return "Core features enabled"
        case .hasAll:
            return "All features enabled"
        }
    }

    private var statusDetail: String {
        switch model.permissions.capabilityStatus {
        case .missing:
            return "Grant Accessibility before discovery, hiding, moving, and temporary reveal can run."
        case .hasRequired:
            return "Screen Recording is optional and only affects real icon previews."
        case .hasAll:
            return "The app can run core features and enhanced previews."
        }
    }
}

private struct PermissionRow: View {
    var title: String
    var state: PermissionState
    var required: Bool
    var detail: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(state == .granted ? .green : (required ? .orange : .secondary))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .fontWeight(.semibold)
                        Text(required ? "Required" : "Optional")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(state == .granted ? "Granted" : actionTitle, action: action)
                    .disabled(state == .granted)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
            Toggle("Show main menu bar icon", isOn: $model.settings.showMainIcon)
            Toggle("Enable always-hidden section", isOn: $model.settings.enableAlwaysHiddenSection)
            Picker("New items", selection: $model.settings.newItemsSection) {
                Text("Visible").tag(NewItemsSection.visible)
                Text("Hidden").tag(NewItemsSection.hidden)
                Text("Always Hidden").tag(NewItemsSection.alwaysHidden)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}

private struct BehaviorSettingsPane: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Auto re-hide", isOn: $model.settings.autoRehide)
            LabeledContent("Strategy", value: "Timer")
            Stepper(
                value: $model.settings.rehideInterval,
                in: 1...120,
                step: 1
            ) {
                Text("Re-hide interval: \(Int(model.settings.rehideInterval)) seconds")
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .onAppear {
            model.settings.rehideStrategy = .timer
        }
    }
}

private struct DiagnosticsPane: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Enable diagnostic logging", isOn: $model.settings.enableDiagnosticLogging)
            Toggle("Use Screen Recording previews when available", isOn: $model.settings.enableScreenRecordingPreviews)
            Text("Diagnostics must not record keyboard input, raw screenshots, or menu contents unless explicitly exported by the user.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(24)
    }
}
