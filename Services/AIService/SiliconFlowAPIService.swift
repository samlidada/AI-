import Foundation

/// 硅基流动平台API服务
class SiliconFlowAPIService: AIService {
    static let shared = SiliconFlowAPIService(apiKey: "sk-ymyhdfwdhgkksjnakhrimqgdfxpebirmpwemkkrkejcjnben", endpoint: "https://api.siliconflow.cn/v1/chat/completions")
    
    /// API密钥
    private var apiKey: String
    
    /// API终端URL
    private var endpoint: String
    
    /// 请求模式枚举
    enum RequestMode {
        case textOnly       // 纯文本请求(如目标分解)
        case multimodal     // 多模态请求(如评估报告)
    }
    
    /// 当前请求模式
    private var currentRequestMode: RequestMode = .textOnly
    
    /// 可用模型列表 - 更新为最新的通义千问模型名称
    private let availableModels = [
        "Pro/Qwen/Qwen2.5-VL-7B-Instruct",  // 支持图片的VLM模型放在最前面
        "Qwen/Qwen2.5-VL-7B-Instruct",      // 第二个也是支持图片的VLM模型
        "Pro/Qwen/Qwen2.5-7B-Instruct",
        "Qwen/Qwen2.5-7B-Instruct", 
        "Qwen/Qwen2.5-72B-Instruct",
        "Qwen/Qwen2-7B-Instruct",
        "Qwen/QwQ-32B"
    ]
    
    /// 文本模型列表 - 最适合纯文本请求的模型
    private let textModels = [
        "Pro/Qwen/Qwen2.5-7B-Instruct",
        "Qwen/Qwen2.5-7B-Instruct", 
        "Qwen/Qwen2.5-72B-Instruct",
        "Qwen/Qwen2-7B-Instruct",
        "Qwen/QwQ-32B"
    ]
    
    /// 视觉模型列表 - 支持图片的VLM模型
    private let visionModels = [
        "Pro/Qwen/Qwen2.5-VL-7B-Instruct",
        "Qwen/Qwen2.5-VL-7B-Instruct"
    ]
    
    /// 当前模型索引
    private var currentModelIndex = 0
    
    /// 当前模型名称
    private var modelName: String {
        return availableModels[currentModelIndex]
    }
    
    /// 获取当前模型名称
    var currentModelName: String {
        return modelName
    }
    
    /// 日志文件URL
    private lazy var logFileURL: URL = {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // 创建AppLogs目录
        let appLogsDirectory = documentsDirectory.appendingPathComponent("AppLogs")
        if !fileManager.fileExists(atPath: appLogsDirectory.path) {
            try? fileManager.createDirectory(at: appLogsDirectory, withIntermediateDirectories: true)
        }
        
        return appLogsDirectory.appendingPathComponent("silicon_flow_api.log")
    }()
    
    /// 初始化服务
    /// - Parameters:
    ///   - apiKey: API密钥
    ///   - endpoint: API终端URL
    init(apiKey: String, endpoint: String) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        
        // 调用父类初始化方法
        super.init()
        
        // 初始化时记录一些基本信息
        log("初始化SiliconFlowAPIService")
        log("API终端URL: \(endpoint)")
        log("API密钥前缀: \(String(apiKey.prefix(8)))...")
        log("可用模型列表: \(availableModels.joined(separator: ", "))")
        log("当前使用模型: \(modelName)")
    }
    
    /// 记录日志
    /// - Parameter message: 日志消息
    func log(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"
        
        // 打印到控制台
        print(logMessage)
        
        // 写入到文件
        do {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("写入日志失败: \(error.localizedDescription)")
        }
    }
    
    /// 设置请求模式
    /// - Parameter mode: 请求模式
    func setRequestMode(_ mode: RequestMode) {
        currentRequestMode = mode
        
        // 根据模式选择合适的模型
        switch mode {
        case .textOnly:
            // 使用第一个可用的文本模型
            if let index = availableModels.firstIndex(where: { textModels.contains($0) }) {
                currentModelIndex = index
                log("设置为纯文本模式，使用模型: \(modelName)")
            }
        case .multimodal:
            // 使用第一个可用的视觉模型
            if let index = availableModels.firstIndex(where: { visionModels.contains($0) }) {
                currentModelIndex = index
                log("设置为多模态模式，使用模型: \(modelName)")
            }
        }
    }
    
    /// 根据消息内容自动检测并设置请求模式
    /// - Parameter messages: 消息数组
    private func autoDetectAndSetMode(for messages: [[String: Any]]) {
        // 检查是否包含图片
        var containsImages = false
        
        for message in messages {
            if let content = message["content"] as? [[String: Any]] {
                for item in content {
                    if let type = item["type"] as? String, type == "image_url" {
                        containsImages = true
                        break
                    }
                }
            }
            if containsImages { break }
        }
        
        // 根据是否包含图片设置模式
        setRequestMode(containsImages ? .multimodal : .textOnly)
    }
    
    /// 尝试使用下一个适合当前请求模式的模型
    /// - Returns: 是否成功切换到新模型
    func tryNextModel() -> Bool {
        let previousModel = modelName
        let previousIndex = currentModelIndex
        
        // 根据当前请求模式获取合适的模型列表
        let suitableModels = currentRequestMode == .multimodal ? visionModels : textModels
        
        // 找到当前模型在合适模型列表中的位置
        let currentModelInList = suitableModels.firstIndex(of: previousModel)
        
        // 尝试切换到下一个合适的模型
        if let currentIndex = currentModelInList, currentIndex + 1 < suitableModels.count {
            // 有下一个合适的模型，直接切换
            let nextSuitableModel = suitableModels[currentIndex + 1]
            if let indexInAllModels = availableModels.firstIndex(of: nextSuitableModel) {
                currentModelIndex = indexInAllModels
                log("在\(currentRequestMode == .multimodal ? "多模态" : "纯文本")模式下切换模型: 从 \(previousModel) 到 \(modelName)")
                return true
            }
        }
        
        // 如果已经用完了所有合适的模型，尝试从完整列表中找下一个
        currentModelIndex = (currentModelIndex + 1) % availableModels.count
        
        // 如果遍历了所有模型又回到了起点，则返回失败
        if modelName == previousModel || currentModelIndex == previousIndex {
            log("所有\(currentRequestMode == .multimodal ? "多模态" : "纯文本")模型都已尝试，未找到可用模型")
            log("可用合适模型列表: \(suitableModels.joined(separator: ", "))")
            return false
        }
        
        log("切换到下一个模型: \(modelName)")
        return true
    }
    
    /// 发送请求到API
    /// - Parameters:
    ///   - messages: 消息数组
    ///   - maxTokens: 最大token数
    ///   - temperature: 温度参数
    ///   - retryCount: 重试次数
    /// - Returns: API响应内容
    func sendRequest(messages: [[String: Any]], maxTokens: Int = 1024, temperature: Double = 0.7, retryCount: Int = 0) async throws -> String {
        // 检查网络连接
        
        guard retryCount < availableModels.count else {
            log("错误: 所有模型都尝试失败")
            throw APIError.allModelsFailedError
        }
        
        // 自动检测并设置适合的请求模式
        autoDetectAndSetMode(for: messages)
        
        // 记录当前使用的模型
        log("使用模型: \(modelName), 请求模式: \(currentRequestMode == .multimodal ? "多模态" : "纯文本"), 消息数: \(messages.count)")
        
        // 检查是否包含多模态内容
        var imageCount = 0
        var totalImageSize = 0
        for message in messages {
            if let content = message["content"] as? [[String: Any]] {
                // 计算图片数量和总大小
                for item in content {
                    if let type = item["type"] as? String, type == "image_url" {
                        imageCount += 1
                        if let imageUrl = item["image_url"] as? [String: String],
                           let urlString = imageUrl["url"],
                           urlString.hasPrefix("data:image") {
                            // 提取base64数据
                            let components = urlString.components(separatedBy: ",")
                            if components.count > 1, let base64Data = components.last,
                               let data = Data(base64Encoded: base64Data) {
                                totalImageSize += data.count
                            }
                        }
                    }
                }
            }
        }
        
        // 如果包含图片，记录多模态请求信息
        if imageCount > 0 {
            log("多模态请求: 包含\(imageCount)张图片, 总大小约\(totalImageSize / 1024)KB")
        }
        
        // 构建URL
        guard let url = URL(string: endpoint) else {
            log("错误: 无效的URL: \(endpoint)")
            throw APIError.invalidURL
        }
        
        // 准备请求体
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages.map { message -> [String: Any] in 
                // 检查content类型
                if let contentString = message["content"] as? String {
                    return ["role": message["role"] as! String, "content": contentString]
                } else if let contentArray = message["content"] as? [[String: Any]] {
                    return ["role": message["role"] as! String, "content": contentArray]
                } else {
                    // 默认返回空字符串
                    return ["role": message["role"] as! String, "content": ""]
                }
            },
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
        
        // 记录请求详情
        log("请求详情: \(formatRequestBody(requestBody))")
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // 将请求体编码为JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            log("错误: 请求编码失败: \(error.localizedDescription)")
            throw APIError.requestEncodingFailed
        }
        
        // 发送请求
        log("发送请求到: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // 检查HTTP响应
            guard let httpResponse = response as? HTTPURLResponse else {
                log("错误: 收到非HTTP响应")
                
                // 尝试下一个模型
                if tryNextModel() {
                    return try await sendRequest(messages: messages, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
                }
                throw APIError.invalidResponseFormat
            }
            
            // 记录响应状态
            log("收到响应 - 状态码: \(httpResponse.statusCode)")
            
            // 检查状态码
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
                log("错误: HTTP状态错误 \(httpResponse.statusCode): \(errorMessage)")
                log("当前使用模型: \(modelName)")
                
                // 状态码为401时，可能是API密钥错误
                if httpResponse.statusCode == 401 {
                    log("可能是API密钥无效，请检查API密钥是否正确")
                }
                
                // 状态码为404时，可能是模型名称错误
                if httpResponse.statusCode == 404 {
                    log("可能是模型名称无效，当前模型: \(modelName)")
                    log("请确认模型名称是否正确，参考文档: https://docs.siliconflow.cn/cn/api-reference/chat-completions/chat-completions")
                }
                
                // 尝试下一个模型
                if tryNextModel() {
                    return try await sendRequest(messages: messages, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            // 确保有数据
            guard !data.isEmpty else {
                log("错误: 未收到数据")
                
                // 尝试下一个模型
                if tryNextModel() {
                    return try await sendRequest(messages: messages, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
                }
                throw APIError.noDataReceived
            }
            
            // 将响应解析为JSON
            guard let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("错误: 无法解析响应为JSON")
                
                // 尝试下一个模型
                if tryNextModel() {
                    return try await sendRequest(messages: messages, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
                }
                throw APIError.invalidResponseFormat
            }
            
            // 提取内容字段
            if let choices = jsonObject["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                log("成功获取响应内容: \(content.prefix(50))...")
                return content
            } else {
                log("错误: 响应格式无效，未找到内容字段")
                
                // 尝试下一个模型
                if tryNextModel() {
                    return try await sendRequest(messages: messages, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
                }
                throw APIError.responseDecodingFailed
            }
        } catch let error as APIError {
            // 已经是API错误，记录并重新抛出
            log("API错误: \(error.localizedDescription)")
            throw error
        } catch {
            // 其他错误（如网络错误）
            log("网络或其他错误: \(error.localizedDescription)")
            
            // 尝试下一个模型
            if tryNextModel() {
                return try await sendRequest(messages: messages, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount + 1)
            }
            throw APIError.apiError(message: error.localizedDescription)
        }
    }
    
    /// 重写基类方法，发送请求到AI服务
    /// - Parameters:
    ///   - messages: 消息列表
    ///   - maxTokens: 最大令牌数
    ///   - temperature: 温度参数
    ///   - retryCount: 重试次数
    /// - Returns: 文本响应
    override func sendRequest(
        messages: [Message],
        maxTokens: Int,
        temperature: Double,
        retryCount: Int = 0
    ) async throws -> String {
        // 将Message对象转换为字典格式
        let messageDicts = messages.map { $0.toDictionary() }
        
        // 调用现有方法处理请求
        return try await sendRequest(messages: messageDicts, maxTokens: maxTokens, temperature: temperature, retryCount: retryCount)
    }
    
    /// 解析目标生成子任务
    /// - Parameters:
    ///   - goal: 目标对象
    ///   - completion: 完成回调，返回子任务列表或错误
    func analyzeGoalForSubtasks(goal: Goal, completion: @escaping (Result<[SubTask], Error>) -> Void) {
        // 构建提示信息
        let prompt = """
        你是一位专业的任务分解专家。请帮我分析以下目标，并将其分解为3-5个具体的子任务。

        目标标题：\(goal.title)
        目标描述：\(goal.goalDescription)

        请为每个子任务提供一个明确的标题和预计完成天数(整数)。
        请以JSON格式返回，格式为：
        [
          {"title": "子任务1标题", "estimatedHours": 24},
          {"title": "子任务2标题", "estimatedHours": 48},
          {"title": "子任务3标题", "estimatedHours": 72}
        ]

        只返回JSON数据，不要有其他文字说明。
        """
        
        // 构建消息数组
        let messageArray = [
            ["role": "user", "content": prompt]
        ]
        
        // 发送请求
        sendRequest(messages: messageArray) { result in
            switch result {
            case .success(let response):
                // 尝试解析响应为JSON
                // 首先尝试直接解析整个响应
                if let data = response.data(using: .utf8),
                   let subtaskData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    var subtasks: [SubTask] = []
                    
                    for (index, subtaskInfo) in subtaskData.enumerated() {
                        guard let title = subtaskInfo["title"] as? String else {
                            continue
                        }
                        
                        let estimatedHours = subtaskInfo["estimatedHours"] as? Int ?? 24
                        let subtask = SubTask(title: title, note: "AI生成的子任务", priority: 0)
                        subtask.goal = goal
                        subtask.estimatedHours = estimatedHours
                        subtasks.append(subtask)
                    }
                    
                    print("✅ 成功从响应中解析出\(subtasks.count)个子任务")
                    completion(.success(subtasks))
                    return
                }
                
                // 如果直接解析失败，尝试从响应中提取JSON部分
                print("🔍 尝试从响应中提取JSON数组")
                if let jsonStart = response.range(of: "["),
                   let jsonEnd = response.range(of: "]", options: .backwards),
                   jsonStart.upperBound <= jsonEnd.lowerBound {
                    let jsonString = response[jsonStart.lowerBound...jsonEnd.upperBound]
                    if let jsonData = String(jsonString).data(using: .utf8),
                       let subtaskData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                        var subtasks: [SubTask] = []
                        
                        for (index, subtaskInfo) in subtaskData.enumerated() {
                            guard let title = subtaskInfo["title"] as? String else {
                                continue
                            }
                            
                            let estimatedHours = subtaskInfo["estimatedHours"] as? Int ?? 24
                            let subtask = SubTask(title: title, note: "AI生成的子任务", priority: 0)
                            subtask.goal = goal
                            subtask.estimatedHours = estimatedHours
                            subtasks.append(subtask)
                        }
                        
                        print("✅ 成功从提取的JSON中解析出\(subtasks.count)个子任务")
                        completion(.success(subtasks))
                        return
                    }
                }
                
                // 如果所有尝试都失败，打印响应并使用默认值
                print("⚠️ 无法解析响应为有效的JSON，响应内容:")
                print(response)
                self.createDefaultSubtasks(for: goal, completion: completion)
                
            case .failure(let error):
                print("API请求失败: \(error.localizedDescription)")
                // 如果API请求失败，创建默认子任务
                self.createDefaultSubtasks(for: goal, completion: completion)
            }
        }
    }
    
    /// 评估目标完成情况
    /// - Parameters:
    ///   - goal: 目标对象
    ///   - completion: 完成回调，返回评分和评语
    func evaluateGoalCompletion(goal: Goal, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        // 收集子任务完成情况
        let totalSubtasks = goal.subTasks.count
        let completedSubtasks = goal.subTasks.filter { $0.isCompleted }.count
        let overdueSubtasks = goal.subTasks.filter { $0.isOverdue }.count
        
        // 构建子任务完成情况的描述
        var subtasksDescription = ""
        for (index, subtask) in goal.subTasks.enumerated() {
            subtasksDescription += "子任务\(index+1): \(subtask.title)\n"
            subtasksDescription += "状态: \(subtask.isCompleted ? "已完成" : (subtask.isOverdue ? "未按时完成" : "未完成"))\n"
            
            if let completionDate = subtask.completionDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                subtasksDescription += "完成时间: \(formatter.string(from: completionDate))\n"
            }
            
            subtasksDescription += "\n"
        }
        
        // 构建提示信息
        let prompt = """
        你是一位专业的目标评估专家。请评估以下目标的完成情况，给出评分(0-100)和评语。

        目标标题：\(goal.title)
        目标描述：\(goal.goalDescription)

        子任务完成情况：
        \(subtasksDescription)

        统计信息：
        - 总子任务数：\(totalSubtasks)
        - 已完成子任务数：\(completedSubtasks)
        - 未按时完成子任务数：\(overdueSubtasks)

        请根据完成度、及时性和质量给出评分，并提供具体的评语，评语应包括总体评价、做得好的方面和需要改进的建议。

        请以JSON格式返回：
        {"score": 80, "comment": "你的评语内容"}

        只返回JSON数据，不要有其他文字说明。
        """
        
        // 构建消息数组
        let messageArray = [
            ["role": "user", "content": prompt]
        ]
        
        // 发送请求
        sendRequest(messages: messageArray) { result in
            switch result {
            case .success(let response):
                // 尝试解析响应为JSON
                // 首先尝试直接解析整个响应
                if let data = response.data(using: .utf8),
                   let evaluationData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let score = evaluationData["score"] as? Int,
                   let comment = evaluationData["comment"] as? String {
                    print("✅ 成功从响应中解析出评分: \(score)")
                    completion(.success((score, comment)))
                    return
                }
                
                // 如果直接解析失败，尝试从响应中提取JSON部分
                print("🔍 尝试从响应中提取JSON对象")
                if let jsonStart = response.range(of: "{"),
                   let jsonEnd = response.range(of: "}", options: .backwards),
                   jsonStart.upperBound <= jsonEnd.lowerBound {
                    let jsonString = response[jsonStart.lowerBound...jsonEnd.upperBound]
                    if let jsonData = String(jsonString).data(using: .utf8),
                       let evaluationData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let score = evaluationData["score"] as? Int,
                       let comment = evaluationData["comment"] as? String {
                        print("✅ 成功从提取的JSON中解析出评分: \(score)")
                        completion(.success((score, comment)))
                        return
                    }
                }
                
                // 尝试从响应文本中用正则表达式提取评分和评语
                print("🔍 尝试用正则表达式从响应中提取评分和评语")
                if let scorePattern = try? NSRegularExpression(pattern: "score\"?:\\s*(\\d+)", options: []),
                   let scoreMatch = scorePattern.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
                   let scoreRange = Range(scoreMatch.range(at: 1), in: response),
                   let score = Int(response[scoreRange]),
                   let commentPattern = try? NSRegularExpression(pattern: "comment\"?:\\s*\"([^\"]*)\"", options: []),
                   let commentMatch = commentPattern.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
                   let commentRange = Range(commentMatch.range(at: 1), in: response) {
                    let comment = String(response[commentRange])
                    print("✅ 成功使用正则表达式提取出评分: \(score)")
                    completion(.success((score, comment)))
                    return
                }
                
                // 如果所有尝试都失败，打印响应并使用默认值
                print("⚠️ 无法解析响应为有效的JSON，响应内容:")
                print(response)
                self.createDefaultEvaluation(for: goal, completion: completion)
                
            case .failure(let error):
                print("API请求失败: \(error.localizedDescription)")
                // 如果API请求失败，返回默认评分和评语
                self.createDefaultEvaluation(for: goal, completion: completion)
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 创建默认子任务
    private func createDefaultSubtasks(for goal: Goal, completion: @escaping (Result<[SubTask], Error>) -> Void) {
        var subtasks: [SubTask] = []
        
        // 创建基本子任务
        let taskTitles = [
            "规划和设计 - 明确需求并制定详细计划",
            "环境搭建 - 准备开发环境和所需工具",
            "基础功能开发 - 实现核心功能模块",
            "UI优化和测试 - 完善界面和用户体验",
            "发布准备 - 最终测试和部署"
        ]
        
        // 根据目标标题长度选择3-5个子任务
        let taskCount = min(5, max(3, goal.title.count / 10))
        
        for i in 0..<taskCount {
            let subtask = SubTask(title: taskTitles[i], note: "系统生成的默认子任务", priority: 0)
            subtask.goal = goal
            subtasks.append(subtask)
        }
        
        completion(.success(subtasks))
    }
    
    /// 创建默认评估结果
    private func createDefaultEvaluation(for goal: Goal, completion: @escaping (Result<(Int, String), Error>) -> Void) {
        // 基于子任务完成情况计算得分
        let completionRate = Double(goal.completedSubTasksCount) / Double(max(1, goal.subTasks.count))
        let score = min(100, max(60, Int(completionRate * 100)))
        
        // 根据得分生成评语
        let comment: String
        if score >= 90 {
            comment = "您的目标完成度极高，超出预期。时间管理出色，各子任务都按计划或提前完成，成果质量优秀。"
        } else if score >= 80 {
            comment = "整体完成情况良好，大部分子任务按时完成，成果质量符合预期。时间管理有效但仍有优化空间。"
        } else if score >= 70 {
            comment = "目标基本完成，但部分子任务存在延迟或质量不足的情况。建议加强时间管理和任务优先级规划。"
        } else {
            comment = "目标完成度不足，多数子任务未能按时完成。建议重新审视目标设定的合理性，并改进执行方法。"
        }
        
        completion(.success((score, comment)))
    }
    
    /// 格式化请求体为简洁的日志文本
    /// - Parameter requestBody: 原始请求体
    /// - Returns: 格式化后的文本
    private func formatRequestBody(_ requestBody: [String: Any]) -> String {
        var result = "{\n"
        
        // 添加模型信息
        if let model = requestBody["model"] as? String {
            result += "  \"model\": \"\(model)\",\n"
        }
        
        // 添加temperature
        if let temperature = requestBody["temperature"] as? Double {
            result += "  \"temperature\": \(temperature),\n"
        }
        
        // 添加max_tokens
        if let maxTokens = requestBody["max_tokens"] as? Int {
            result += "  \"max_tokens\": \(maxTokens),\n"
        }
        
        // 处理消息数组
        if let messages = requestBody["messages"] as? [[String: Any]] {
            result += "  \"messages\": [\n"
            
            for (index, message) in messages.enumerated() {
                result += "    {\n"
                
                // 添加角色
                if let role = message["role"] as? String {
                    result += "      \"role\": \"\(role)\",\n"
                }
                
                // 处理内容
                if let content = message["content"] as? String {
                    // 文本内容，截断过长的文本
                    let truncatedContent = content.count > 50 ? content.prefix(50) + "..." : content
                    result += "      \"content\": \"\(truncatedContent)\"\n"
                } else if let content = message["content"] as? [[String: Any]] {
                    // 多模态内容
                    result += "      \"content\": [\n"
                    
                    for (contentIndex, item) in content.enumerated() {
                        result += "        {"
                        
                        if let type = item["type"] as? String {
                            result += "\"type\": \"\(type)\""
                            
                            // 如果是图片类型，添加简化的提示
                            if type == "image_url" {
                                result += ", \"image_url\": {\"url\": \"[图片数据已省略]\"}"
                            }
                        }
                        
                        result += "}"
                        if contentIndex < content.count - 1 {
                            result += ","
                        }
                        result += "\n"
                    }
                    
                    result += "      ]\n"
                } else {
                    result += "      \"content\": null\n"
                }
                
                result += "    }"
                if index < messages.count - 1 {
                    result += ","
                }
                result += "\n"
            }
            
            result += "  ]\n"
        }
        
        result += "}"
        return result
    }
}

/// API错误类型
enum APIError: Error, LocalizedError {
    case invalidURL
    case requestEncodingFailed
    case responseDecodingFailed
    case noDataReceived
    case invalidResponseFormat
    case apiError(message: String)
    case httpError(statusCode: Int, message: String)
    case allModelsFailedError
    
    /// 本地化错误描述
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case .requestEncodingFailed:
            return "请求编码失败"
        case .responseDecodingFailed:
            return "响应解码失败"
        case .noDataReceived:
            return "未收到数据"
        case .invalidResponseFormat:
            return "无法解析响应为有效的JSON"
        case .apiError(let message):
            return "API错误: \(message)"
        case .httpError(let statusCode, let message):
            return "HTTP错误(\(statusCode)): \(message)"
        case .allModelsFailedError:
            return "所有模型都尝试失败"
        }
    }
} 