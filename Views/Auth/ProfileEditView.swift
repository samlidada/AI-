import SwiftUI
import PhotosUI

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @Environment(\.modelContext) private var modelContext
    
    // 用于临时存储编辑的用户信息
    @State private var editedName: String = ""
    @State private var editedAvatar: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingDeleteAlert = false
    
    // 保存按钮启用状态
    var saveEnabled: Bool {
        return editedName != userManager.userName || editedAvatar != nil
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 头像部分
                Section {
                    HStack {
                        Spacer()
                        
                        // 头像选择器
                        VStack {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                if let avatar = editedAvatar {
                                    Image(uiImage: avatar)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.blue, lineWidth: 2)
                                        )
                                } else if let currentAvatar = userManager.userAvatar {
                                    Image(uiImage: currentAvatar)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.blue, lineWidth: 2)
                                        )
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 100, height: 100)
                                        .foregroundColor(.blue)
                                }
                            }
                            .onChange(of: selectedPhoto) { oldValue, newValue in
                                loadSelectedPhoto(item: newValue)
                            }
                            
                            Text("点击更换头像")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
                
                // 用户名部分
                Section(header: Text("个人资料")) {
                    HStack {
                        Text("用户名")
                        Spacer()
                        TextField("请输入用户名", text: $editedName)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // 账户信息部分
                Section(header: Text("账户信息")) {
                    if !userManager.userEmail.isEmpty {
                        HStack {
                            Text("邮箱")
                            Spacer()
                            Text(userManager.userEmail)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 退出登录按钮
                Section {
                    Button(action: {
                        userManager.logout()
                        dismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("退出登录")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("删除账号（不可恢复）")
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveChanges()
                    }
                    .disabled(!saveEnabled)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // 初始化编辑状态
                editedName = userManager.userName
            }
            .alert("确定要删除账号吗？", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    Task {
                        await userManager.deleteAccount(modelContext: modelContext) { success in
                            if success {
                                dismiss()
                            } else {
                                // 可选：弹窗提示失败
                            }
                        }
                    }
                }
            } message: {
                Text("此操作将删除所有本地数据且无法恢复。\n删除后将自动退出登录。")
            }
        }
    }
    
    // 加载选择的照片
    private func loadSelectedPhoto(item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.editedAvatar = image
                    }
                }
            case .failure(let error):
                print("照片加载失败: \(error)")
            }
        }
    }
    
    // 保存更改
    private func saveChanges() {
        // 保存用户名
        if editedName != userManager.userName {
            userManager.saveUserName(editedName)
        }
        
        // 保存头像
        if let newAvatar = editedAvatar {
            userManager.saveUserAvatar(newAvatar)
        }
        
        // 发送通知
        NotificationCenter.default.post(name: Notification.Name("UserDidUpdate"), object: nil)
        
        // 关闭页面
        dismiss()
    }
}

#Preview {
    ProfileEditView()
} 