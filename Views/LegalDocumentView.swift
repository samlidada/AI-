import SwiftUI
import Foundation

struct LegalDocumentView: View {
    let title: String
    let documentPath: String
    
    @State private var documentContent: AttributedString = AttributedString("")
    @State private var rawDocumentContent: String = ""
    @State private var isLoading = true
    @State private var loadError: Error? = nil
    @State private var showRawText = false // 是否显示纯文本
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView()
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let error = loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("无法加载文档")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if showRawText {
                        // 纯文本视图
                        Text(rawDocumentContent)
                            .font(.body)
                            .padding()
                            .textSelection(.enabled)
                            .lineSpacing(8) // 更大的行间距
                    } else {
                        // AttributedString视图
                        Text(documentContent)
                            .padding()
                            .textSelection(.enabled)
                            .lineSpacing(6)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showRawText.toggle()
                }) {
                    Image(systemName: showRawText ? "text.viewfinder" : "doc.plaintext")
                }
            }
        }
        .onAppear {
            loadDocument()
        }
    }
    
    private func loadDocument() {
        isLoading = true
        
        // 从documentPath中提取文件名
        let fileName = documentPath.components(separatedBy: "/").last?.components(separatedBy: ".").first ?? ""
        
        // 内置文档内容作为后备
        let userAgreement = """
# 用户协议

**最后更新日期：2025年4月10日**

欢迎使用"大 project"应用（以下简称"本应用"）。

本用户协议（以下简称"本协议"）是您与本应用开发者之间关于使用本应用服务的法律协议。

请您在使用本应用前仔细阅读本协议。

## 1. 协议接受

通过下载、安装或使用本应用，您表示您已阅读、理解并同意受本协议的约束。

如果您不同意本协议的任何条款，请勿使用本应用。

## 2. 服务描述

本应用是一款目标管理工具，提供以下功能：

- 目标创建和管理
- AI辅助目标拆解
- 任务执行和追踪
- 成果证明上传
- 目标评估和数据分析

## 3. 用户账户

### 3.1 账户安全

您有责任维护您账户的保密性，并对发生在您账户下的所有活动负责。

如果您发现任何未经授权使用您账户的情况，请立即通知我们。

### 3.2 账户内容

您通过本应用创建的内容，包括目标、子任务、上传的图片等，均属于您的个人内容。

您应对这些内容的合法性、准确性和适当性负责。

## 4. 用户行为规范

在使用本应用时，您同意不会：

- 违反任何适用的法律法规
- 侵犯他人的知识产权或其他权利
- 上传包含病毒、恶意代码的内容
- 干扰或破坏本应用的正常运行
- 使用本应用从事任何非法或不道德活动

## 5. 知识产权

### 5.1 应用权利

本应用的所有权利（包括但不限于软件、界面设计、商标、专利等）均归本应用开发者所有。

### 5.2 用户内容

您保留您通过本应用创建或上传的内容的所有权利。

同时，您授予我们非排他性、可转让、可再许可、免版税的全球性许可，以便我们可以使用、复制、修改、展示、分发您的内容，用于提供和改进本应用的服务。

## 6. 服务限制与变更

### 6.1 服务可用性

我们会尽力确保本应用的稳定运行，但不能保证服务不会中断或没有错误。

我们保留随时修改、暂停或终止部分或全部服务的权利，而无需事先通知。

### 6.2 功能更新

我们可能会不时更新本应用或更改其功能。

更新可能包括错误修复、功能改进或性能优化。

## 7. 免责声明

### 7.1 无担保声明

本应用按"现状"和"可用性"提供，不提供任何明示或暗示的担保。

### 7.2 责任限制

在法律允许的最大范围内，我们不对因使用或无法使用本应用而导致的任何直接、间接、附带、特殊、惩罚性或后果性损害承担责任。

## 8. 协议变更

我们可能会不时修改本协议。

修改后的协议将在本应用内公布。

如果您在协议修改后继续使用本应用，即表示您接受修改后的协议。

## 9. 法律适用

本协议受中华人民共和国法律管辖。

与本协议相关的任何争议应首先通过友好协商解决。

## 10. 联系我们

如果您对本协议有任何疑问或建议，请通过以下方式联系我们：

- 电子邮件：[13922045600@163.com](mailto:13922045600@163.com)
"""
        
        let privacyPolicy = """
# 隐私政策

**最后更新日期：2025年4月10日**

欢迎使用"大 project"应用。

本隐私政策旨在向您说明我们如何收集、使用、存储和保护您的个人信息。

请您在使用我们的服务前仔细阅读本政策。

## 1. 信息收集与使用

### 1.1 我们收集的信息

- **账户信息**：注册时提供的用户名、邮箱地址等信息。
- **用户内容**：您在应用中创建的目标、子任务、描述、截止日期等内容。
- **上传的图像**：您上传作为任务完成证明的图片。
- **设备信息**：设备型号、操作系统版本、唯一设备标识符等。
- **使用数据**：您如何使用应用的信息，如功能使用频率、应用崩溃信息等。

### 1.2 信息使用目的

- 提供、维护和改进我们的服务
- 开发新功能和服务
- 个性化您的体验并提供更相关的内容和建议
- 响应您的反馈、问题和请求
- 监控和分析使用趋势和活动
- 保护我们服务的安全和完整性

## 2. 数据存储

### 2.1 本地存储

- 您的大部分数据（包括目标、子任务和上传的图片）默认存储在您的设备本地。
- 这些数据由SwiftData框架管理，受设备系统安全机制保护。

### 2.2 备份机制

- 目前应用不提供自动云备份功能。
- 未来版本可能添加数据备份功能，届时我们会更新本政策并获取您的同意。

## 3. 数据共享

我们不会出售您的个人信息。

在以下情况下，我们可能会共享您的信息：

- **第三方服务提供商**：我们可能使用第三方服务来辅助我们提供服务，如数据分析、AI服务等。
- **通义千问API**：在您使用目标拆解、评估等AI功能时，我们会向通义千问API发送您的目标内容，以获取分析结果。
- **法律要求**：当法律要求披露您的信息时，我们可能会披露您的信息。
- **应用功能**：在您明确同意的情况下，如使用分享功能时。

## 4. 数据安全

我们采取合理的措施保护您的信息：

- 使用加密技术保护数据传输
- 严格限制对个人信息的访问
- 定期审查我们的信息收集、存储和处理实践

## 5. 您的权利与选择

您对个人信息拥有以下权利：

- **访问**：您可以随时在应用中查看您创建的所有内容。
- **删除**：您可以删除您的目标、子任务和上传的图片。
- **权限控制**：您可以通过设备设置控制应用对相机、相册的访问权限。

## 6. 针对儿童的政策

我们的服务不面向13岁以下的儿童。

我们不会故意收集13岁以下儿童的个人信息。

如果发现我们无意中收集了儿童的个人信息，我们将立即采取措施删除。

## 7. 隐私政策更新

我们可能会不时更新本隐私政策。

更新后的版本将在应用内发布，并注明更新日期。

重大变更时，我们会通过应用内通知或其他方式通知您。

## 8. 联系我们

如果您对本隐私政策有任何疑问或建议，请通过以下方式联系我们：

- 电子邮件：[13922045600@163.com](mailto:13922045600@163.com)
"""
        
        // 尝试多种方式加载文档
        
        // 方式1：从Docs目录加载（直接使用内置的文件路径）
        if let docsPath = Bundle.main.path(forResource: fileName, ofType: "md", inDirectory: "Docs") {
            do {
                let markdownString = try String(contentsOfFile: docsPath, encoding: .utf8)
                loadMarkdown(markdownString)
                return
            } catch {
                print("从Docs目录加载失败: \(error)")
            }
        }
        
        // 方式2：尝试从Bundle直接加载
        if let fileURL = Bundle.main.url(forResource: fileName, withExtension: "md") {
            do {
                let markdownString = try String(contentsOf: fileURL, encoding: .utf8)
                loadMarkdown(markdownString)
                return
            } catch {
                print("从Bundle直接加载失败: \(error)")
            }
        }
        
        // 方式3：使用内置文档作为后备
        if fileName == "UserAgreement" {
            loadMarkdown(userAgreement)
        } else if fileName == "PrivacyPolicy" {
            loadMarkdown(privacyPolicy)
        } else {
            loadError = NSError(domain: "LegalDocumentError", code: 404, userInfo: [NSLocalizedDescriptionKey: "找不到文档文件"])
            isLoading = false
        }
    }
    
    private func loadMarkdown(_ markdownString: String) {
        // 保存原始文本，用于纯文本视图
        rawDocumentContent = markdownString
        
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace  // 保留空白和换行
        
        do {
            documentContent = try AttributedString(markdown: markdownString, options: options)
        } catch {
            // 如果带选项解析失败，尝试不带选项解析
            do {
                documentContent = try AttributedString(markdown: markdownString)
            } catch {
                // 如果Markdown解析失败，使用纯文本，但保留换行
                var plainText = AttributedString(markdownString)
                plainText.font = .body
                documentContent = plainText
                print("Markdown解析错误: \(error)")
            }
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(title: "用户协议", documentPath: "UserAgreement.md")
    }
} 