import SwiftUI

struct PermissionsView: View {
    @State private var accessibilityGranted = false
    @State private var fullDiskAccessGranted = false

    private let checker = PermissionsChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            Text("Permissions")
                .font(.headline)
                .padding(.top, 6)
                .padding(.bottom, 8)

            VStack(spacing: 1) {
                permissionRow(
                    icon: accessibilityGranted ? "checkmark.shield.fill" : "lock.shield",
                    iconColor: accessibilityGranted ? .green : .orange,
                    title: "Accessibility",
                    description: "Required for the global hotkey (⌥Space).",
                    granted: accessibilityGranted,
                    action: {
                        if accessibilityGranted {
                            checker.openAccessibilitySettings()
                        } else {
                            checker.requestAccessibility()
                        }
                    }
                )

                Divider().padding(.horizontal, 12)

                permissionRow(
                    icon: fullDiskAccessGranted ? "checkmark.shield.fill" : "lock.shield",
                    iconColor: fullDiskAccessGranted ? .green : .orange,
                    title: "Full Disk Access",
                    description: fullDiskAccessGranted
                        ? "Required to read, write, and edit files."
                        : "Click Open Settings, then press '+' and add Tamagotchai.",
                    granted: fullDiskAccessGranted,
                    action: {
                        checker.openFullDiskAccessSettings()
                        checker.revealAppInFinder()
                    }
                )
            }

            Divider()
                .padding(.top, 8)

            HStack {
                Button("Refresh") {
                    refreshStatuses()
                }
                Spacer()
                Button("Done") {
                    PermissionsWindowController.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 380)
        .onAppear { refreshStatuses() }
    }

    private func refreshStatuses() {
        accessibilityGranted = checker.isAccessibilityGranted()
        fullDiskAccessGranted = checker.isFullDiskAccessGranted()
    }

    private func permissionRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).fontWeight(.medium)
                Text(description).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Button("Open Settings") { action() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
