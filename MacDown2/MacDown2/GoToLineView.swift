import SwiftUI

/// Content of `GoToLinePanel` (epic-22-implementation.md §6.7, §17 Slice 2b).
struct GoToLineView: View {
    @State private var input = ""
    @FocusState private var isFocused: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Go to Line")
                .font(.headline)
            TextField("Line, or Line:Column", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                // Return must respect the same empty-input guard as the "Go"
                // button below, not bypass it (hostile review finding, PR #126).
                .onSubmit { guard !input.isEmpty else { return }; onSubmit(input) }
                .accessibilityIdentifier("goToLineField")

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Go") { onSubmit(input) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.isEmpty)
            }
        }
        .padding()
        .onAppear { isFocused = true }
    }
}
