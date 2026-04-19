import SwiftUI

// Sheet used by BookmarkDetailView for editing the custom title and the tag
// set. The PATCH sends the full `tags` array (replace semantics per handoff
// §5 — an empty array would clear tags, while omitting the key leaves them
// untouched), which matches this sheet's "save the visible list verbatim"
// model exactly.
struct BookmarkEditSheet: View {

    @Environment(\.dismiss) private var dismiss

    let model: BookmarkDetailModel

    @State private var customTitle: String = ""
    @State private var tags: [String] = []
    @State private var newTag: String = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Custom title (leave blank for extracted)", text: $customTitle)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    ForEach(tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button(role: .destructive) {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    HStack {
                        TextField("Add tag", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addTag)
                        Button("Add", action: addTag)
                            .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Tags are lowercased server-side; saving replaces the entire set.")
                        .font(.caption)
                }

                if let error = model.actionError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(saving)
                }
            }
            .onAppear(perform: hydrate)
            .disabled(saving)
        }
    }

    private func hydrate() {
        let bookmark = model.bookmark
        customTitle = bookmark.title ?? ""
        tags = bookmark.tags ?? []
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            newTag = ""
            return
        }
        tags.append(trimmed)
        newTag = ""
    }

    private func save() {
        saving = true
        let currentTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleToSend: String? = currentTitle.isEmpty ? nil : currentTitle

        Task {
            await model.applyEdits(customTitle: titleToSend, tags: tags)
            saving = false
            if model.actionError == nil { dismiss() }
        }
    }
}
