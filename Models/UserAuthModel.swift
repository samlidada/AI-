import Foundation
import SwiftData
import Combine
import UIKit

// 用户信息模型
class UserManager: ObservableObject {
    // 单例模式
    static let shared = UserManager()
    
    // 添加判断是否为审核账号的属性
    @Published var isReviewAccount: Bool = false
    
    // UserDefaults键
    private let userIDKey = "UserManager.userID"
    private let userEmailKey = "UserManager.userEmail"
    private let userNameKey = "UserManager.userName"
    private let isLoggedInKey = "UserManager.isLoggedIn"
    private let userAvatarKey = "UserManager.userAvatar"
    
    // 用户特定数据的键前缀
    private let userDataPrefix = "UserData."
    
    // 公开属性，用于绑定UI
    @Published var isLoggedIn: Bool = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var userID: String = ""
    @Published var userAvatar: UIImage?
    
    private init() {
        // 从UserDefaults加载用户状态
        loadUserState()
    }
    
    // 加载用户状态
    private func loadUserState() {
        let defaults = UserDefaults.standard
        
        isLoggedIn = defaults.bool(forKey: isLoggedInKey)
        userID = defaults.string(forKey: userIDKey) ?? ""
        userEmail = defaults.string(forKey: userEmailKey) ?? ""
        userName = defaults.string(forKey: userNameKey) ?? ""
        
        // 加载头像
        loadUserAvatar()
        
        // 如果已登录但用户名为空，尝试从存储的用户特定数据恢复
        if isLoggedIn && !userID.isEmpty && userName.isEmpty {
            restoreUserData()
        }
    }
    
    // 生成特定用户的数据键
    private func userSpecificKey(_ key: String) -> String {
        return "\(userDataPrefix)\(userID).\(key)"
    }
    
    // 保存用户特定数据
    private func saveUserSpecificData() {
        guard !userID.isEmpty else { return }
        
        let defaults = UserDefaults.standard
        
        // 保存用户名到用户特定位置
        if !userName.isEmpty {
            defaults.set(userName, forKey: userSpecificKey("userName"))
        }
        
        // 保存邮箱到用户特定位置
        if !userEmail.isEmpty {
            defaults.set(userEmail, forKey: userSpecificKey("userEmail"))
        }
        
        // 保存头像到用户特定位置
        if let avatar = userAvatar, let imageData = avatar.jpegData(compressionQuality: 0.8) {
            defaults.set(imageData, forKey: userSpecificKey("userAvatar"))
        }
    }
    
    // 恢复用户特定数据
    private func restoreUserData() {
        guard !userID.isEmpty else { return }
        
        let defaults = UserDefaults.standard
        
        // 恢复用户名
        if let savedName = defaults.string(forKey: userSpecificKey("userName")), userName.isEmpty {
            userName = savedName
            defaults.set(savedName, forKey: userNameKey)
        }
        
        // 恢复邮箱
        if let savedEmail = defaults.string(forKey: userSpecificKey("userEmail")), userEmail.isEmpty {
            userEmail = savedEmail
            defaults.set(savedEmail, forKey: userEmailKey)
        }
        
        // 恢复头像
        if userAvatar == nil, let avatarData = defaults.data(forKey: userSpecificKey("userAvatar")),
           let image = UIImage(data: avatarData) {
            userAvatar = image
            defaults.set(avatarData, forKey: userAvatarKey)
        }
    }
    
    // 加载用户头像
    private func loadUserAvatar() {
        if let avatarData = UserDefaults.standard.data(forKey: userAvatarKey),
           let image = UIImage(data: avatarData) {
            self.userAvatar = image
        } else {
            // 默认头像使用系统图标
            self.userAvatar = nil
        }
    }
    
    // 保存用户头像
    func saveUserAvatar(_ image: UIImage) {
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(imageData, forKey: userAvatarKey)
            self.userAvatar = image
            
            // 同时保存到用户特定存储
            if !userID.isEmpty {
                UserDefaults.standard.set(imageData, forKey: userSpecificKey("userAvatar"))
            }
            
            // 发送通知
            NotificationCenter.default.post(name: Notification.Name("UserAvatarDidChange"), object: nil)
        }
    }
    
    // 获取用户头像
    func getUserAvatar() -> UIImage {
        if let avatar = userAvatar {
            return avatar
        } else {
            // 返回默认头像
            return UIImage(systemName: "person.circle.fill") ?? UIImage()
        }
    }
    
    // Apple ID登录成功处理
    func loginWithApple(userID: String, email: String?, name: String?) {
        let defaults = UserDefaults.standard
        
        // 存储用户信息
        self.userID = userID
        defaults.set(userID, forKey: userIDKey)
        
        if let email = email {
            self.userEmail = email
            defaults.set(email, forKey: userEmailKey)
            
            // 检查是否为App Store审核账号
            if email == "appreview@goalapp.test" {
                print("检测到App Store审核账号登录")
                self.isReviewAccount = true
                NotificationCenter.default.post(name: Notification.Name("AppStoreReviewLogin"), object: nil)
            } else {
                self.isReviewAccount = false
            }
        }
        
        if let name = name {
            self.userName = name
            defaults.set(name, forKey: userNameKey)
        }
        
        // 更新登录状态
        self.isLoggedIn = true
        defaults.set(true, forKey: isLoggedInKey)
        
        // 尝试恢复用户特定数据
        restoreUserData()
        
        // 确保将当前数据也保存为用户特定数据
        saveUserSpecificData()
        
        // 发送通知
        NotificationCenter.default.post(name: Notification.Name("UserDidLogin"), object: nil)
    }
    
    // 保存用户名
    func saveUserName(_ name: String) {
        userName = name
        UserDefaults.standard.set(name, forKey: userNameKey)
        
        // 同时保存到用户特定存储
        if !userID.isEmpty {
            UserDefaults.standard.set(name, forKey: userSpecificKey("userName"))
        }
        
        // 发送通知
        NotificationCenter.default.post(name: Notification.Name("UserDidUpdate"), object: nil)
    }
    
    // 退出登录
    func logout() {
        // 在登出之前确保保存了用户特定数据
        saveUserSpecificData()
        
        let defaults = UserDefaults.standard
        
        // 清除当前会话信息
        userID = ""
        userName = ""
        userEmail = ""
        isLoggedIn = false
        userAvatar = nil
        isReviewAccount = false  // 重置审核账号状态
        
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: userNameKey)
        defaults.removeObject(forKey: userEmailKey)
        defaults.removeObject(forKey: userAvatarKey)
        defaults.set(false, forKey: isLoggedInKey)
        
        // 发送通知
        NotificationCenter.default.post(name: Notification.Name("UserDidLogout"), object: nil)
    }
    
    // 获取显示名称
    var displayName: String {
        if !userName.isEmpty {
            return userName
        } else if !userEmail.isEmpty {
            return userEmail
        } else {
            return "用户"
        }
    }
    
    // 注销账号并彻底删除所有本地数据
    @MainActor
    func deleteAccount(modelContext: ModelContext?, completion: @escaping (Bool) -> Void) async {
        if let context = modelContext {
            do {
                // 1. 先删CompletionProof
                let proofs = try context.fetch(FetchDescriptor<CompletionProof>())
                for proof in proofs {
                    context.delete(proof)
                }
                // 2. 再删ProofImage
                let images = try context.fetch(FetchDescriptor<ProofImage>())
                for image in images {
                    context.delete(image)
                }
                // 3. 再删SubTask
                let subTasks = try context.fetch(FetchDescriptor<SubTask>())
                for subTask in subTasks {
                    context.delete(subTask)
                }
                // 4. 最后删Goal
                let goals = try context.fetch(FetchDescriptor<Goal>())
                for goal in goals {
                    context.delete(goal)
                }
                try context.save()
            } catch {
                print("删除SwiftData数据失败: \(error)")
                completion(false)
                return
            }
        }
        // 2. 清除所有UserDefaults中的用户信息
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: userNameKey)
        defaults.removeObject(forKey: userEmailKey)
        defaults.removeObject(forKey: userAvatarKey)
        defaults.set(false, forKey: isLoggedInKey)
        // 清除用户特定数据
        if !userID.isEmpty {
            defaults.removeObject(forKey: userSpecificKey("userName"))
            defaults.removeObject(forKey: userSpecificKey("userEmail"))
            defaults.removeObject(forKey: userSpecificKey("userAvatar"))
        }
        // 3. 清除内存中的用户信息
        userID = ""
        userName = ""
        userEmail = ""
        isLoggedIn = false
        userAvatar = nil
        isReviewAccount = false
        // 4. 发送通知
        NotificationCenter.default.post(name: Notification.Name("UserDidDeleteAccount"), object: nil)
        completion(true)
    }
} 