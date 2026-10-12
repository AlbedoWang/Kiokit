import SwiftUI
import UIKit
import KiokitCore

struct AnkiNumberField: View {
    @Environment(CollectionStore.self) private var store
    let title: String
    @Binding var value: Int
    let minimum: Int
    let accessibilityID: String
    var maximum = 9999
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var number: Int? {
        // Bounds come from the corresponding upstream Qt/Svelte control.
        guard let result = Int(draft), (minimum...maximum).contains(result) else { return nil }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                TextField("", text: $draft)
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    .monospacedDigit().foregroundStyle(AnkiTheme.ink)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(width: 104).background(AnkiTheme.subtle, in: RoundedRectangle(cornerRadius: 8))
                    .focused($focused).accessibilityLabel(title).accessibilityIdentifier(accessibilityID)
                    .onSubmit { finish() }
            }
            if focused && number == nil && !draft.isEmpty {
                Text(store.text("请输入 \(minimum) 到 \(maximum) 之间的整数。")).ankiFootnote()
                    .accessibilityIdentifier("invalidNumber-" + accessibilityID)
            }
        }
        .onAppear { draft = String(value) }
        .onDisappear { if focused { commit() } }
        .onChange(of: value) { _, new in if !focused { draft = String(new) } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { notification in
            guard let field = notification.object as? UITextField else { return }
            Task { @MainActor in
                if focused || field.accessibilityIdentifier == accessibilityID { field.selectAll(nil) }
            }
        }
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(store.text("完成")) { finish() }.accessibilityIdentifier("finishNumberInput")
                }
            }
        }
    }

    private func commit() {
        if let number {
            if number != value { value = number }
            draft = String(value)
        } else {
            draft = String(value)
        }
    }

    private func finish() {
        commit()
        focused = false
    }
}
