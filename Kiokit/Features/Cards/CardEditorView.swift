import SwiftUI
import KiokitCore

struct CardEditorView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [AnkiNoteField]
    @State private var tags: String
    @State private var selectedDeck: UUID?
    @State private var noteTypeID: Int64?
    private let original: Flashcard?

    init(card: Flashcard? = nil, deckID: UUID? = nil) {
        original = card
        _fields = State(initialValue: card?.noteFields ?? [])
        _tags = State(initialValue: card?.tags.joined(separator: " ") ?? "")
        _selectedDeck = State(initialValue: card?.deckID ?? deckID)
        _noteTypeID = State(initialValue: card?.ankiNoteTypeID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(store.text("牌组"), selection: $selectedDeck) {
                        ForEach(store.decks) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker(store.text("笔记类型"), selection: $noteTypeID) {
                        ForEach(store.noteTypes, id: \.self) { type in
                            Text(type["name"].string).tag(Optional(type["id"].int))
                        }
                    }.disabled(original != nil).accessibilityIdentifier("noteType")
                }
                ForEach(fields.indices, id: \.self) { index in
                    Section(fields[index].name) {
                        TextEditor(text: Binding(get: { fields[index].value }, set: { fields[index].value = $0 }))
                            .frame(minHeight: 110)
                            .accessibilityIdentifier(index == 0 ? "cardFront" : index == 1 ? "cardBack" : "noteField-\(index)")
                    }
                }
                Section {
                    TextField(store.text("标签，用空格分隔"), text: $tags).autocorrectionDisabled()
                } footer: {
                    Text(store.text("编辑原始笔记字段会更新该笔记的所有卡片。字段内容支持 HTML；媒体文件名保持原样。")).ankiFootnote()
                }
            }
            .ankiForm()
            .navigationTitle(original == nil ? store.text("添加卡片") : store.text("编辑卡片"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.text("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.text("保存")) {
                        guard let selectedDeck, let noteTypeID else { return }
                        if store.saveNote(card: original, deckID: selectedDeck, noteTypeID: noteTypeID, fields: fields, tags: tags) { dismiss() }
                    }.fontWeight(.semibold).disabled(selectedDeck == nil || noteTypeID == nil)
                }
            }
            .onAppear {
                if selectedDeck == nil { selectedDeck = store.decks.first?.id }
                if noteTypeID == nil { noteTypeID = store.defaultNoteTypeID() }
                if fields.isEmpty, let noteTypeID { fields = store.newNoteFields(noteTypeID) }
            }
            .onChange(of: noteTypeID) { _, value in
                if original == nil, let value { fields = store.newNoteFields(value) }
            }
        }
    }
}
