import Foundation
import SwiftData
import Combine
import UIKit

class GoalViewModel: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    var modelContext: ModelContext?
    
    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
        fetchGoals()
    }
    
    func fetchGoals() {
        guard let modelContext = modelContext else { return }
        
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdDate, order: .reverse)])
        do {
            goals = try modelContext.fetch(descriptor)
            // 更新所有目标的状态，直接调用不需要try-catch
            for goal in goals {
                // 直接调用更新状态方法，不再使用try-catch
                goal.updateStatus()
            }
        } catch {
            errorMessage = "无法加载目标: \(error.localizedDescription)"
            print("获取目标时出错: \(error)")
        }
    }
    
    func addGoal(title: String, goalDescription: String, priority: GoalPriority = .standard, targetDate: Date?) {
        guard let modelContext = modelContext else { return }
        
        let newGoal = Goal(title: title, goalDescription: goalDescription, priority: .standard, targetCompletionDate: targetDate)
        modelContext.insert(newGoal)
        
        do {
            try modelContext.save()
            fetchGoals()
        } catch {
            errorMessage = "无法保存目标: \(error.localizedDescription)"
        }
    }
    
    func updateGoal(_ goal: Goal) {
        guard let modelContext = modelContext else { return }
        
        // 如果有子任务，更新目标状态
        if !goal.subTasks.isEmpty {
            if goal.completedSubTasksCount == goal.subTasks.count {
                // 所有子任务都已完成，将目标标记为已完成
                if !goal.isCompleted {
                    goal.markAsCompleted()
                }
            } else if goal.status == .completed {
                // 有子任务未完成，但目标状态为已完成，重置为进行中
                goal.status = .inProgress
                goal.completedDate = nil
            } else {
                // 更新状态为进行中
                if goal.status == .notStarted {
                    goal.status = .inProgress
                }
            }
        }
        
        // 保存更改
        do {
            try modelContext.save()
            fetchGoals()
        } catch {
            errorMessage = "无法更新目标: \(error.localizedDescription)"
        }
    }
    
    func markAsCompleted(_ goal: Goal) {
        goal.markAsCompleted()
        updateGoal(goal)
    }
    
    func deleteGoal(_ goal: Goal) {
        guard let modelContext = modelContext else { return }
        
        modelContext.delete(goal)
        
        do {
            try modelContext.save()
            fetchGoals()
        } catch {
            errorMessage = "无法删除目标: \(error.localizedDescription)"
        }
    }
    
    // 添加子任务
    func addSubTask(to goal: Goal, title: String, estimatedDays: Int = 1) {
        guard let modelContext = modelContext else { return }
        
        // 计算顺序，默认添加到末尾
        let order = goal.subTasks.isEmpty ? 0 : goal.subTasks.map { $0.order }.max()! + 1
        
        let subTask = SubTask(title: title)
        subTask.order = order
        subTask.estimatedHours = estimatedDays * 24 // 转换天为小时
        subTask.goal = goal
        goal.subTasks.append(subTask)
        
        do {
            try modelContext.save()
            updateGoal(goal)
        } catch {
            errorMessage = "无法添加子任务: \(error.localizedDescription)"
        }
    }
    
    // 重新排序子任务
    func reorderSubTasks(for goal: Goal, from: Int, to: Int) {
        guard let modelContext = modelContext else { return }
        
        // 获取排序后的子任务数组
        var orderedTasks = goal.subTasks.sorted(by: { $0.order < $1.order })
        
        // 移动元素
        let task = orderedTasks.remove(at: from)
        orderedTasks.insert(task, at: to)
        
        // 更新所有子任务的顺序
        for (index, task) in orderedTasks.enumerated() {
            task.order = index
        }
        
        do {
            try modelContext.save()
            updateGoal(goal)
        } catch {
            errorMessage = "无法重新排序子任务: \(error.localizedDescription)"
        }
    }
    
    // 新增：基于ID的子任务重排序方法
    func reorderSubTasksByID(for goal: Goal, fromID: UUID, toID: UUID) {
        guard let modelContext = modelContext else { return }
        
        // 获取排序后的子任务数组
        var orderedTasks = goal.subTasks.sorted(by: { $0.order < $1.order })
        
        // 根据ID找到对应的任务和索引
        guard let fromTask = orderedTasks.first(where: { $0.id == fromID }),
              let fromIndex = orderedTasks.firstIndex(where: { $0.id == fromID }),
              let toIndex = orderedTasks.firstIndex(where: { $0.id == toID }) else {
            return
        }
        
        // 移除任务并插入到新位置
        orderedTasks.remove(at: fromIndex)
        orderedTasks.insert(fromTask, at: toIndex)
        
        // 更新所有子任务的顺序
        for (index, task) in orderedTasks.enumerated() {
            task.order = index
        }
        
        do {
            try modelContext.save()
            // 使用轻量级更新，避免触发复杂的业务逻辑
            fetchGoals()
        } catch {
            errorMessage = "无法重新排序子任务: \(error.localizedDescription)"
        }
    }
    
    // 更新子任务
    func updateSubTask(_ subTask: SubTask) {
        guard let modelContext = modelContext, let goal = subTask.goal else { return }
        
        do {
            try modelContext.save()
            updateGoal(goal)
        } catch {
            errorMessage = "无法更新子任务: \(error.localizedDescription)"
        }
    }
    
    // 删除子任务
    func deleteSubTask(_ subTask: SubTask) {
        guard let modelContext = modelContext, let goal = subTask.goal else { return }
        
        // 从目标的子任务数组中移除
        if let index = goal.subTasks.firstIndex(where: { $0.id == subTask.id }) {
            goal.subTasks.remove(at: index)
        }
        
        // 从数据库中删除
        modelContext.delete(subTask)
        
        do {
            try modelContext.save()
            updateGoal(goal)
        } catch {
            errorMessage = "无法删除子任务: \(error.localizedDescription)"
        }
    }
    
    // 按日期分组的目标
    func goalsByDateSection() -> [DateSection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let pastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        let pastMonth = calendar.date(byAdding: .day, value: -30, to: today)!
        
        var sections: [DateSection] = []
        var todayGoals: [Goal] = []
        var yesterdayGoals: [Goal] = []
        var pastWeekGoals: [Goal] = []
        var pastMonthGoals: [Goal] = []
        var earlierGoals: [Goal] = []
        
        // 分类处理
        for goal in goals {
            let goalDate = calendar.startOfDay(for: goal.createdDate)
            
            if calendar.isDate(goalDate, inSameDayAs: today) {
                todayGoals.append(goal)
            } else if calendar.isDate(goalDate, inSameDayAs: yesterday) {
                yesterdayGoals.append(goal)
            } else if goalDate >= pastWeek {
                pastWeekGoals.append(goal)
            } else if goalDate >= pastMonth {
                pastMonthGoals.append(goal)
            } else {
                earlierGoals.append(goal)
            }
        }
        
        // 添加非空分类到结果中
        if !todayGoals.isEmpty {
            sections.append(DateSection(title: "今天", goals: todayGoals))
        }
        
        if !yesterdayGoals.isEmpty {
            sections.append(DateSection(title: "昨天", goals: yesterdayGoals))
        }
        
        if !pastWeekGoals.isEmpty {
            sections.append(DateSection(title: "过去 7 天", goals: pastWeekGoals))
        }
        
        if !pastMonthGoals.isEmpty {
            sections.append(DateSection(title: "过去 30 天", goals: pastMonthGoals))
        }
        
        if !earlierGoals.isEmpty {
            sections.append(DateSection(title: "更早", goals: earlierGoals))
        }
        
        return sections
    }
    
    // 开始执行目标
    func startGoalExecution(_ goal: Goal) {
        // 清除方案缓存
        AIGoalAnalysisService.shared.clearPlanCache(for: goal)
        
        // 更新目标状态
        goal.startExecution()
        updateGoal(goal)
        
        // 添加触觉反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    // 完成目标执行并进入评估阶段
    func finishGoalExecution(_ goal: Goal) {
        goal.finishExecution()
        updateGoal(goal)
    }
    
    // 设置AI评估结果
    func setGoalEvaluation(_ goal: Goal, comment: String) {
        goal.setEvaluation(comment: comment)
        updateGoal(goal)
    }
    
    // 为子任务添加完成证明
    func addCompletionProof(to subTask: SubTask, imagesData: [Data], description: String) {
        guard let modelContext = modelContext, let _ = subTask.goal else { return }
        
        // 创建证明对象
        let proof = CompletionProof(imagesData: imagesData, description: description, subTask: subTask)
        
        // 保存证明
        modelContext.insert(proof)
        
        // 也需要插入所有额外的图片（ProofImage对象）
        for proofImage in proof.additionalImages {
            modelContext.insert(proofImage)
        }
        
        do {
            try modelContext.save()
        } catch {
            errorMessage = "无法保存证明: \(error.localizedDescription)"
        }
    }
    
    // 标记子任务为已完成
    func markSubTaskCompleted(_ subTask: SubTask) {
        guard let goal = subTask.goal else { return }
        
        // 标记子任务为已完成
        subTask.markAsCompleted()
        
        // 保存更改
        updateSubTask(subTask)
        
        // 更新目标状态
        updateGoal(goal)
    }
    
    // 获取子任务的完成证明
    func getCompletionProof(for subTask: SubTask) -> CompletionProof? {
        guard let modelContext = modelContext else { return nil }
        
        // 创建查询 - 使用简单的字符串谓词
        let descriptor = FetchDescriptor<CompletionProof>()
        
        do {
            let proofs = try modelContext.fetch(descriptor)
            // 在内存中过滤
            return proofs.first { $0.subTask?.id == subTask.id }
        } catch {
            errorMessage = "无法获取证明: \(error.localizedDescription)"
            return nil
        }
    }
    
    // 完成目标
    func completeGoal(_ goal: Goal) {
        // 标记目标为已完成
        goal.markAsCompleted()
        
        // 更新目标状态为评估中
        goal.finishExecution()
        
        // 保存更改
        updateGoal(goal)
    }
    
    // 根据子任务找到对应的目标
    func getGoalForSubTask(_ subTask: SubTask) -> Goal? {
        return goals.first { goal in
            goal.subTasks.contains { $0.id == subTask.id }
        }
    }
    
    // 创建App Store审核测试数据
    func createTestData(for reviewEmail: String) {
        guard let modelContext = modelContext else { return }
        
        print("为App Store审核账户创建测试数据: \(reviewEmail)")
        
        // 检查是否已经存在数据，避免重复创建
        let descriptor = FetchDescriptor<Goal>()
        guard let existingGoals = try? modelContext.fetch(descriptor), existingGoals.isEmpty else {
            print("已存在数据，跳过测试数据创建")
            return
        }
        
        // 创建已完成目标 - Swift学习
        createCompletedGoal(
            title: "学习Swift编程基础",
            description: "掌握Swift语言基础知识，为iOS开发打下基础",
            daysAgo: 3,
            subTasks: [
                "了解Swift语法基础",
                "学习变量、常量和基本数据类型",
                "掌握函数和闭包的使用",
                "学习类和结构体",
                "理解Swift中的协议和扩展"
            ],
            score: 4.8
        )
        
        // 创建已完成目标 - 健身计划
        createCompletedGoal(
            title: "完成健身计划第一阶段",
            description: "坚持每周3次训练，完成第一阶段健身目标",
            daysAgo: 7,
            subTasks: [
                "制定每周训练计划",
                "学习正确的训练姿势",
                "完成第一周力量训练",
                "完成第二周有氧训练",
                "制定合理的饮食计划",
                "记录每次训练数据"
            ],
            score: 4.5
        )
        
        // 创建进行中目标 - 阅读
        createInProgressGoal(
            title: "阅读《原子习惯》",
            description: "通过阅读《原子习惯》，学习如何建立良好的习惯",
            daysRemaining: 3,
            progress: 0.6,
            subTasks: [
                "阅读第一章并做笔记",
                "阅读第二章并做笔记",
                "阅读第三章并做笔记",
                "实践书中提到的方法",
                "总结阅读心得"
            ],
            completedIndices: [0, 1, 2]
        )
        
        // 创建进行中目标 - SwiftUI学习
        createInProgressGoal(
            title: "学习iOS SwiftUI开发",
            description: "掌握SwiftUI框架，能够独立开发iOS应用",
            daysRemaining: 12,
            progress: 0.3,
            subTasks: [
                "学习SwiftUI基础控件",
                "了解SwiftUI布局系统",
                "学习数据流和状态管理",
                "实现简单的列表和导航",
                "学习自定义视图和动画",
                "掌握与系统框架的集成",
                "学习SwiftData数据持久化",
                "完成一个完整的Demo应用"
            ],
            completedIndices: [0, 1]
        )
        
        // 创建规划中目标 - 英语学习
        createPlanningGoal(
            title: "准备英语考试",
            description: "系统备考英语等级考试，提高英语水平",
            daysRemaining: 30,
            subTasks: [
                "制定详细的学习计划",
                "每天背诵50个单词",
                "每天做2套听力练习",
                "每周完成4篇阅读理解",
                "每周写2篇作文并请教师批改",
                "做3套模拟试题",
                "整理易错点和重点语法",
                "制作单词记忆卡片",
                "每天进行口语练习",
                "报名参加考试"
            ]
        )
        
        // 创建规划中目标 - 个人博客
        createPlanningGoal(
            title: "开发个人博客网站",
            description: "使用现代技术栈开发一个个人技术博客网站",
            daysRemaining: 45,
            subTasks: [
                "确定网站功能和技术栈",
                "设计网站结构和数据库",
                "实现用户认证系统",
                "开发文章发布和管理功能",
                "实现评论和互动功能",
                "优化网站性能和SEO",
                "部署网站到云服务器"
            ]
        )
        
        print("已成功创建App Store审核测试数据")
    }
    
    // 创建已完成的目标
    private func createCompletedGoal(title: String, description: String, daysAgo: Int, subTasks: [String], score: Double) {
        guard let modelContext = modelContext else { return }
        
        let calendar = Calendar.current
        let completedDate = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let startDate = calendar.date(byAdding: .day, value: -daysAgo-5, to: Date())!
        
        let goal = Goal(title: title, goalDescription: description, priority: .standard)
        goal.completedDate = completedDate
        goal.status = .completed
        goal.executionStatus = .completed
        goal.startExecutionDate = startDate
        goal.aiComment = "目标完成度很高，对内容进行了全面覆盖。时间管理良好，任务拆分合理。建议下次可以更加具体化每个子任务的完成标准。整体评分: \(score)/5.0"
        
        modelContext.insert(goal)
        
        // 创建并完成所有子任务
        for (index, taskTitle) in subTasks.enumerated() {
            let subTask = SubTask(title: taskTitle)
            subTask.order = index
            subTask.goal = goal
            subTask.isCompleted = true
            subTask.completionDate = calendar.date(byAdding: .hour, value: -(index*12), to: completedDate)
            subTask.estimatedHours = 24
            
            // 创建一个简单的完成证明
            let proofDescription = "已完成\(taskTitle)，达到了预期目标"
            createDummyProof(for: subTask, description: proofDescription)
            
            modelContext.insert(subTask)
        }
        
        try? modelContext.save()
    }
    
    // 创建进行中的目标
    private func createInProgressGoal(title: String, description: String, daysRemaining: Int, progress: Double, subTasks: [String], completedIndices: [Int]) {
        guard let modelContext = modelContext else { return }
        
        let calendar = Calendar.current
        let targetDate = calendar.date(byAdding: .day, value: daysRemaining, to: Date())!
        let startDate = calendar.date(byAdding: .day, value: -5, to: Date())!
        
        let goal = Goal(title: title, goalDescription: description, priority: .standard, targetCompletionDate: targetDate)
        goal.status = .inProgress
        goal.executionStatus = .executing
        goal.startExecutionDate = startDate
        
        modelContext.insert(goal)
        
        // 创建子任务
        for (index, taskTitle) in subTasks.enumerated() {
            let subTask = SubTask(title: taskTitle)
            subTask.order = index
            subTask.goal = goal
            subTask.estimatedHours = 24
            
            // 如果是已完成的子任务
            if completedIndices.contains(index) {
                subTask.isCompleted = true
                subTask.completionDate = calendar.date(byAdding: .day, value: -(completedIndices.count - completedIndices.firstIndex(of: index)!), to: Date())
                
                // 为已完成的子任务创建证明
                let proofDescription = "已完成\(taskTitle)，进展顺利"
                createDummyProof(for: subTask, description: proofDescription)
            }
            
            modelContext.insert(subTask)
        }
        
        try? modelContext.save()
    }
    
    // 创建规划中的目标
    private func createPlanningGoal(title: String, description: String, daysRemaining: Int, subTasks: [String]) {
        guard let modelContext = modelContext else { return }
        
        let calendar = Calendar.current
        let targetDate = calendar.date(byAdding: .day, value: daysRemaining, to: Date())!
        
        let goal = Goal(title: title, goalDescription: description, priority: .standard, targetCompletionDate: targetDate)
        goal.status = .notStarted
        goal.executionStatus = .planning
        
        modelContext.insert(goal)
        
        // 创建子任务
        for (index, taskTitle) in subTasks.enumerated() {
            let subTask = SubTask(title: taskTitle)
            subTask.order = index
            subTask.goal = goal
            subTask.estimatedHours = 24 + (index % 3) * 12 // 变化的预计时间
            
            modelContext.insert(subTask)
        }
        
        try? modelContext.save()
    }
    
    // 创建示例证明
    private func createDummyProof(for subTask: SubTask, description: String) {
        guard let modelContext = modelContext else { return }
        
        // 创建一个简单的占位图片数据
        let dummyImageData = createDummyImage(text: subTask.title)
        
        // 创建证明对象
        let proof = CompletionProof(imagesData: [dummyImageData], description: description, subTask: subTask)
        modelContext.insert(proof)
    }
    
    // 创建带文字的示例图片
    private func createDummyImage(text: String) -> Data {
        let size = CGSize(width: 400, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // 背景
            UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // 边框
            UIColor.lightGray.setStroke()
            let borderRect = CGRect(x: 10, y: 10, width: size.width - 20, height: size.height - 20)
            context.stroke(borderRect)
            
            // 文字
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: paragraphStyle
            ]
            
            let displayText = "任务完成：\(text)"
            let textRect = CGRect(x: 20, y: size.height/2 - 30, width: size.width - 40, height: 60)
            displayText.draw(with: textRect, options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
            
            // 添加日期
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateString = "完成日期: " + dateFormatter.string(from: Date())
            
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.gray,
                .paragraphStyle: paragraphStyle
            ]
            
            let dateRect = CGRect(x: 20, y: size.height - 50, width: size.width - 40, height: 30)
            dateString.draw(with: dateRect, options: .usesLineFragmentOrigin, attributes: dateAttrs, context: nil)
        }
        
        return image.jpegData(compressionQuality: 0.7) ?? Data()
    }
}

// 日期分组结构
struct DateSection: Identifiable {
    var id = UUID()
    var title: String
    var goals: [Goal]
} 