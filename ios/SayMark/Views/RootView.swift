import SwiftUI

struct RootView: View {
    @StateObject private var viewModel = FolderTreeViewModel()
    @State private var showNewItem = false
    @State private var showRecord = false
    @State private var showCommand = false
    @State private var locateFolderId: String?

    var body: some View {
        NavigationStack {
            FolderTreeView(viewModel: viewModel, locateFolderId: $locateFolderId)
                .navigationTitle("语音记事本")
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        // 录音按钮
                        Button {
                            showRecord = true
                        } label: {
                            Image(systemName: "mic")
                        }
                        // 指令按钮
                        Button {
                            showCommand = true
                        } label: {
                            Image(systemName: "command")
                        }
                        // 新建按钮
                        Button {
                            showNewItem = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showNewItem) {
                    NewItemSheet(viewModel: viewModel, parentId: nil)
                }
                .sheet(isPresented: $showRecord) {
                    RecordNoteView(viewModel: viewModel, targetFolderId: nil)
                }
                .sheet(isPresented: $showCommand) {
                    CommandInputView(viewModel: viewModel, onSelectFolder: { folderId in
                        locateFolderId = folderId
                        viewModel.locate(folderId: folderId)
                    })
                }
        }
        .task {
            await viewModel.loadTree()
        }
    }
}
