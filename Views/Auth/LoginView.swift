import SwiftUI
import AuthenticationServices
import CryptoKit

// 登录视图
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LoginViewModel()
    @State private var showAlert = false
    @State private var alertMessage = ""
    @EnvironmentObject private var userManager: UserManager
    
    // 是否显示测试按钮(仅在开发环境显示)
    private var showTestButton: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // 顶部Logo和标题
            VStack(spacing: 15) {
                Image(systemName: "checklist")
                    .font(.system(size: 70))
                    .foregroundColor(.blue)
                
                Text("AI目标拆解")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("登录以同步您的目标数据")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 60)
            
            Spacer()
            
            // 仅在开发环境下显示测试账号按钮
            if showTestButton {
                Button(action: {
                    // 使用App Store审核测试账号登录
                    UserManager.shared.loginWithApple(
                        userID: "appreview_test_id",
                        email: "appreview@goalapp.test",
                        name: "审核测试账号"
                    )
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundColor(.white)
                        Text("使用测试账号")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
            
            // 登录选项
            VStack(spacing: 20) {
                // 自定义中文Apple登录按钮
                Button(action: {
                    viewModel.startAppleSignInProcess()
                }) {
                    HStack {
                        Image(systemName: "applelogo")
                            .font(.title3)
                        
                        Text("通过 Apple 账号登录")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 30)
                
                // 跳过登录按钮
                Button(action: {
                    dismiss()
                }) {
                    Text("稍后再说")
                        .foregroundColor(.secondary)
                }
                .padding(.top, 10)
            }
            .padding(.bottom, 60)
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text(viewModel.alertTitle),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("确定")) {
                    if viewModel.loginSuccessful {
                        dismiss()
                    }
                }
            )
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

// 登录视图模型
class LoginViewModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var loginSuccessful = false
    
    // 当前的随机字符串，用于防止CSRF攻击
    private var currentNonce: String?
    
    // 启动Apple登录流程
    func startAppleSignInProcess() {
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    // 提供呈现上下文
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // 获取当前活跃的窗口（兼容iOS 15+）
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        
        // 兼容旧版本，虽然已弃用但可作为备用
        #if compiler(>=5.7)
        if #available(iOS 15.0, *) {
            // iOS 15及以上不应该走到这里
            return UIWindow()
        } else {
            return UIApplication.shared.windows.first ?? UIWindow()
        }
        #else
        return UIApplication.shared.windows.first ?? UIWindow()
        #endif
    }
    
    // 授权成功回调
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // 验证nonce
            guard let currentNonce = currentNonce else {
                showLoginError(title: "登录失败", message: "无效的安全状态")
                return
            }
            
            // 理论上需要在这里验证nonce，但简化处理
            _ = currentNonce
            
            // 处理用户信息
            let userId = appleIDCredential.user
            let email = appleIDCredential.email
            
            var name: String?
            if let fullName = appleIDCredential.fullName {
                var nameComponents: [String] = []
                
                if let givenName = fullName.givenName {
                    nameComponents.append(givenName)
                }
                
                if let familyName = fullName.familyName {
                    nameComponents.append(familyName)
                }
                
                if !nameComponents.isEmpty {
                    name = nameComponents.joined(separator: " ")
                }
            }
            
            // 登录成功，保存用户信息
            UserManager.shared.loginWithApple(userID: userId, email: email, name: name)
            
            // 显示成功消息
            loginSuccessful = true
            DispatchQueue.main.async {
                self.alertTitle = "登录成功"
                self.alertMessage = "欢迎使用AI目标拆解应用"
                self.showAlert = true
            }
        }
    }
    
    // 授权失败回调
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // 将错误转换为中文提示
        let errorMessage = getChineseErrorMessage(from: error)
        showLoginError(title: "登录失败", message: errorMessage)
    }
    
    // 将错误信息转换为中文
    private func getChineseErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        
        // 根据错误码判断具体原因
        switch nsError.code {
        case ASAuthorizationError.canceled.rawValue:
            return "您已取消登录"
        case ASAuthorizationError.unknown.rawValue:
            return "发生未知错误，请稍后再试"
        case ASAuthorizationError.invalidResponse.rawValue:
            return "无效的响应，请重新尝试"
        case ASAuthorizationError.notHandled.rawValue:
            return "请求未被处理"
        case ASAuthorizationError.failed.rawValue:
            return "授权请求失败"
        case ASAuthorizationError.notInteractive.rawValue:
            return "无法处理非交互式请求"
        default:
            // 针对其他错误，尝试从本地化描述中提取信息
            if nsError.localizedDescription.contains("network") {
                return "网络连接出现问题，请检查网络后再试"
            } else if nsError.localizedDescription.contains("timeout") {
                return "请求超时，请稍后重试"
            } else if nsError.localizedDescription.contains("cancel") || nsError.localizedDescription.contains("取消") {
                return "您已取消登录"
            } else {
                // 如果无法识别具体错误，返回通用错误信息
                return "登录失败，请稍后再试"
            }
        }
    }
    
    // 显示登录错误
    private func showLoginError(title: String, message: String) {
        DispatchQueue.main.async {
            self.alertTitle = title
            self.alertMessage = message
            self.showAlert = true
        }
    }
    
    // 生成随机字符串
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("无法生成随机字节: \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    // SHA256散列
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

#Preview {
    LoginView()
} 