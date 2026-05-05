import AnvilTheme
import AnvilUI
import SwiftUI

struct ProviderSettingsSheet: View {
    let state: ProviderSettingsPanelState
    let handle: (TaskWorkspaceAction) -> Void
    @Environment(\.anvilTheme) private var theme

    private var canSubmit: Bool {
        !state.isSaving && state.validation != .validating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.large) {
            header
            fields
            validationView
            errorBanner
            actions
        }
        .padding(theme.spacing.xLarge)
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: theme.spacing.medium) {
            AnvilIconTile(systemName: "gearshape")
            VStack(alignment: .leading, spacing: theme.spacing.xSmall) {
                Text("Provider Settings")
                    .font(theme.typography.pageTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                AnvilStatusPill(state.hasSavedAPIKey ? "Saved key available" : "No saved key")
            }
            Spacer()
            Button("Cancel") {
                handle(.dismissSettings)
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var fields: some View {
        AnvilPanelSection(title: "Connection") {
            baseURLField
            apiKeyField
            modelField
        }
    }

    private var baseURLField: some View {
        AnvilSurface {
            LabeledContent("Base URL") {
                TextField("https://api.openai.com/v1", text: baseURLBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerBaseURL)
            }
        }
    }

    private var apiKeyField: some View {
        AnvilSurface {
            LabeledContent("API key") {
                SecureField(apiKeyPlaceholder, text: apiKeyBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerAPIKey)
            }
        }
    }

    private var modelField: some View {
        AnvilSurface {
            LabeledContent("Model") {
                TextField("gpt-4.1-mini", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerModel)
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = state.errorMessage {
            ErrorBanner(message: errorMessage)
        }
    }

    private var actions: some View {
        HStack {
            Button("Clear") {
                handle(.clearProviderSettings)
            }
            .disabled(state.isSaving)
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerClear)

            Spacer()

            Button("Validate") {
                handle(.validateProviderSettings)
            }
            .disabled(!canSubmit)
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerValidate)

            Button("Save") {
                handle(.saveProviderSettings)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .accessibilityIdentifier(TaskWorkspaceAccessibilityID.providerSave)
        }
    }

    private var apiKeyPlaceholder: String {
        state.hasSavedAPIKey ? "Leave blank to keep saved key" : "Required"
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { state.baseURLString },
            set: { handle(.changeProviderBaseURL($0)) }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { state.apiKeyReplacement },
            set: { handle(.changeProviderAPIKey($0)) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { state.model },
            set: { handle(.changeProviderModel($0)) }
        )
    }

    @ViewBuilder
    private var validationView: some View {
        switch state.validation {
        case .idle:
            AnvilBanner(message: "Validate before saving live provider settings.", systemImage: "checkmark.shield")
        case .validating:
            HStack(spacing: theme.spacing.small) {
                ProgressView()
                    .controlSize(.small)
                AnvilStatusPill("Validating provider", tone: .warning)
            }
        case .success(let message):
            AnvilBanner(message: message, tone: .success, systemImage: "checkmark.circle.fill")
        case .failure(let message):
            AnvilBanner(message: message, tone: .danger, systemImage: "exclamationmark.triangle.fill")
        }
    }
}
