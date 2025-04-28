import Foundation

/// 消息结构
struct Message {
    let role: String
    let content: Any // 可以是字符串或图片数组
    
    /// 将消息转换为字典
    func toDictionary() -> [String: Any] {
        return [
            "role": role,
            "content": content
        ]
    }
}

/// AI服务基类
class AIService {
    /// 发送请求到AI服务
    /// - Parameters:
    ///   - messages: 消息列表
    ///   - maxTokens: 最大令牌数
    ///   - temperature: 温度参数
    ///   - retryCount: 重试次数
    /// - Returns: 文本响应
    func sendRequest(
        messages: [Message],
        maxTokens: Int,
        temperature: Double,
        retryCount: Int = 0
    ) async throws -> String {
        // 基类方法，需要由子类实现
        fatalError("必须由子类实现")
    }
    
    /// 发送请求到AI服务(兼容回调风格)
    /// - Parameters:
    ///   - messages: 消息列表(字典格式)
    ///   - maxTokens: 最大令牌数
    ///   - completion: 完成回调
    func sendRequest(
        messages: [[String: Any]],
        maxTokens: Int = 512,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // 转换消息格式
        let formattedMessages = messages.compactMap { messageDict -> Message? in
            guard let role = messageDict["role"] as? String,
                  let content = messageDict["content"] else {
                return nil
            }
            return Message(role: role, content: content)
        }
        
        // 使用异步方法
        Task {
            do {
                let response = try await sendRequest(
                    messages: formattedMessages,
                    maxTokens: maxTokens,
                    temperature: 0.7
                )
                // 主线程返回结果
                DispatchQueue.main.async {
                    completion(.success(response))
                }
            } catch {
                // 主线程返回错误
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
} 