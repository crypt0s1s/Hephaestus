#if DEBUG
import AnvilTheme
import SwiftUI

private struct AnvilWorkbenchControlsPreview: View {
    @State private var note = "Draft a reusable interaction step."
    @State private var plan = """
        ## Summary
        Build shared Anvil controls for workflow screens.

        ## Validation
        Run lint, build, and focused UI tests.
        """

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AnvilFieldSection(title: "Prompt") {
                HStack {
                    AnvilTextField(
                        text: $note,
                        configuration: AnvilTextFieldConfiguration(
                            placeholder: "Add a workflow note",
                            axis: .vertical,
                            lineLimit: 1...3,
                            accessibilityLabel: "Workflow note"
                        )
                    )

                    AnvilActionButton(
                        configuration: AnvilActionButtonConfiguration(
                            title: "Add note",
                            systemImage: "plus.message.fill",
                            style: .primary,
                            labelStyle: .iconOnly
                        ),
                        action: {}
                    )
                }
            }

            AnvilFieldSection(title: "Draft") {
                AnvilTextEditor(
                    text: $plan,
                    configuration: AnvilTextEditorConfiguration(
                        placeholder: "Write a plan...",
                        accessibilityLabel: "Draft plan"
                    )
                )
                .frame(minHeight: 160)
            }

            AnvilList(
                configuration: AnvilListConfiguration(
                    style: .elevated,
                    spacing: 0
                )
            ) {
                previewRow(status: .running, title: "Planner", detail: "Generating a draft plan.")
                Divider()
                previewRow(status: .waiting, title: "User review", detail: "Waiting for approval.")
                Divider()
                previewRow(status: .succeeded, title: "Validation", detail: "Required sections found.")
            }

            HStack {
                AnvilActionButton(
                    configuration: AnvilActionButtonConfiguration(
                        title: "Accept draft",
                        systemImage: "checkmark.circle.fill",
                        style: .primary
                    ),
                    action: {}
                )
                AnvilActionButton(
                    configuration: AnvilActionButtonConfiguration(
                        title: "Continue planning",
                        systemImage: "square.and.pencil"
                    ),
                    action: {}
                )
            }
        }
        .padding(20)
        .frame(width: 620)
        .anvilTheme(.fallback)
    }

    private func previewRow(
        status: AnvilStatusIndicatorState,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AnvilStatusIndicator(state: status)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
    }
}

#Preview("Anvil workbench controls") {
    AnvilWorkbenchControlsPreview()
}
#endif
