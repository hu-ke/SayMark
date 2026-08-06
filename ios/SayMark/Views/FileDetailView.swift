import SwiftUI

struct FileDetailView: View {
    @StateObject private var noteVM: NoteViewModel
    @ObservedObject var viewModel: FolderTreeViewModel
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editContent = ""

    init(note: NoteFile, viewModel: FolderTreeViewModel) {
        _noteVM = StateObject(wrappedValue: NoteViewModel(note: note))
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            if isEditing {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("名称", text: $editName)
                        .textFieldStyle(.roundedBorder)
                    TextEditor(text: $editContent)
                        .frame(minHeight: 320)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
                }
                .padding()
            } else {
                Text(noteVM.note.content.isEmpty ? "(无内容)" : noteVM.note.content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(noteVM.note.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "保存" : "编辑") {
                    if isEditing {
                        Task {
                            await noteVM.save(name: editName, content: editContent)
                            await viewModel.loadTree()
                            isEditing = false
                        }
                    } else {
                        editName = noteVM.note.name
                        editContent = noteVM.note.content
                        isEditing = true
                    }
                }
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { noteVM.error != nil },
            set: { if !$0 { noteVM.error = nil } }
        )) {
            Button("好") { noteVM.error = nil }
        } message: {
            Text(noteVM.error ?? "")
        }
    }
}
