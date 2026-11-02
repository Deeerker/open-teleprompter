import SwiftUI

struct ScriptEditor: View {
    @Bindable var prompter: Prompter
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $prompter.text)
                .font(.title3)
                .focused($focused)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if prompter.text.isEmpty {
                        Text("Escribe o pega aquí tu texto…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle("Texto")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Borrar", role: .destructive) {
                            prompter.text = ""
                            focused = true
                        }
                        .disabled(prompter.text.isEmpty)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { dismiss() }
                    }
                }
        }
        .onAppear { focused = true }
    }
}
