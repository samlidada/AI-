import Foundation
import SwiftData
import UIKit

/// 目标分析服务
class AIGoalAnalysisService {
    static let shared = AIGoalAnalysisService()
    
    // 存储为每个目标生成的所有方案(最多3种)
    private var generatedPlans: [UUID: [[SubTask]]] = [:]
    
    // 记录当前显示的方案索引
    private var currentPlanIndex: [UUID: Int] = [:]
    
    // 记录API请求失败的尝试次数
    private var apiFailureAttempts: [UUID: Int] = [:]
    
    // 最大允许刷新尝试次数
    private let maxRefreshAttempts = 3
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 清除指定目标的方案缓存
    /// - Parameter goal: 目标对象或目标ID
    func clearPlanCache(for goal: Goal) {
        let goalId = goal.id
        print("🧹 清除目标方案缓存: \(goal.title)")
        generatedPlans.removeValue(forKey: goalId)
        currentPlanIndex.removeValue(forKey: goalId)
        apiFailureAttempts.removeValue(forKey: goalId) // 重置失败尝试计数
    }
    
    /// 清除指定目标的方案缓存
    /// - Parameter goalId: 目标ID
    func clearPlanCache(forGoalId goalId: UUID) {
        print("🧹 清除目标方案缓存，ID: \(goalId)")
        generatedPlans.removeValue(forKey: goalId)
        currentPlanIndex.removeValue(forKey: goalId)
        apiFailureAttempts.removeValue(forKey: goalId) // 重置失败尝试计数
    }
    
    /// 分析目标并生成子任务
    /// - Parameters:
    ///   - goal: 目标对象
    ///   - completion: 完成回调，返回子任务列表
    func analyzeGoal(_ goal: Goal, completion: @escaping ([SubTask]) -> Void) {
        print("🔍 开始AI分析目标: \(goal.title)")
        
        // 在主线程上获取必要信息
        let goalId = goal.id
        let goalTitle = goal.title
        let goalDescription = goal.goalDescription
        
        // 只在没有现有方案时初始化
        if generatedPlans[goalId] == nil {
            print("📝 初始化目标方案列表")
            generatedPlans[goalId] = []
            currentPlanIndex[goalId] = 0
        } else {
            print("📝 目标已有\(generatedPlans[goalId]?.count ?? 0)个方案，将添加新方案")
        }
        
        // 使用Task.detached隔离SwiftData上下文
        Task.detached { @Sendable in
            do {
                // 明确设置API服务为纯文本模式，提高响应速度
                await MainActor.run {
                    ServicesManager.shared.siliconFlowAPIService.setRequestMode(.textOnly)
                    print("📝 已设置为纯文本模式进行目标分析，提高响应速度")
                }
                
                let subtasks = try await self.analyzeGoalAsync(goal)
                
                // 在主线程上保存方案
                await MainActor.run {
                    print("✅ 目标分析成功，生成\(subtasks.count)个子任务")
                    
                    // 将新方案添加到列表
                    if var plans = self.generatedPlans[goalId] {
                        plans.append(subtasks)
                        self.generatedPlans[goalId] = plans
                        self.currentPlanIndex[goalId] = plans.count - 1
                        print("✅ 将新方案添加到现有方案列表，当前有\(plans.count)个方案，当前索引: \(plans.count - 1)")
                    } else {
                        self.generatedPlans[goalId] = [subtasks]
                        self.currentPlanIndex[goalId] = 0
                        print("✅ 创建新的方案列表，当前索引: 0")
                    }
                    
                    self.apiFailureAttempts[goalId] = 0 // 重置失败计数
                    completion(subtasks)
                }
            } catch {
                print("❌ 目标分析出错: \(error.localizedDescription)")
                
                // 在主线程上返回空数组和显示错误信息
                await MainActor.run {
                    // 初始化或增加失败计数
                    let currentFailures = self.apiFailureAttempts[goalId] ?? 0
                    self.apiFailureAttempts[goalId] = currentFailures + 1
                    
                    // 返回空数组，由调用方显示错误信息
                    completion([])
                }
            }
        }
    }
    
    /// 刷新生成新的子任务方案
    /// - Parameters:
    ///   - goal: 目标对象
    ///   - completion: 完成回调，返回子任务列表
    func refreshAnalysis(_ goal: Goal, completion: @escaping ([SubTask]) -> Void) {
        print("🔄 刷新AI分析目标: \(goal.title)")
        
        // 在主线程上获取当前方案信息
        let goalId = goal.id
        
        Task { @MainActor in
            // 获取当前已生成的方案数量
            let planCount = generatedPlans[goalId]?.count ?? 0
            
            print("📊 当前目标已有\(planCount)个方案")
            
            // 检查是否已经有方案并且数量达到最大值(3个)，有则循环显示现有方案
            if planCount >= 3 {
                // 更新当前方案索引
                let nextIndex = ((currentPlanIndex[goalId] ?? 0) + 1) % planCount
                currentPlanIndex[goalId] = nextIndex
                
                // 获取下一个方案
                if let nextPlan = generatedPlans[goalId]?[nextIndex] {
                    print("🔄 切换到方案 \(nextIndex + 1)/\(planCount)")
                    completion(nextPlan)
                    return
                }
            } else if planCount > 0 {
                // 如果已有方案但未达到最大值，则生成新方案
                print("📝 已有\(planCount)个方案，未达到最大值，将生成新方案")
            } else {
                // 如果没有方案，则生成第一个方案
                print("📝 没有现有方案，将生成第一个方案")
            }
            
            // 从Goal对象中提取必要信息，避免在异步任务中直接访问SwiftData模型
            let goalTitle = goal.title
            let goalDescription = goal.goalDescription
            
            // 检查失败尝试次数
            let currentFailures = self.apiFailureAttempts[goalId] ?? 0
            
            // 如果已经尝试了最大次数，则直接返回空数组
            if currentFailures >= self.maxRefreshAttempts {
                // 返回空数组，由调用方展示"请稍后再试"信息
                print("⚠️ 已达到最大尝试次数\(currentFailures)/\(self.maxRefreshAttempts)，不再尝试")
                completion([])
                return
            }
            
            // 尝试生成新方案
            Task.detached { @Sendable in
                do {
                    // 明确设置API服务为纯文本模式，提高响应速度
                    await MainActor.run {
                        ServicesManager.shared.siliconFlowAPIService.setRequestMode(.textOnly)
                        print("📝 已设置为纯文本模式进行目标刷新分析，提高响应速度")
                    }
                    
                    let subtasks = try await self.analyzeGoalAsync(goal, isRefresh: true)
                    
                    await MainActor.run {
                        // 将新方案添加到列表
                        if var plans = self.generatedPlans[goalId] {
                            plans.append(subtasks)
                            self.generatedPlans[goalId] = plans
                            self.currentPlanIndex[goalId] = plans.count - 1
                            print("✅ 将新方案添加到现有方案列表，当前索引: \(plans.count - 1)")
                        } else {
                            self.generatedPlans[goalId] = [subtasks]
                            self.currentPlanIndex[goalId] = 0
                            print("✅ 创建新的方案列表，当前索引: 0")
                        }
                        
                        // 重置失败计数
                        self.apiFailureAttempts[goalId] = 0
                        
                        let currentCount = self.generatedPlans[goalId]?.count ?? 1
                        print("✅ 目标刷新分析成功，生成方案 \(currentCount)/3，包含\(subtasks.count)个子任务")
                        completion(subtasks)
                    }
                } catch {
                    print("❌ 刷新目标分析出错: \(error.localizedDescription)")
                    
                    await MainActor.run {
                        // 增加失败计数
                        self.apiFailureAttempts[goalId] = currentFailures + 1
                        
                        // 返回空数组，由调用方显示错误信息
                        completion([])
                    }
                }
            }
        }
    }
    
    /// 评估目标完成情况
    /// - Parameters:
    ///   - goal: 目标对象
    ///   - completion: 完成回调，返回评语
    func evaluateGoal(_ goal: Goal, completion: @escaping (String) -> Void) {
        print("🔍 开始AI评估目标: \(goal.title) (ID: \(goal.id))")
        
        // 复制目标对象的必要信息，避免在异步任务中直接访问SwiftData模型
        let goalId = goal.id
        let goalTitle = goal.title
        
        Task.detached { @Sendable in
            do {
                // 明确设置API服务为多模态模式，确保使用支持图片的模型
                await MainActor.run {
                    ServicesManager.shared.siliconFlowAPIService.setRequestMode(.multimodal)
                    print("📝 已设置为多模态模式进行评估，确保使用支持图片的模型")
                }
                
                print("⏳ 开始异步评估目标: \(goalTitle)")
                let startTime = Date()
                let comment = try await self.evaluateGoalAsync(goal)
                let totalTime = Date().timeIntervalSince(startTime)
                print("✅ 目标评估成功完成，总耗时: \(String(format: "%.2f", totalTime))秒")
                
                await MainActor.run {
                    print("✅ 目标评估成功，评语长度: \(comment.count)字符")
                    // 重置失败计数
                    self.apiFailureAttempts[goalId] = 0
                    completion(comment)
                }
            } catch {
                print("❌ 目标评估出错: \(error.localizedDescription)")
                // 如果API调用失败，返回简单错误信息
                await MainActor.run {
                    // 增加失败计数
                    let currentFailures = self.apiFailureAttempts[goalId] ?? 0
                    self.apiFailureAttempts[goalId] = currentFailures + 1
                    print("⚠️ 失败计数已增加到 \(currentFailures + 1)/\(self.maxRefreshAttempts)")
                    
                    // 尝试生成本地评估
                    if currentFailures + 1 >= self.maxRefreshAttempts {
                        print("🔄 尝试生成本地评估结果作为备选方案")
                        Task {
                            do {
                                let localComment = await self.generateLocalEvaluationAsync(goal)
                                print("✅ 本地评估生成成功，长度: \(localComment.count)字符")
                                completion(localComment)
                            } catch {
                                print("❌ 本地评估生成失败: \(error.localizedDescription)")
                                completion("服务器无响应，请刷新。")
                            }
                        }
                    } else {
                        print("⚠️ 返回服务器无响应消息")
                        completion("服务器无响应，请刷新。")
                    }
                }
            }
        }
    }

    // 检查目标是否达到最大刷新尝试次数
    func hasReachedMaxAttempts(for goal: Goal) -> Bool {
        let attempts = apiFailureAttempts[goal.id] ?? 0
        return attempts >= maxRefreshAttempts
    }
    
    // 获取目标当前的失败尝试次数
    func getFailureAttempts(for goal: Goal) -> Int {
        return apiFailureAttempts[goal.id] ?? 0
    }
    
    // 获取当前方案索引，从0开始计数
    func getCurrentPlanIndex(for goalId: UUID) -> Int {
        return currentPlanIndex[goalId] ?? 0
    }
    
    // 获取目标的总方案数
    func getTotalPlansCount(for goalId: UUID) -> Int {
        return generatedPlans[goalId]?.count ?? 0
    }
    
    // MARK: - 异步实现方法
    
    /// 异步分析目标
    /// - Parameters:
    ///   - goal: 目标对象
    ///   - isRefresh: 是否为刷新请求
    /// - Returns: 子任务列表
    private func analyzeGoalAsync(_ goal: Goal, isRefresh: Bool = false) async throws -> [SubTask] {
        // 从Goal对象中提取必要信息，避免在异步任务中直接访问SwiftData模型
        let goalTitle = goal.title
        let goalDescription = goal.goalDescription
        let goalId = goal.id
        
        // 构建提示信息
        let prompt = """
        你是一位专业的任务分解专家。请帮我深入分析以下目标，并将其分解为多个具体的子任务。
        
        目标标题：\(goalTitle)
        目标描述：\(goalDescription)
        
        要求：
        1. 请尽可能细致地分解目标，不要限制子任务数量，根据目标复杂度合理拆分
        2. 拆分的子任务应该具体、可操作、结果可验证
        3. 关注目标的完整实现路径，确保所有关键步骤都被包含
        4. 考虑可能的依赖关系，按合理顺序排列子任务
        \(isRefresh ? "5. 请提供与之前不同的拆分视角或方法" : "")
        
        请为每个子任务提供一个明确的标题和预计完成小时数(整数)。
        请以JSON格式返回，格式为：
        [
          {"title": "子任务1标题", "estimatedHours": 24},
          {"title": "子任务2标题", "estimatedHours": 48},
          {"title": "子任务3标题", "estimatedHours": 72}
          // 更多子任务...
        ]

        只返回JSON数据，不要有其他文字说明。
        """
        
        // 构建消息
        let messages = [Message(role: "user", content: prompt)]
        
        // 获取服务
        let apiService = ServicesManager.shared.siliconFlowAPIService
        
        // 发送请求
        let response = try await apiService.sendRequest(
            messages: messages,
            maxTokens: 1024, 
            temperature: isRefresh ? 0.8 : 0.7  // 刷新时增加随机性
        )
        
        // 获取解析后的子任务数据（标题和天数），而不是直接创建SwiftData模型
        let subtaskInfos = try parseSubtaskInfos(from: response)
        
        // 在主线程上创建和返回SubTask模型对象
        return await MainActor.run {
            var subtasks: [SubTask] = []
            for (index, info) in subtaskInfos.enumerated() {
                let subtask = SubTask(title: info.title, note: "AI生成的子任务", priority: 0)
                subtask.estimatedHours = info.estimatedHours
                subtask.goal = goal
                subtasks.append(subtask)
            }
            return subtasks
        }
    }
    
    /// 异步评估目标
    /// - Parameter goal: 目标对象
    /// - Returns: 评语
    private func evaluateGoalAsync(_ goal: Goal) async throws -> String {
        // 从Goal对象中提取必要信息，避免在异步任务中直接访问SwiftData模型
        let goalTitle = goal.title
        let goalDescription = goal.goalDescription
        
        // 使用MainActor安全地收集子任务信息和完成证明
        let (subtasksInfo, proofInfos) = await MainActor.run {
            let totalSubtasks = goal.subTasks.count
            let completedSubtasks = goal.subTasks.filter { $0.isCompleted }.count
            let overdueSubtasks = goal.subTasks.filter { $0.isOverdue }.count
            
            // 构建子任务完成情况的描述
            var subtasksDescription = ""
            
            // 收集所有成果证明
            var allProofs: [(subTaskTitle: String, description: String?, images: [Data])] = []
            
            for (index, subtask) in goal.subTasks.enumerated() {
                subtasksDescription += "子任务\(index+1): \(subtask.title)\n"
                subtasksDescription += "状态: \(subtask.isCompleted ? "已完成" : (subtask.isOverdue ? "未按时完成" : "未完成"))\n"
                
                if let completionDate = subtask.completionDate {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    subtasksDescription += "完成时间: \(formatter.string(from: completionDate))\n"
                }
                
                // 收集完成证明
                if subtask.isCompleted, let proof = subtask.completionProof {
                    // 限制每个子任务只使用最多1张图片作为证明
                    let limitedImages = proof.allImagesData.prefix(1).map { $0 }
                    
                    allProofs.append((
                        subTaskTitle: subtask.title,
                        description: proof.proofDescription,
                        images: limitedImages
                    ))
                    
                    // 在描述中添加成果证明信息
                    if let proofDesc = proof.proofDescription, !proofDesc.isEmpty {
                        subtasksDescription += "成果描述: \(proofDesc)\n"
                    }
                    subtasksDescription += "提交了\(proof.allImagesData.count)张图片作为证明\n"
                }
                
                subtasksDescription += "\n"
            }
            
            return ((totalSubtasks, completedSubtasks, overdueSubtasks, subtasksDescription), allProofs)
        }
        
        // 解构数据
        let (totalSubtasks, completedSubtasks, overdueSubtasks, subtasksDescription) = subtasksInfo
        
        // 创建API请求
        var allMessages: [Message] = []
        
        // 1. 首先添加文本描述的消息
        let textPrompt = """
        你是一位专业的目标评估专家。请评估以下目标的完成情况，给出评语。

        目标标题：\(goalTitle)
        目标描述：\(goalDescription)

        子任务完成情况：
        \(subtasksDescription)

        统计信息：
        - 总子任务数：\(totalSubtasks)
        - 已完成子任务数：\(completedSubtasks)
        - 未按时完成子任务数：\(overdueSubtasks)
        """
        
        // 添加成果证明信息
        let proofText: String
        if !proofInfos.isEmpty {
            var proofDetails = "\n\n用户提交的成果证明信息:\n"
            for (index, proof) in proofInfos.enumerated() {
                proofDetails += "子任务: \(proof.subTaskTitle)\n"
                if proof.description != nil && !proof.description!.isEmpty {
                    proofDetails += "成果描述: \(proof.description!)\n"
                }
                proofDetails += "提交的图片数量: \(proof.images.count)\n\n"
            }
            proofText = proofDetails
        } else {
            proofText = "\n\n注意: 用户未提交任何成果证明材料。"
        }
        
        let finalPrompt = textPrompt + proofText + """

        评估要求：
        1. 内容相关性评估 (权重20%)
           - 仔细分析每个子任务的成果描述和证明是否与原定目标相关
           - 简要判断提交的证明材料是否能反映任务完成情况
           - 适度评估成果的质量和完整性，但不要过度解读图片内容

        2. 目标达成度评估
           - 对比原定目标和最终成果
           - 评估是否真正实现了目标的核心价值
           - 分析是否存在形式完成但实质未达标的情况

        3. 时间管理评估
           - 分析任务完成的时间节奏
           - 评估时间利用的合理性
           - 考虑完成质量与时间投入的平衡

        4. 个人习惯养成指导 (权重30%)
           - 深入分析用户在目标执行过程中展现的习惯模式
           - 提出形成良好习惯的具体、可操作的建议和方法
           - 详细推荐科学的习惯养成策略（如"小习惯大改变"、"触发-行为-奖励"循环等）
           - 建议可以配合使用的工具和方法来巩固好习惯
           - 分析培养这些习惯如何帮助用户在其他领域取得成功
           - 提供习惯追踪和维持的方法论

        5. 创新思路与方法推荐 (权重25%)
           - 对于目标中可能存在的创新点进行深入分析
           - 详细推荐与目标相关的创新方法和思维模式
           - 分享类似目标中的创新实践案例
           - 提供打破思维定式的具体策略
           - 分析用户的创造性思维如何助力目标达成
           - 探讨跨领域思维对目标达成的促进作用
           - 提供系统性创新思考的框架和方法

        6. 社会趋势结合与前景展望 (权重25%)
           - 深入分析目标在当下社会发展趋势中的位置
           - 详细探讨目标在未来的潜在价值和发展方向
           - 提供与时代主题（如数字化、可持续发展、健康生活等）结合的详细建议
           - 预判相关领域的未来变化趋势，给出前瞻性建议
           - 分析目标完成后可能产生的社会影响
           - 探讨目标与当前社会趋势的契合度及未来发展空间
           - 提供将个人成果与社会需求结合的建议

        7. 个性化建议与改进方向
           - 针对目标完成情况提供具体、可操作的改进建议
           - 对于表现优秀的方面给予肯定并提供进一步发展方向
           - 对于不足之处提供具体的优化策略和资源推荐
           - 根据完成度不同提供差异化建议：
             * 对于高完成度：提供如何将成果扩展或应用到其他领域的建议
             * 对于中等完成度：提供如何弥补关键短板的具体方法
             * 对于低完成度：提供如何重新规划和分解目标的建议，以及时间管理技巧

        即使用户未按预期完成目标，仍然要给予鼓励性的总结和建设性的建议，态度应该像一位亦师亦友的知己，既诚恳指出问题，也真诚鼓励和肯定。

        请特别注意：
        - 对图片内容的解读不要占据评估的主要部分，只需进行简要的关联性判断
        - 将重点放在个人习惯养成、创新方法和社会前景的深入分析上
        - 评价应体现出对用户的理解和尊重，语气温暖而不居高临下
        - 提供的建议必须具体、可行，避免空泛的表达
        - 无论目标完成情况如何，都要提供全面的反馈，不能因为某方面较差就忽略其他方面的评估
        - 建议中要体现出对用户个人成长的关注，而不仅仅是任务本身

        请使用以下JSON格式返回结果（不要返回任何其他内容）：
        {
            "comment": "这里是你的总体评语，应包含对目标完成情况的全面分析",
            "strengths": "这里列出用户完成目标过程中的优点和亮点",
            "areas_for_improvement": "这里列出需要改进的地方，语气应该建设性而非批评",
            "habit_formation": "这里给出关于个人习惯养成的详细分析和建议",
            "innovation_insights": "这里提供创新的思路和方法建议",
            "social_trend_analysis": "这里分析目标在当前社会趋势中的位置和价值",
            "personalized_suggestions": "这里提供全面的个性化建议，应当切实可行且有启发性"
        }

        只返回JSON格式数据，不要有任何解释性文字。
        """
        
        // 添加第一条文本消息
        allMessages.append(Message(role: "user", content: finalPrompt))
        
        // 2. 如果有图片证明，为每个图片添加两条消息（一条文本描述，一条图片内容）
        // 限制图片总数不超过2张
        var processedImageCount = 0
        let maxImages = 2
        
        for proof in proofInfos {
            for imageData in proof.images {
                if processedImageCount < maxImages {
                    // 压缩图片到更小的尺寸
                    let compressedImageData = compressImage(imageData, maxSize: 200_000) // 降低到200KB以下
                    let base64String = compressedImageData.base64EncodedString()
                    
                    // 添加图片描述消息
                    allMessages.append(Message(role: "user", content: "这是子任务「\(proof.subTaskTitle)」的完成证明图片"))
                    
                    // 添加图片内容消息
                    let imageContent: [[String: Any]] = [
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64String)"
                            ]
                        ]
                    ]
                    allMessages.append(Message(role: "user", content: imageContent))
                    
                    processedImageCount += 1
                } else {
                    // 达到最大图片数量，跳出循环
                    break
                }
            }
            
            if processedImageCount >= maxImages {
                break
            }
        }
        
        // 最后添加一条请求生成JSON评估的消息
        allMessages.append(Message(role: "user", content: """
请务必根据以上信息，以完整的JSON格式返回全面评估结果，必须包含以下所有字段：
{
    "comment": "总体评语",
    "strengths": "优点和亮点",
    "areas_for_improvement": "需要改进的地方",
    "habit_formation": "个人习惯养成分析和建议",
    "innovation_insights": "创新思路和方法建议",
    "social_trend_analysis": "目标在社会趋势中的位置和价值",
    "personalized_suggestions": "个性化建议"
}
请确保每个字段都有内容，不要遗漏任何字段，只返回JSON格式数据，不要有任何解释性文字。
"""))
        
        // 获取服务
        let apiService = ServicesManager.shared.siliconFlowAPIService
        
        // 打印消息数量和请求详情
        print("📤 发送评估请求，包含\(allMessages.count)条消息，其中图片\(processedImageCount)张")
        print("📝 最后一条消息: \(allMessages.last?.content ?? "无内容")")
        print("📊 请求参数: maxTokens=1024, temperature=0.7")
        
        // 发送请求
        do {
            print("⏳ 开始发送API请求...")
            let startTime = Date()
            let response = try await apiService.sendRequest(
                messages: allMessages,
                maxTokens: 1024,
                temperature: 0.7
            )
            let requestTime = Date().timeIntervalSince(startTime)
            print("✅ API请求成功，耗时: \(String(format: "%.2f", requestTime))秒")
            
            // 记录响应长度
            print("📏 API响应长度: \(response.count)字符")
            
            // 解析响应，获取评语
            print("🔍 开始解析评估响应...")
            let parseStartTime = Date()
            let comment = try parseComment(from: response)
            let parseTime = Date().timeIntervalSince(parseStartTime)
            print("✅ 解析评估响应成功，耗时: \(String(format: "%.2f", parseTime))秒")
            print("📏 解析后评语长度: \(comment.count)字符")
            
            // 添加声明文字
            let finalComment = comment + "\n\n此评语由 AI 生成，仅供参考。"
            
            return finalComment
        } catch {
            print("❌ API请求或解析过程中出错: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - 解析子任务信息而不创建SwiftData模型
    
    /// 解析子任务信息而不创建SwiftData模型
    /// - Parameter response: API响应
    /// - Returns: 子任务信息列表
    private func parseSubtaskInfos(from response: String) throws -> [(title: String, estimatedHours: Int)] {
        // 预处理响应文本
        let cleanedResponse = preprocessResponse(response)
        print("🔍 对响应进行预处理")
        
        // 策略1: 尝试直接解析整个响应
        if let data = cleanedResponse.data(using: .utf8),
           let subtaskData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var subtaskInfos: [(title: String, estimatedHours: Int)] = []
            
            for subtaskInfo in subtaskData {
                guard let title = subtaskInfo["title"] as? String else {
                    continue
                }
                
                let estimatedHours = subtaskInfo["estimatedHours"] as? Int ?? 24
                subtaskInfos.append((title: title, estimatedHours: estimatedHours))
            }
            
            if !subtaskInfos.isEmpty {
                print("✅ 成功通过直接解析获取子任务")
                return subtaskInfos
            }
        }
        
        // 策略2: 尝试提取JSON数组部分
        if let jsonStart = cleanedResponse.range(of: "["),
           let jsonEnd = cleanedResponse.range(of: "]", options: .backwards),
           jsonStart.upperBound <= jsonEnd.lowerBound {
            let jsonString = cleanedResponse[jsonStart.lowerBound...jsonEnd.upperBound]
            
            // 尝试解析提取的JSON
            if let jsonData = String(jsonString).data(using: .utf8),
               let subtaskData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                var subtaskInfos: [(title: String, estimatedHours: Int)] = []
                
                for subtaskInfo in subtaskData {
                    guard let title = subtaskInfo["title"] as? String else {
                        continue
                    }
                    
                    let estimatedHours = subtaskInfo["estimatedHours"] as? Int ?? 24
                    subtaskInfos.append((title: title, estimatedHours: estimatedHours))
                }
                
                if !subtaskInfos.isEmpty {
                    print("✅ 成功通过提取JSON数组获取子任务")
                    return subtaskInfos
                }
            }
        }
        
        // 策略3: 使用正则表达式提取JSON对象
        let pattern = "\\{\\s*\"title\"\\s*:\\s*\"([^\"]*)\"\\s*,\\s*\"estimatedHours\"\\s*:\\s*(\\d+)\\s*\\}"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            throw NSError(domain: "AIGoalAnalysisService", code: 100, userInfo: [NSLocalizedDescriptionKey: "无法创建正则表达式"])
        }
        
        let matches = regex.matches(in: cleanedResponse, options: [], range: NSRange(cleanedResponse.startIndex..., in: cleanedResponse))
        
        if !matches.isEmpty {
            var subtaskInfos: [(title: String, estimatedHours: Int)] = []
            
            for match in matches {
                guard let titleRange = Range(match.range(at: 1), in: cleanedResponse),
                      let hoursRange = Range(match.range(at: 2), in: cleanedResponse),
                      let estimatedHours = Int(cleanedResponse[hoursRange]) else {
                    continue
                }
                
                let title = String(cleanedResponse[titleRange])
                subtaskInfos.append((
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines), 
                    estimatedHours: estimatedHours
                ))
            }
            
            if !subtaskInfos.isEmpty {
                print("✅ 成功通过正则表达式获取子任务")
                return subtaskInfos
            }
        }
        
        // 策略4: 更宽松地解析每个任务项
        let titlePattern = "(?:\"title\"\\s*:\\s*\"([^\"]*)\")|(?:标题[：:]\\s*\"?([^\"\\n,}]*)\"?)"
        let hoursPattern = "(?:\"estimatedHours\"\\s*:\\s*(\\d+))|(?:小时[：:]\\s*(\\d+))"
        
        guard let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: []),
              let hoursRegex = try? NSRegularExpression(pattern: hoursPattern, options: []) else {
            throw NSError(domain: "AIGoalAnalysisService", code: 100, userInfo: [NSLocalizedDescriptionKey: "无法创建正则表达式"])
        }
        
        let titleMatches = titleRegex.matches(in: cleanedResponse, options: [], range: NSRange(cleanedResponse.startIndex..., in: cleanedResponse))
        let hoursMatches = hoursRegex.matches(in: cleanedResponse, options: [], range: NSRange(cleanedResponse.startIndex..., in: cleanedResponse))
        
        if titleMatches.count > 0 {
            var subtaskInfos: [(title: String, estimatedHours: Int)] = []
            
            for (index, titleMatch) in titleMatches.enumerated() {
                // 提取标题
                var title = ""
                if let titleRange1 = Range(titleMatch.range(at: 1), in: cleanedResponse), !cleanedResponse[titleRange1].isEmpty {
                    title = String(cleanedResponse[titleRange1])
                } else if let titleRange2 = Range(titleMatch.range(at: 2), in: cleanedResponse), !cleanedResponse[titleRange2].isEmpty {
                    title = String(cleanedResponse[titleRange2])
                } else {
                    continue
                }
                
                // 提取小时数
                var estimatedHours = 24 // 默认值
                if index < hoursMatches.count {
                    let hoursMatch = hoursMatches[index]
                    if let hoursRange1 = Range(hoursMatch.range(at: 1), in: cleanedResponse), !cleanedResponse[hoursRange1].isEmpty,
                       let hours = Int(cleanedResponse[hoursRange1]) {
                        estimatedHours = hours
                    } else if let hoursRange2 = Range(hoursMatch.range(at: 2), in: cleanedResponse), !cleanedResponse[hoursRange2].isEmpty,
                              let hours = Int(cleanedResponse[hoursRange2]) {
                        estimatedHours = hours
                    }
                }
                
                subtaskInfos.append((
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines), 
                    estimatedHours: estimatedHours
                ))
            }
            
            if !subtaskInfos.isEmpty {
                print("✅ 成功通过解析单个任务项获取子任务")
                return subtaskInfos
            }
        }
        
        // 如果所有尝试都失败，抛出错误
        print("⚠️ 无法解析响应为有效的JSON，响应内容:")
        print(response)
        throw NSError(domain: "AIGoalAnalysisService", code: 100, userInfo: [NSLocalizedDescriptionKey: "无法解析子任务响应"])
    }
    
    // MARK: - 响应解析方法
    
    /// 解析子任务响应
    /// - Parameters:
    ///   - response: API响应
    ///   - goal: 目标对象
    /// - Returns: 子任务列表
    private func parseSubtasks(from response: String, for goal: Goal) throws -> [SubTask] {
        // 预处理响应文本
        let cleanedResponse = preprocessResponse(response)
        print("🔍 对响应进行预处理")
        
        // 策略1: 尝试直接解析整个响应
        if let subtasks = tryParseFullResponse(cleanedResponse, for: goal) {
            print("✅ 成功通过直接解析获取子任务")
            return subtasks
        }
        
        // 策略2: 尝试提取JSON数组部分
        if let subtasks = tryExtractJsonArray(cleanedResponse, for: goal) {
            print("✅ 成功通过提取JSON数组获取子任务")
            return subtasks
        }
        
        // 策略3: 使用正则表达式提取JSON对象
        if let subtasks = tryExtractWithRegex(cleanedResponse, for: goal) {
            print("✅ 成功通过正则表达式获取子任务")
            return subtasks
        }
        
        // 策略4: 更宽松地解析每个任务项
        if let subtasks = tryParseEachTask(cleanedResponse, for: goal) {
            print("✅ 成功通过解析单个任务项获取子任务")
            return subtasks
        }
        
        // 如果所有尝试都失败，抛出错误
        print("⚠️ 无法解析响应为有效的JSON，响应内容:")
        print(response)
        throw NSError(domain: "AIGoalAnalysisService", code: 100, userInfo: [NSLocalizedDescriptionKey: "无法解析子任务响应"])
    }
    
    /// 从API响应中解析评语
    /// - Parameter response: API响应
    /// - Returns: 评语
    private func parseComment(from response: String) throws -> String {
        // 记录原始响应的前200个字符，避免日志过大
        print("📝 收到AI评估响应，响应前200个字符: \(String(response.prefix(200)))")
        
        // 尝试解析JSON格式的评语
        if let data = response.data(using: .utf8) {
            // 尝试解析JSON对象
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ 成功解析响应为JSON对象")
                    
                    // 记录JSON中包含的所有键
                    print("📊 JSON对象包含以下键: \(jsonObject.keys.joined(separator: ", "))")
                    
                    if let comment = jsonObject["comment"] as? String {
                        // 组合新的格式化评语，包含所有字段
                        var formattedComment = comment
                        
                        // 添加优点部分
                        if let strengths = jsonObject["strengths"] as? String, !strengths.isEmpty {
                            print("👍 解析到 'strengths' 字段")
                            formattedComment += "\n\n【优势】\n" + strengths
                        } else {
                            print("⚠️ 未找到有效的 'strengths' 字段")
                        }
                        
                        // 添加需改进部分
                        if let areasForImprovement = jsonObject["areas_for_improvement"] as? String, !areasForImprovement.isEmpty {
                            print("👍 解析到 'areas_for_improvement' 字段")
                            formattedComment += "\n\n【改进空间】\n" + areasForImprovement
                        } else {
                            print("⚠️ 未找到有效的 'areas_for_improvement' 字段")
                        }
                        
                        // 添加习惯养成部分
                        if let habitFormation = jsonObject["habit_formation"] as? String, !habitFormation.isEmpty {
                            print("👍 解析到 'habit_formation' 字段")
                            formattedComment += "\n\n【习惯养成建议】\n" + habitFormation
                        } else {
                            print("⚠️ 未找到有效的 'habit_formation' 字段")
                        }
                        
                        // 添加创新思路部分
                        if let innovationInsights = jsonObject["innovation_insights"] as? String, !innovationInsights.isEmpty {
                            print("👍 解析到 'innovation_insights' 字段")
                            formattedComment += "\n\n【创新思路】\n" + innovationInsights
                        } else {
                            print("⚠️ 未找到有效的 'innovation_insights' 字段")
                        }
                        
                        // 添加社会趋势分析
                        if let socialTrendAnalysis = jsonObject["social_trend_analysis"] as? String, !socialTrendAnalysis.isEmpty {
                            print("👍 解析到 'social_trend_analysis' 字段")
                            formattedComment += "\n\n【趋势分析】\n" + socialTrendAnalysis
                        } else {
                            print("⚠️ 未找到有效的 'social_trend_analysis' 字段")
                        }
                        
                        // 添加个性化建议部分
                        if let suggestions = jsonObject["personalized_suggestions"] as? String, !suggestions.isEmpty {
                            print("👍 解析到 'personalized_suggestions' 字段")
                            formattedComment += "\n\n【个性化建议】\n" + suggestions
                        } else {
                            print("⚠️ 未找到有效的 'personalized_suggestions' 字段")
                        }
                        
                        print("✅ 成功组合所有评估维度，最终评语长度: \(formattedComment.count)")
                        return formattedComment
                    } else {
                        print("⚠️ JSON对象中未找到 'comment' 字段")
                    }
                }
            } catch {
                print("❌ JSON解析失败: \(error.localizedDescription)")
            }
        }
        
        print("🔍 尝试提取JSON对象部分...")
        // 尝试提取JSON对象部分
        if let jsonStart = response.range(of: "{"),
           let jsonEnd = response.range(of: "}", options: .backwards),
           jsonStart.upperBound <= jsonEnd.lowerBound {
            let jsonString = response[jsonStart.lowerBound...jsonEnd.upperBound]
            print("📝 提取到JSON对象: \(String(jsonString.prefix(100)))...")
            
            // 尝试解析提取的JSON
            if let jsonData = String(jsonString).data(using: .utf8) {
                do {
                    if let jsonObject = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        print("✅ 成功解析提取的JSON为对象")
                        print("📊 提取的JSON对象包含以下键: \(jsonObject.keys.joined(separator: ", "))")
                        
                        if let comment = jsonObject["comment"] as? String {
                            // 组合新的格式化评语，包含所有字段
                            var formattedComment = comment
                            
                            // 添加优点部分
                            if let strengths = jsonObject["strengths"] as? String, !strengths.isEmpty {
                                print("👍 提取的JSON中包含 'strengths' 字段")
                                formattedComment += "\n\n【优势】\n" + strengths
                            } else {
                                print("⚠️ 提取的JSON中未找到有效的 'strengths' 字段")
                            }
                            
                            // 添加需改进部分
                            if let areasForImprovement = jsonObject["areas_for_improvement"] as? String, !areasForImprovement.isEmpty {
                                print("👍 提取的JSON中包含 'areas_for_improvement' 字段")
                                formattedComment += "\n\n【改进空间】\n" + areasForImprovement
                            } else {
                                print("⚠️ 提取的JSON中未找到有效的 'areas_for_improvement' 字段")
                            }
                            
                            // 添加习惯养成部分
                            if let habitFormation = jsonObject["habit_formation"] as? String, !habitFormation.isEmpty {
                                print("👍 提取的JSON中包含 'habit_formation' 字段")
                                formattedComment += "\n\n【习惯养成建议】\n" + habitFormation
                            } else {
                                print("⚠️ 提取的JSON中未找到有效的 'habit_formation' 字段")
                            }
                            
                            // 添加创新思路部分
                            if let innovationInsights = jsonObject["innovation_insights"] as? String, !innovationInsights.isEmpty {
                                print("👍 提取的JSON中包含 'innovation_insights' 字段")
                                formattedComment += "\n\n【创新思路】\n" + innovationInsights
                            } else {
                                print("⚠️ 提取的JSON中未找到有效的 'innovation_insights' 字段")
                            }
                            
                            // 添加社会趋势分析
                            if let socialTrendAnalysis = jsonObject["social_trend_analysis"] as? String, !socialTrendAnalysis.isEmpty {
                                print("👍 提取的JSON中包含 'social_trend_analysis' 字段")
                                formattedComment += "\n\n【趋势分析】\n" + socialTrendAnalysis
                            } else {
                                print("⚠️ 提取的JSON中未找到有效的 'social_trend_analysis' 字段")
                            }
                            
                            // 添加个性化建议部分
                            if let suggestions = jsonObject["personalized_suggestions"] as? String, !suggestions.isEmpty {
                                print("👍 提取的JSON中包含 'personalized_suggestions' 字段")
                                formattedComment += "\n\n【个性化建议】\n" + suggestions
                            } else {
                                print("⚠️ 提取的JSON中未找到有效的 'personalized_suggestions' 字段")
                            }
                            
                            print("✅ 成功组合提取的JSON中的所有评估维度，最终评语长度: \(formattedComment.count)")
                            return formattedComment
                        } else {
                            print("⚠️ 提取的JSON对象中未找到 'comment' 字段")
                        }
                    }
                } catch {
                    print("❌ 提取的JSON解析失败: \(error.localizedDescription)")
                }
            }
        }
        
        print("🔍 尝试使用正则表达式提取评语...")
        // 如果上述方法都失败，尝试从响应文本中用正则表达式提取评语
        let pattern = "\"comment\"\\s*:\\s*\"([^\"]*)\""
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            
            if let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
               let range = Range(match.range(at: 1), in: response) {
                let comment = String(response[range])
                print("✅ 成功使用正则表达式提取comment字段，长度: \(comment.count)")
                return comment
            } else {
                print("⚠️ 正则表达式未能匹配任何评语")
            }
        } catch {
            print("❌ 创建正则表达式失败: \(error.localizedDescription)")
            throw NSError(domain: "AIGoalAnalysisService", code: 100, userInfo: [NSLocalizedDescriptionKey: "无法创建正则表达式"])
        }
        
        // 如果正则表达式方法也失败，则直接返回响应文本（清理可能的Markdown格式）
        print("⚠️ 所有解析方法都失败，返回清理后的原始响应")
        let cleanedResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanedResponse
    }
    
    // MARK: - 本地生成方法
    
    /// 本地生成子任务（如果API调用失败）
    /// - Parameter goal: 目标对象
    /// - Returns: 子任务列表
    private func generateLocalSubtasksAsync(_ goal: Goal) async -> [SubTask] {
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒
        
        // 创建基本子任务模板
        let taskTitles = [
            "需求分析 - 详细调研并记录所有功能需求",
            "用户场景设计 - 确定目标用户群体和使用场景",
            "功能架构 - 创建系统功能结构图和数据流图",
            "原型设计 - 制作低保真原型并进行用户测试",
            "技术选型 - 评估并确定适合的技术栈",
            "环境搭建 - 配置开发和测试环境",
            "数据模型设计 - 设计数据库结构和API接口"
        ]
        
        // 每个任务的预计小时数
        let estimatedHours = [24, 24, 24, 48, 24, 12, 36]
        
        // 根据目标特性选择子任务数量
        let complexity = goal.goalDescription.count / 20 // 根据描述长度估算复杂度
        let taskCount = min(taskTitles.count, max(5, complexity))
        
        // 在主线程上创建SwiftData对象
        return await MainActor.run {
            var subtasks: [SubTask] = []
            for i in 0..<taskCount {
                let subtask = SubTask(title: taskTitles[i], note: "系统生成的默认子任务", priority: 0)
                subtask.goal = goal
                subtask.estimatedHours = estimatedHours[i % estimatedHours.count]
                subtasks.append(subtask)
            }
            return subtasks
        }
    }
    
    /// 本地生成替代子任务（刷新分析API调用失败）
    /// - Parameter goal: 目标对象
    /// - Returns: 子任务列表
    private func generateAlternativeSubtasksAsync(_ goal: Goal) async -> [SubTask] {
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒
        
        // 第二套任务模板，侧重于不同的方法论
        let taskTitles = [
            "目标细化 - 将目标分解为SMART原则的多个小目标",
            "资源评估 - 确定实现目标所需的人力和物力资源",
            "风险分析 - 识别可能的风险点并制定应对策略",
            "里程碑规划 - 设定关键进度节点和验收标准",
            "工作分解 - 细化每个里程碑的具体工作内容",
            "时间线制定 - 安排各项任务的时间表和优先级",
            "团队组织 - 确定责任人和协作机制"
        ]
        
        // 每个任务的预计小时数
        let estimatedHours = [24, 12, 24, 24, 36, 24, 12]
        
        // 根据目标估算复杂度选择任务数量
        let complexity = (goal.title.count + goal.goalDescription.count) / 30
        let taskCount = min(taskTitles.count, max(6, complexity))
        
        // 在主线程上创建SwiftData对象
        return await MainActor.run {
            var subtasks: [SubTask] = []
            for i in 0..<taskCount {
                let subtask = SubTask(title: taskTitles[i], note: "系统生成的替代子任务", priority: 0)
                subtask.goal = goal
                subtask.estimatedHours = estimatedHours[i % estimatedHours.count]
                subtasks.append(subtask)
            }
            return subtasks
        }
    }
    
    /// 本地生成评估结果（评估API调用失败）
    /// - Parameter goal: 目标
    /// - Returns: 评语
    private func generateLocalEvaluationAsync(_ goal: Goal) async -> String {
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
        
        // 在主线程上安全地获取评估所需的统计数据
        let stats = await MainActor.run {
            // 1. 内容相关性评分 (权重50%)
            var relevanceScore = 0
            let tasksWithRelevantProof = goal.subTasks.filter { subtask in
                if let proof = subtask.completionProof {
                    // 检查成果描述是否与子任务相关
                    if let description = proof.proofDescription, !description.isEmpty {
                        // 简单相关性检查：成果描述中是否包含子任务关键词
                        let keywords = subtask.title.components(separatedBy: " ")
                        return keywords.contains { description.contains($0) }
                    }
                    return false
                }
                return false
            }
            let relevanceRate = Double(tasksWithRelevantProof.count) / Double(max(1, goal.completedSubTasksCount))
            relevanceScore = Int(relevanceRate * 50)
            
            // 2. 完成度评分 (权重30%)
            let completionRate = Double(goal.completedSubTasksCount) / Double(max(1, goal.subTasks.count))
            let completionScore = Int(completionRate * 30)
            
            // 3. 时间效率评分 (权重20%)
            var timeScore = 0
            if let startDate = goal.startExecutionDate, let completedDate = goal.completedDate {
                let totalTime = completedDate.timeIntervalSince(startDate)
                
                // 计算所有子任务的预计总小时数
                let totalEstimatedHours = goal.subTasks.reduce(0.0) { $0 + Double($1.estimatedHours) }
                
                let estimatedTime = totalEstimatedHours * 3600 // 转换为秒
                if totalTime <= estimatedTime {
                    timeScore = 20 // 按时完成
                } else if totalTime <= estimatedTime * 1.3 {
                    timeScore = 15 // 稍微超时
                } else {
                    timeScore = 10 // 严重超时
                }
            } else {
                timeScore = 10 // 默认时间得分
            }
            
            return (relevanceScore, completionScore, timeScore)
        }
        
        // 解构数据
        let (relevanceScore, completionScore, timeScore) = stats
        
        // 综合得分
        let score = relevanceScore + completionScore + timeScore
        
        // 根据得分生成评语
        var comment: String
        var strengths: String
        var areasForImprovement: String
        var habitFormation: String
        var innovationInsights: String
        var socialTrendAnalysis: String
        var suggestions: String
        
        if score >= 90 {
            comment = "目标完成情况优秀。成果与目标高度相关，证明材料充分，时间管理合理。总体来看，目标的核心价值得到了很好的实现。"
            strengths = "任务分解合理，执行高效，成果质量高，时间管理出色。"
            areasForImprovement = "即使表现优秀，仍可在细节完善和成果展示方面进一步提升。"
            habitFormation = "您已经展现出优秀的执行习惯和时间管理能力。建议将这些好习惯系统化，可以尝试建立个人的「目标达成SOP」，帮助您在未来的项目中复制这种成功模式。"
            innovationInsights = "在高效完成目标的同时，可以尝试引入更多创新思维，如「横向思考法」或「SCAMPER技术」，探索如何让成果产生更大的影响力。"
            socialTrendAnalysis = "您的高效执行力在当前社会非常有价值。随着远程工作和灵活就业模式的普及，自律和高效的工作习惯将成为核心竞争力。"
            suggestions = "建议将此次目标的成功经验总结为方法论，应用到未来类似目标中；可以考虑将成果进一步系统化，形成可复用的知识或资产；尝试设定更具挑战性的目标，拓展自己的能力边界。"
        } else if score >= 80 {
            comment = "目标基本达成，成果与目标相关性良好。大部分子任务完成质量较高，时间管理总体合理，但仍有提升空间。"
            strengths = "目标完成度高，大部分子任务质量达标，时间规划基本合理。"
            areasForImprovement = "部分子任务的成果相关性有待提高，时间分配可以更加优化。"
            habitFormation = "您已经形成了不错的目标执行习惯。建议尝试「两分钟法则」，即把开始一项任务的门槛降到只需要两分钟的程度，这样可以克服拖延，增强任务启动的顺畅度。"
            innovationInsights = "可以尝试「跨领域思维」，把其他行业或领域的解决方案应用到当前目标中，这样可能会产生意想不到的创新洞见。"
            socialTrendAnalysis = "在信息过载的时代，有效筛选和聚焦的能力越来越受到重视。您在目标管理上的能力与这一趋势高度契合，未来可以进一步发展成为一种核心竞争力。"
            suggestions = "建议在下一个目标中优化任务分解的粒度，使每个子任务更加聚焦；可以尝试使用更多可视化工具记录成果，增强成果展示的直观性；适当提前规划风险应对措施，避免临时调整带来的时间压力。"
        } else if score >= 70 {
            comment = "目标部分达成，但成果与目标的相关性有待提高。完成的子任务数量尚可，但质量参差不齐，时间管理有明显改进空间。"
            strengths = "能够坚持完成大部分子任务，展示了一定的执行力，部分成果有价值。"
            areasForImprovement = "成果与目标的相关性不够紧密，时间分配不够合理，部分子任务完成质量不高。"
            habitFormation = "您已经有了坚持执行的意识，这是很好的开始。建议引入「习惯追踪」工具（如习惯打卡App），并设置适当的奖励机制，让习惯形成变得更加有趣和可持续。"
            innovationInsights = "可以尝试「逆向思考」法，即从目标的最终状态反推所需步骤，这往往能发现常规思路中容易忽略的关键环节。"
            socialTrendAnalysis = "当前社会越来越重视过程管理而非结果导向，精益思想(Lean Thinking)正在各行各业普及。将这一理念应用到个人目标管理中，可以帮助您在混杂的任务中找到真正的价值点。"
            suggestions = "建议下次目标制定时，更清晰地定义成功标准；增加阶段性检查点，及时调整偏离方向的子任务；可以尝试番茄工作法等时间管理技术，提高专注度和效率；适当减少子任务数量，确保每个任务都能高质量完成。"
        } else if score >= 60 {
            comment = "目标完成度不足，提交的成果与目标相关性较弱。多数子任务未完成或完成质量较低，时间管理效率低下。"
            strengths = "展示了开始执行目标的意愿，有部分有价值的成果产出。"
            areasForImprovement = "目标分解不够合理，导致执行困难；时间管理欠佳；成果与目标关联度低。"
            habitFormation = "建议从「微习惯」开始培养执行力，设定极小的目标（如每天只专注工作5分钟），确保100%能完成，逐渐建立自信和动力。《微习惯》这本书可能对您有所帮助。"
            innovationInsights = "尝试使用「约束创新法」，即在资源有限的情况下寻找创新解决方案。有时限制反而能激发创造力，帮助我们找到更高效的途径。"
            socialTrendAnalysis = "碎片化学习和工作已成为常态，但这也带来了注意力不集中的问题。学习「深度工作」(Deep Work)的理念和方法，将帮助您在这个充满干扰的时代保持高效率。"
            suggestions = "建议重新审视目标设定，确保目标符合SMART原则（具体、可衡量、可实现、相关性、时限性）；可以先从更小的目标开始，建立成功经验；尝试邀请同伴监督或定期复盘，增强执行力；学习基础的项目管理方法，提高规划和执行能力。"
        } else {
            comment = "目标几乎未达成，提交的成果与目标无明显关联。大多数子任务未完成，时间管理混乱。"
            strengths = "至少有尝试设定目标并开始行动的意识，这是自我提升的第一步。"
            areasForImprovement = "目标可能过于宏大或模糊，子任务分解不当，执行力和时间管理都存在严重问题。"
            habitFormation = "良好习惯的养成需要从最基础开始。建议先建立「最小行动」习惯，如每天固定时间花5分钟回顾当天计划、使用番茄钟法专注工作20分钟等。利用「习惯堆叠」技术，将新习惯与已有的日常活动绑定，增加执行的概率。"
            innovationInsights = "尝试「思维导图」工具来整理思路，有时目标执行不畅可能是因为思路不够清晰。这种可视化的思考方式能帮助发现新的连接点和机会。"
            socialTrendAnalysis = "在快节奏的社会中，「慢生活」(Slow Movement)理念正受到越来越多人的认可。适度降低期望值，专注于少而精的目标，可能比追求数量更能带来实质性进步和幸福感。"
            suggestions = "建议显著降低目标难度，设定更小、更具体的目标；学习基础的目标管理和时间规划技巧；可以采用\"不破不立\"的方式，先专注于养成定期回顾和计划的习惯；考虑寻求专业辅导或使用结构化的目标管理工具。"
        }
        
        // 组合成完整的评估结果
        let finalComment = comment + 
            "\n\n【优势】\n" + strengths + 
            "\n\n【改进空间】\n" + areasForImprovement + 
            "\n\n【习惯养成建议】\n" + habitFormation + 
            "\n\n【创新思路】\n" + innovationInsights + 
            "\n\n【趋势分析】\n" + socialTrendAnalysis + 
            "\n\n【个性化建议】\n" + suggestions + 
            "\n\n此评语由 AI 生成，仅供参考。"
        
        return finalComment
    }
    
    // MARK: - 辅助解析方法
    
    /// 预处理响应文本，移除可能干扰JSON解析的内容
    private func preprocessResponse(_ response: String) -> String {
        var cleaned = response
        
        // 移除可能的Markdown代码块标记
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        
        // 移除响应开头的非JSON文本（例如"以下是任务分解："等）
        if let jsonStart = cleaned.range(of: "[") {
            let textBeforeJson = cleaned[cleaned.startIndex..<jsonStart.lowerBound]
            if !textBeforeJson.isEmpty && textBeforeJson.contains(where: { $0.isLetter }) {
                cleaned = String(cleaned[jsonStart.lowerBound...])
            }
        }
        
        // 移除响应结尾的非JSON文本
        if let jsonEnd = cleaned.range(of: "]", options: .backwards) {
            let textAfterJson = cleaned[jsonEnd.upperBound..<cleaned.endIndex]
            if !textAfterJson.isEmpty && textAfterJson.contains(where: { $0.isLetter }) {
                cleaned = String(cleaned[..<jsonEnd.upperBound])
            }
        }
        
        // 移除可能的注释行
        let lines = cleaned.split(separator: "\n")
        let filteredLines = lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("//") }
        cleaned = filteredLines.joined(separator: "\n")
        
        return cleaned
    }
    
    // MARK: - 图片处理
    
    /// 压缩图片数据到指定大小
    /// - Parameters:
    ///   - imageData: 原始图片数据
    ///   - maxSize: 最大允许大小（单位：字节）
    /// - Returns: 压缩后的图片数据
    private func compressImage(_ imageData: Data, maxSize: Int = 200_000) -> Data {
        // 如果图片已经小于最大尺寸，直接返回
        if imageData.count <= maxSize {
            return imageData
        }
        
        // 尝试解码图片
        guard let image = UIImage(data: imageData) else {
            return imageData
        }
        
        // 首先尝试降低图片尺寸
        var targetSize = CGSize(width: 800, height: 800)
        UIGraphicsBeginImageContext(targetSize)
        
        // 计算适合的尺寸，保持宽高比
        let aspectRatio = image.size.width / image.size.height
        var drawingSize: CGSize
        
        if aspectRatio > 1 { // 宽图
            drawingSize = CGSize(width: 800, height: 800 / aspectRatio)
        } else { // 高图或正方形
            drawingSize = CGSize(width: 800 * aspectRatio, height: 800)
        }
        
        let drawingRect = CGRect(
            x: (targetSize.width - drawingSize.width) / 2,
            y: (targetSize.height - drawingSize.height) / 2,
            width: drawingSize.width,
            height: drawingSize.height
        )
        
        image.draw(in: drawingRect)
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // 然后尝试降低图片质量
        var compression: CGFloat = 0.8
        var compressedData = resizedImage?.jpegData(compressionQuality: compression) ?? imageData
        
        // 逐步降低压缩质量，直到达到目标大小
        while compressedData.count > maxSize && compression > 0.1 {
            compression -= 0.1
            compressedData = resizedImage?.jpegData(compressionQuality: compression) ?? compressedData
        }
        
        // 如果压缩后仍然过大，再次尝试降低分辨率
        if compressedData.count > maxSize,
           let stillLargeImage = UIImage(data: compressedData) {
            let furtherDownscale = sqrt(Double(maxSize) / Double(compressedData.count))
            let smallerSize = CGSize(
                width: targetSize.width * furtherDownscale,
                height: targetSize.height * furtherDownscale
            )
            
            UIGraphicsBeginImageContext(smallerSize)
            stillLargeImage.draw(in: CGRect(origin: .zero, size: smallerSize))
            if let finalImage = UIGraphicsGetImageFromCurrentImageContext() {
                UIGraphicsEndImageContext()
                if let finalData = finalImage.jpegData(compressionQuality: 0.7) {
                    compressedData = finalData
                }
            }
            UIGraphicsEndImageContext()
        }
        
        print("图片压缩: 原始大小 \(imageData.count/1024)KB -> 压缩后 \(compressedData.count/1024)KB")
        return compressedData
    }
    
    /// 策略1: 尝试直接解析整个响应
    private func tryParseFullResponse(_ response: String, for goal: Goal) -> [SubTask]? {
        if let data = response.data(using: .utf8),
           let subtaskData = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var subtasks: [SubTask] = []
            
            for subtaskInfo in subtaskData {
                guard let title = subtaskInfo["title"] as? String else {
                    continue
                }
                
                let note = "AI生成的子任务"
                let subtask = SubTask(title: title, note: note, priority: 0)
                subtask.goal = goal
                subtasks.append(subtask)
            }
            
            if !subtasks.isEmpty {
                return subtasks
            }
        }
        return nil
    }
    
    /// 策略2: 尝试提取JSON数组部分
    private func tryExtractJsonArray(_ response: String, for goal: Goal) -> [SubTask]? {
        if let jsonStart = response.range(of: "["),
           let jsonEnd = response.range(of: "]", options: .backwards),
           jsonStart.upperBound <= jsonEnd.lowerBound {
            let jsonString = response[jsonStart.lowerBound...jsonEnd.upperBound]
            
            // 尝试解析提取的JSON
            if let jsonData = String(jsonString).data(using: .utf8),
               let subtaskData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                var subtasks: [SubTask] = []
                
                for subtaskInfo in subtaskData {
                    guard let title = subtaskInfo["title"] as? String else {
                        continue
                    }
                    
                    let note = "AI生成的子任务"
                    let subtask = SubTask(title: title, note: note, priority: 0)
                    subtask.goal = goal
                    subtasks.append(subtask)
                }
                
                if !subtasks.isEmpty {
                    return subtasks
                }
            }
        }
        return nil
    }
    
    /// 策略3: 使用正则表达式提取JSON对象
    private func tryExtractWithRegex(_ response: String, for goal: Goal) -> [SubTask]? {
        // 使用正则表达式提取任务项
        let pattern = "\\{\\s*\"title\"\\s*:\\s*\"([^\"]*)\"\\s*,\\s*\"estimatedHours\"\\s*:\\s*(\\d+)\\s*\\}"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let matches = regex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        
        if !matches.isEmpty {
            var subtasks: [SubTask] = []
            
            for match in matches {
                guard let titleRange = Range(match.range(at: 1), in: response) else {
                    continue
                }
                
                let title = String(response[titleRange])
                let note = "AI生成的子任务"
                let subtask = SubTask(title: title, note: note, priority: 0)
                subtask.goal = goal
                subtasks.append(subtask)
            }
            
            if !subtasks.isEmpty {
                return subtasks
            }
        }
        return nil
    }
    
    /// 策略4: 更宽松地解析每个任务项
    private func tryParseEachTask(_ response: String, for goal: Goal) -> [SubTask]? {
        // 寻找任务标题模式
        let titlePattern = "(?:\"title\"\\s*:\\s*\"([^\"]*)\")|(?:标题[：:]\\s*\"?([^\"\\n,}]*)\"?)"
        
        guard let titleRegex = try? NSRegularExpression(pattern: titlePattern, options: []) else {
            return nil
        }
        
        let titleMatches = titleRegex.matches(in: response, options: [], range: NSRange(response.startIndex..., in: response))
        
        if titleMatches.count > 0 {
            var subtasks: [SubTask] = []
            
            for titleMatch in titleMatches {
                // 提取标题
                var title = ""
                if let titleRange1 = Range(titleMatch.range(at: 1), in: response), !response[titleRange1].isEmpty {
                    title = String(response[titleRange1])
                } else if let titleRange2 = Range(titleMatch.range(at: 2), in: response), !response[titleRange2].isEmpty {
                    title = String(response[titleRange2])
                } else {
                    continue
                }
                
                let note = "AI生成的子任务"
                let subtask = SubTask(title: title.trimmingCharacters(in: .whitespacesAndNewlines), 
                                   note: note, 
                                   priority: 0)
                subtask.goal = goal
                subtasks.append(subtask)
            }
            
            if !subtasks.isEmpty {
                return subtasks
            }
        }
        return nil
    }
    
    private func calculateTimeScore(goal: Goal) -> Int {
        print("📆 计算时间效率分数")
        
        // 1. 获取子任务列表 - 使用目标的子任务属性而不是创建新的查询
        let subTasks = goal.subTasks
        
        guard !subTasks.isEmpty else {
            print("⚠️ 目标没有子任务，无法计算时间分数")
            return 0
        }
        
        // 2. 计算子任务的预估总小时数
        let totalEstimatedHours = subTasks.reduce(0) { $0 + $1.estimatedHours }
        
        if totalEstimatedHours <= 0 {
            print("⚠️ 子任务没有有效的预估小时数，无法计算时间分数")
            return 0
        }
        
        print("📊 子任务预估总小时数: \(totalEstimatedHours)")
        
        // 3. 根据预估总小时数计算时间效率分数
        var timeScore = 0
        if let startDate = goal.startExecutionDate, let completedDate = goal.completedDate {
            let totalTime = completedDate.timeIntervalSince(startDate)
            
            let estimatedTime = Double(totalEstimatedHours) * 3600 // 转换为秒
            if totalTime <= estimatedTime {
                timeScore = 20 // 按时完成
            } else if totalTime <= estimatedTime * 1.3 {
                timeScore = 15 // 稍微超时
            } else {
                timeScore = 10 // 严重超时
            }
        } else {
            timeScore = 10 // 默认时间得分
        }
        
        return timeScore
    }
}



