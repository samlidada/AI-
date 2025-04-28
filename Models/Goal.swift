import Foundation
import SwiftData

enum GoalStatus: String, Codable {
    case notStarted = "未开始"
    case inProgress = "进行中"
    case completed = "已完成"
    case overdue = "未按时完成"
}

// 完全重新设计优先级枚举，不再使用high/medium/low
enum GoalPriority: String, Codable, CaseIterable {
    case standard = "标准"  // 使用全新的命名，避免与旧数据库中的值冲突
    
    // 添加便捷解码方法，处理历史数据
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let _ = try container.decode(String.self)  // 使用 _ 忽略解码值
            // 无论是什么旧值，都统一转为标准优先级
            self = .standard
        } catch {
            // 如果解码失败，使用默认值
            self = .standard
        }
    }
}

// 将 GoalExecutionStatus 枚举直接定义在这里
enum GoalExecutionStatus: String, Codable {
    case planning = "规划中"    // 初始状态，可编辑
    case executing = "执行中"   // 锁定，可上传成果
    case evaluating = "评估中"  // AI评估阶段
    case completed = "已完成"   // 全部完成并评估
}

@Model
class Goal {
    var id: UUID
    var title: String
    var goalDescription: String
    var createdDate: Date
    var targetCompletionDate: Date?
    var completedDate: Date?
    var status: GoalStatus
    var priority: GoalPriority
    
    // 新增执行相关属性
    var executionStatus: GoalExecutionStatus = GoalExecutionStatus.planning
    var isLocked: Bool = false
    var startExecutionDate: Date?
    var aiComment: String?
    
    // 计时相关属性
    var finalRemainingSeconds: Int? = nil // 完成时的剩余秒数
    var finalTimeDisplay: String? = nil // 完成时的时间显示
    
    init(title: String, goalDescription: String = "", priority: GoalPriority = .standard, targetCompletionDate: Date? = nil) {
        self.id = UUID()
        self.title = title
        self.goalDescription = goalDescription
        self.priority = priority
        self.createdDate = Date()
        self.targetCompletionDate = targetCompletionDate
        self.completedDate = nil
        self.status = .notStarted
        self.executionStatus = GoalExecutionStatus.planning
        self.isLocked = false
    }
    
    var isCompleted: Bool {
        return status == .completed
    }
    
    var isOverdue: Bool {
        if let targetDate = targetCompletionDate, !isCompleted {
            return Date() > targetDate
        }
        return false
    }
    
    var daysRemaining: Int? {
        guard let targetDate = targetCompletionDate, !isCompleted else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: targetDate)
        return components.day
    }
    
    func updateStatus() {
        if let targetDate = targetCompletionDate {
            if completedDate != nil {
                status = .completed
            } else if Date() > targetDate {
                status = .overdue
            } else {
                status = .inProgress
            }
        }
    }
    
    func markAsCompleted() {
        self.completedDate = Date()
        self.status = .completed
    }
    
    // 新增方法：开始执行目标
    func startExecution() {
        self.executionStatus = GoalExecutionStatus.executing
        self.isLocked = true
        self.startExecutionDate = Date()
        if self.status == .notStarted {
            self.status = .inProgress
        }
    }
    
    // 新增方法：完成目标并进入评估阶段
    func finishExecution() {
        self.executionStatus = GoalExecutionStatus.evaluating
    }
    
    // 新增方法：设置AI评估结果
    func setEvaluation(comment: String) {
        self.aiComment = comment
        self.executionStatus = GoalExecutionStatus.completed
        
        // 如果有任何子任务超时未完成，整个目标状态为"未按时完成"
        if hasOverdueSubTasks {
            self.status = .overdue
            self.completedDate = Date() // 仍然设置完成日期以便记录
        } else if allSubTasksCompleted {
            // 所有子任务正常完成，标记为已完成
            self.completedDate = Date()
            self.status = .completed
        } else {
            // 其他情况（理论上不应该发生）
            self.status = .overdue
        }
    }
    
    // 添加关系
    @Relationship(deleteRule: .cascade)
    var subTasks: [SubTask] = []

    // 添加便利方法
    var completedSubTasksCount: Int {
        return subTasks.filter { $0.isCompleted }.count
    }

    var subTasksProgress: Double {
        guard !subTasks.isEmpty else { return 0 }
        return Double(completedSubTasksCount) / Double(subTasks.count)
    }
    
    // 检查是否所有子任务都已完成
    var allSubTasksCompleted: Bool {
        guard !subTasks.isEmpty else { return false }
        return completedSubTasksCount == subTasks.count
    }
    
    // 新增：检查是否有超时未完成的子任务
    var hasOverdueSubTasks: Bool {
        return subTasks.contains { $0.isOverdue }
    }
    
    // 新增：检查是否所有子任务都已处理（完成或超时）
    var allSubTasksProcessed: Bool {
        guard !subTasks.isEmpty else { return false }
        return subTasks.allSatisfy { $0.isCompleted || $0.isOverdue }
    }
}
