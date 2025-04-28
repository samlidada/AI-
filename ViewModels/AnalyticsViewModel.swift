import Foundation
import SwiftData
import Combine
import SwiftUI

// 时间范围选项
enum TimeRange: String, CaseIterable, Identifiable {
    case week = "周"
    case month = "月"
    case year = "年"
    
    var id: String { self.rawValue }
    
    // 获取时间范围的开始日期
    func startDate(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: date)!
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: date)!
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: date)!
        }
    }
}

// 效率分析数据
struct EfficiencyData {
    var averageCompletionDays: Double = 0
    var estimatedVsActualRatio: Double = 0
    var onTimeCompletionRate: Double = 0
    var overdueRate: Double = 0
    var goalsPerWeek: Double = 0
    var maxGoalGapDays: Int = 0
    var averageGoalGapDays: Double = 0
}

// 个人洞察
struct Insight: Identifiable {
    var id = UUID()
    var title: String
    var description: String
    var icon: String
    var color: Color
}

class AnalyticsViewModel: ObservableObject {
    @Published var efficiencyData: EfficiencyData = EfficiencyData()
    @Published var personalInsights: [Insight] = []
    @Published var totalGoals: Int = 0
    @Published var completedGoals: Int = 0
    @Published var overdueGoals: Int = 0
    @Published var activeGoals: Int = 0
    @Published var averageTimeToComplete: String = "0天"
    @Published var mostProductiveDay: String = "无数据"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private var modelContext: ModelContext?
    
    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }
    
    // 设置模型上下文
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadAnalyticsData()
    }
    
    // 加载分析数据
    func loadAnalyticsData(for timeRange: TimeRange = .month) {
        guard let modelContext = modelContext else { return }
        
        isLoading = true
        errorMessage = nil
        
        // 获取指定时间范围内的目标
        let startDate = timeRange.startDate()
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate<Goal> {
            $0.createdDate >= startDate
        })
        
        do {
            let goals = try modelContext.fetch(descriptor)
            processGoalsData(goals, timeRange: timeRange)
            generateInsights(from: goals)
            isLoading = false
        } catch {
            errorMessage = "加载数据失败：\(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // 处理目标数据
    private func processGoalsData(_ goals: [Goal], timeRange: TimeRange) {
        // 计算基本统计数据
        totalGoals = goals.count
        completedGoals = goals.filter { $0.status == .completed }.count
        overdueGoals = goals.filter { $0.status == .overdue }.count
        activeGoals = goals.filter { $0.status == .inProgress }.count
        
        // 计算完成目标的平均天数
        let completedGoalsWithDates = goals.filter { 
            $0.status == .completed && $0.completedDate != nil && $0.createdDate < $0.completedDate! 
        }
        
        if !completedGoalsWithDates.isEmpty {
            let totalDays = completedGoalsWithDates.reduce(0.0) { result, goal in
                let days = Calendar.current.dateComponents([.day], from: goal.createdDate, to: goal.completedDate!).day ?? 0
                return result + Double(days)
            }
            let avgDays = totalDays / Double(completedGoalsWithDates.count)
            averageTimeToComplete = String(format: "%.1f天", avgDays)
            efficiencyData.averageCompletionDays = avgDays
        }
        
        // 计算完成效率
        if totalGoals > 0 {
            efficiencyData.onTimeCompletionRate = Double(completedGoals) / Double(totalGoals)
            efficiencyData.overdueRate = Double(overdueGoals) / Double(totalGoals)
        }
        
        // 计算目标创建频率
        let startDate = timeRange.startDate()
        let daysSinceStart = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 1
        if daysSinceStart > 0 {
            let weeksCount = Double(daysSinceStart) / 7.0
            efficiencyData.goalsPerWeek = Double(totalGoals) / weeksCount
        }
        
        // 计算目标创建间隔
        if goals.count > 1 {
            // 按创建日期排序
            let sortedGoals = goals.sorted { $0.createdDate < $1.createdDate }
            var gapDays: [Int] = []
            
            // 计算相邻目标之间的间隔天数
            for i in 0..<sortedGoals.count-1 {
                let days = Calendar.current.dateComponents([.day], from: sortedGoals[i].createdDate, to: sortedGoals[i+1].createdDate).day ?? 0
                gapDays.append(days)
            }
            
            if !gapDays.isEmpty {
                efficiencyData.maxGoalGapDays = gapDays.max() ?? 0
                efficiencyData.averageGoalGapDays = Double(gapDays.reduce(0, +)) / Double(gapDays.count)
            }
        }
        
        // 计算估计时间与实际时间的比率
        calculateEstimatedVsActualRatio(goals)
    }
    
    // 计算估计时间与实际时间的比率
    private func calculateEstimatedVsActualRatio(_ goals: [Goal]) {
        // 找出已完成且有子任务的目标
        let goalsWithSubtasks = goals.filter { 
            $0.executionStatus == .completed && 
            !$0.subTasks.isEmpty && 
            $0.completedDate != nil && 
            $0.startExecutionDate != nil 
        }
        
        if goalsWithSubtasks.isEmpty {
            efficiencyData.estimatedVsActualRatio = 1.0
            return
        }
        
        var totalEstimatedDays = 0.0
        var totalActualDays = 0.0
        
        for goal in goalsWithSubtasks {
            // 计算估计总天数
            let estimatedDays = goal.subTasks.reduce(0.0) { $0 + Double($1.estimatedHours) / 24.0 }
            
            // 计算实际天数
            if let startDate = goal.startExecutionDate, let endDate = goal.completedDate {
                let actualDays = Calendar.current.dateComponents([.day, .hour], from: startDate, to: endDate)
                let days = Double(actualDays.day ?? 0)
                let hours = Double(actualDays.hour ?? 0) / 24.0 // 转换小时为天的小数部分
                totalActualDays += days + hours
            }
            
            totalEstimatedDays += estimatedDays
        }
        
        if totalEstimatedDays > 0 {
            efficiencyData.estimatedVsActualRatio = totalActualDays / totalEstimatedDays
        } else {
            efficiencyData.estimatedVsActualRatio = 1.0
        }
    }
    
    // 生成个人洞察
    private func generateInsights(from goals: [Goal]) {
        var insights: [Insight] = []
        
        // 洞察1：完成率
        if totalGoals > 0 {
            let completionRate = Double(completedGoals) / Double(totalGoals) * 100
            var completionInsight: Insight
            
            if completionRate >= 80 {
                completionInsight = Insight(
                    title: "目标完成率极高",
                    description: "您的目标完成率达到了\(Int(completionRate))%，这是非常优秀的成绩！继续保持！",
                    icon: "star.fill",
                    color: .yellow
                )
            } else if completionRate >= 50 {
                completionInsight = Insight(
                    title: "目标完成率良好",
                    description: "您完成了\(Int(completionRate))%的目标，表现不错，还有提升空间。",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            } else {
                completionInsight = Insight(
                    title: "目标完成率需提高",
                    description: "您的目标完成率为\(Int(completionRate))%，建议设置更合理的目标或提高执行力。",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
            
            insights.append(completionInsight)
        }
        
        // 洞察2：时间管理
        if efficiencyData.estimatedVsActualRatio > 0 {
            let ratio = efficiencyData.estimatedVsActualRatio
            var timeInsight: Insight
            
            if ratio <= 1.1 {
                timeInsight = Insight(
                    title: "时间估计非常准确",
                    description: "您对任务时间的估计与实际执行时间非常接近，说明您对自己的能力有很好的认识。",
                    icon: "clock.fill",
                    color: .green
                )
            } else if ratio <= 1.5 {
                timeInsight = Insight(
                    title: "时间估计略有偏差",
                    description: "您的任务实际完成时间比估计时间平均长\(Int((ratio - 1) * 100))%，建议适当调整时间预估。",
                    icon: "clock.badge.exclamationmark.fill",
                    color: .blue
                )
            } else {
                timeInsight = Insight(
                    title: "时间估计偏差较大",
                    description: "您的任务实际完成时间比估计时间平均长\(Int((ratio - 1) * 100))%，建议更谨慎地评估任务难度。",
                    icon: "exclamationmark.arrow.circlepath",
                    color: .orange
                )
            }
            
            insights.append(timeInsight)
        }
        
        // 洞察3：目标创建频率
        if efficiencyData.goalsPerWeek > 0 {
            var frequencyInsight: Insight
            
            if efficiencyData.goalsPerWeek >= 3 {
                frequencyInsight = Insight(
                    title: "目标创建频率较高",
                    description: "您平均每周创建\(String(format: "%.1f", efficiencyData.goalsPerWeek))个目标，确保目标质量和完成度也同样重要。",
                    icon: "bolt.fill",
                    color: .yellow
                )
            } else if efficiencyData.goalsPerWeek >= 1 {
                frequencyInsight = Insight(
                    title: "目标创建频率适中",
                    description: "您平均每周创建\(String(format: "%.1f", efficiencyData.goalsPerWeek))个目标，这是一个比较合理的节奏。",
                    icon: "calendar.badge.plus",
                    color: .green
                )
            } else {
                frequencyInsight = Insight(
                    title: "目标创建频率较低",
                    description: "您平均每周只创建\(String(format: "%.1f", efficiencyData.goalsPerWeek))个目标，可以尝试设立更多小目标来保持动力。",
                    icon: "calendar",
                    color: .blue
            )
            }
            
            insights.append(frequencyInsight)
        }
        
        // 洞察4：目标创建间隔
        if efficiencyData.maxGoalGapDays > 0 && goals.count > 1 {
            var gapInsight: Insight
            
            if efficiencyData.maxGoalGapDays >= 30 {
                gapInsight = Insight(
                    title: "目标间隔需要注意",
                    description: "您曾有\(efficiencyData.maxGoalGapDays)天没有创建新目标，持续的目标设定能帮助保持前进动力。",
                    icon: "exclamationmark.circle",
                    color: .orange
                )
            } else if efficiencyData.maxGoalGapDays >= 14 {
                gapInsight = Insight(
                    title: "目标设定有间断期",
                    description: "您最长\(efficiencyData.maxGoalGapDays)天没有创建新目标，保持稳定的目标设定习惯有助于进步。",
                    icon: "calendar.badge.exclamationmark",
                color: .blue
            )
            } else {
                gapInsight = Insight(
                    title: "目标设定非常稳定",
                    description: "您能保持稳定的目标设定频率，最长间隔仅\(efficiencyData.maxGoalGapDays)天，这是很好的习惯！",
                    icon: "calendar.badge.checkmark",
                    color: .green
                )
            }
            
            insights.append(gapInsight)
        }
        
        personalInsights = insights
    }
    
    // 获取最多产日
    private func findMostProductiveDay(_ goals: [Goal]) -> String {
        let calendar = Calendar.current
        var dayCount: [Int: Int] = [:]  // [weekday: count]
        
        for goal in goals {
            if goal.status == .completed, let completedDate = goal.completedDate {
                let weekday = calendar.component(.weekday, from: completedDate)
                dayCount[weekday, default: 0] += 1
            }
        }
        
        if let (mostProductiveDay, _) = dayCount.max(by: { $0.value < $1.value }) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.weekdaySymbols = ["", "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
            return formatter.weekdaySymbols[mostProductiveDay]
        }
        
        return "无数据"
    }
} 