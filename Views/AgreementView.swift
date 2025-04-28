import SwiftUI

struct AgreementView: View {
    @AppStorage("hasAgreedToTerms") private var hasAgreedToTerms = false
    @State private var isShowingUserAgreement = false
    @State private var isShowingPrivacyPolicy = false
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.blue)
            
            Text("欢迎使用AI目标拆解")
                .font(.title)
                .fontWeight(.bold)
            
            Text("在使用本应用前，请阅读并同意我们的用户协议和隐私政策。")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack {
                Button(action: {
                    isShowingUserAgreement = true
                }) {
                    Text("用户协议")
                        .foregroundColor(.blue)
                        .underline()
                }
                
                Text("和")
                    .foregroundColor(.secondary)
                
                Button(action: {
                    isShowingPrivacyPolicy = true
                }) {
                    Text("隐私政策")
                        .foregroundColor(.blue)
                        .underline()
                }
            }
            .padding()
            
            Button(action: {
                hasAgreedToTerms = true
            }) {
                Text("同意并继续")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $isShowingUserAgreement) {
            NavigationStack {
                LegalDocumentView(title: "用户协议", documentPath: "UserAgreement.md")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") {
                                isShowingUserAgreement = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            NavigationStack {
                LegalDocumentView(title: "隐私政策", documentPath: "PrivacyPolicy.md")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") {
                                isShowingPrivacyPolicy = false
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    AgreementView()
} 