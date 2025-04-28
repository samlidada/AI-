//
//  SubTask.swift
//  Project
//
//  Created by 李大大 on 2025/4/4.
//

import Foundation
import SwiftData

@Model
class SubTask {
    var id: UUID
    var title: String
    var note: String?
    var deadline: Date?
    var priority: Int
    var isCompleted: Bool
    var creationDate: Date
    var completionDate: Date?
    
    // 添加缺失属性
    var order: Int = 0
    var estimatedHours: Int = 24 // 将天改为小时，默认是1天（24小时）
    var remainingSecondsForTimer: Int?
    var remainingTimeWhenCompleted: Int?
    
    // 与 CompletionProof 的关系，使用新的关系宏声明
    @Relationship(deleteRule: .cascade)
    var completionProof: CompletionProof?
    
    // 任务是否已过期
    var isOverdue: Bool = false
    
    // 是否有完成证明
    var hasProofs: Bool {
        return completionProof != nil
    }
    
    @Relationship(deleteRule: .nullify, inverse: \Goal.subTasks)
    var goal: Goal?
    
    init(title: String, note: String? = nil, deadline: Date? = nil, priority: Int = 0, isCompleted: Bool = false) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.deadline = deadline
        self.priority = priority
        self.isCompleted = isCompleted
        self.creationDate = Date()
    }
    
    // 标记为已完成
    func markAsCompleted() {
        self.isCompleted = true
        self.completionDate = Date()
    }
    
    // 标记为未完成
    func markAsIncomplete() {
        self.isCompleted = false
        self.completionDate = nil
        self.isOverdue = false
    }
    
    // 标记为已过期
    func markAsOverdue() {
        self.isCompleted = false
        self.completionDate = nil
        self.isOverdue = true
    }
}
