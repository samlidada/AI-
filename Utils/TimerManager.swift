import Foundation
import Combine
import SwiftData
import UIKit

class TimerManager: ObservableObject {
    // 单例模式
    static let shared = TimerManager()
    
    // 公开属性
    @Published var isRunning: Bool = false
    
    // 用于通知订阅者定时器更新
    private let timerSubject = PassthroughSubject<Date, Never>()
    var timerPublisher: AnyPublisher<Date, Never> {
        return timerSubject.eraseToAnyPublisher()
    }
    
    // 后台任务标识符
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    // 管理中的目标ID
    private var managingGoalIDs: Set<UUID> = []
    
    // 定时器
    private var timer: Timer?
    
    // UserDefaults键
    private let lastUpdateTimeKey = "TimerManager.lastUpdateTime"
    private let managingGoalIDsKey = "TimerManager.managingGoalIDs"
    
    // 新增：目标特定的最后更新时间字典
    private var goalLastUpdateTimes: [UUID: Date] = [:]
    
    private init() {
        // 从UserDefaults恢复状态
        restoreState()
        
        // 注册应用程序生命周期通知
        registerForAppLifecycleNotifications()
        
        // 如果有管理中的目标，启动定时器
        if !managingGoalIDs.isEmpty {
            startTimer()
        }
    }
    
    // 添加目标到管理中
    func startManaging(goalID: UUID) {
        managingGoalIDs.insert(goalID)
        
        // 为目标设置特定的开始时间
        goalLastUpdateTimes[goalID] = Date()
        
        saveState()
        
        if !isRunning {
            startTimer()
        }
    }
    
    // 停止管理目标
    func stopManaging(goalID: UUID) {
        managingGoalIDs.remove(goalID)
        
        // 移除目标特定的最后更新时间
        goalLastUpdateTimes.removeValue(forKey: goalID)
        
        saveState()
        
        if managingGoalIDs.isEmpty && isRunning {
            stopTimer()
        }
    }
    
    // 获取当前管理的目标ID列表
    func getManagedGoalIDs() -> [UUID] {
        return Array(managingGoalIDs)
    }
    
    // 更新目标的倒计时状态
    func updateGoalsTimerState(modelContext: ModelContext) {
        let now = Date()
        
        // 为每个目标单独计算经过的时间
        for goalID in managingGoalIDs {
            if let lastUpdateTime = goalLastUpdateTimes[goalID] {
                // 计算经过的时间（秒）
                let elapsedSeconds = Int(now.timeIntervalSince(lastUpdateTime))
                
                if elapsedSeconds > 0 {
                    // 更新特定目标的倒计时
                    updateGoalTimer(modelContext: modelContext, goalID: goalID, elapsedSeconds: elapsedSeconds)
                    
                    // 更新目标的最后更新时间
                    goalLastUpdateTimes[goalID] = now
                }
            } else {
                // 如果没有记录，设置当前时间
                goalLastUpdateTimes[goalID] = now
            }
        }
        
        // 保存更改后的状态
        saveState()
    }
    
    // MARK: - 私有方法
    
    private func startTimer() {
        // 如果定时器已经在运行，先停止
        stopTimer()
        
        // 创建新定时器
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            self.timerSubject.send(now)
        }
        
        if let timer = timer {
            // 确保定时器在滚动等操作时也能触发
            RunLoop.current.add(timer, forMode: .common)
        }
        
        isRunning = true
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    private func saveState() {
        // 保存管理中的目标ID
        let goalIDStrings = managingGoalIDs.map { $0.uuidString }
        UserDefaults.standard.set(goalIDStrings, forKey: managingGoalIDsKey)
        
        // 保存目标特定的最后更新时间
        let goalTimesDict = Dictionary(uniqueKeysWithValues: goalLastUpdateTimes.map { 
            ($0.key.uuidString, $0.value.timeIntervalSince1970) 
        })
        UserDefaults.standard.set(goalTimesDict, forKey: "TimerManager.goalLastUpdateTimes")
    }
    
    private func restoreState() {
        // 恢复管理中的目标ID
        if let goalIDStrings = UserDefaults.standard.stringArray(forKey: managingGoalIDsKey) {
            managingGoalIDs = Set(goalIDStrings.compactMap { UUID(uuidString: $0) })
        }
        
        // 恢复目标特定的最后更新时间
        if let goalTimesDict = UserDefaults.standard.dictionary(forKey: "TimerManager.goalLastUpdateTimes") as? [String: TimeInterval] {
            goalLastUpdateTimes = Dictionary(uniqueKeysWithValues: goalTimesDict.compactMap { 
                if let uuid = UUID(uuidString: $0.key) {
                    return (uuid, Date(timeIntervalSince1970: $0.value))
                }
                return nil
            })
        }
    }
    
    // 更新特定目标的计时器状态
    private func updateGoalTimer(modelContext: ModelContext, goalID: UUID, elapsedSeconds: Int) {
        // 使用 ModelContext 获取目标
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate<Goal> { goal in
            goal.id == goalID
        })
        
        do {
            if let goal = try modelContext.fetch(descriptor).first {
                // 检查目标是否在执行阶段
                if goal.executionStatus == .executing {
                    // 更新目标相关的计时器状态
                    updateGoalTimerState(goal: goal, elapsedSeconds: elapsedSeconds, modelContext: modelContext)
                } else {
                    // 如果目标不再是执行阶段，从管理列表中移除
                    managingGoalIDs.remove(goalID)
                    goalLastUpdateTimes.removeValue(forKey: goalID)
                }
            } else {
                // 目标不存在，从管理列表中移除
                managingGoalIDs.remove(goalID)
                goalLastUpdateTimes.removeValue(forKey: goalID)
            }
        } catch {
            print("获取目标失败: \(error)")
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存倒计时状态失败: \(error)")
        }
    }
    
    // 更新所有目标的计时器，已不再使用
    private func updateGoalsTimers(modelContext: ModelContext, elapsedSeconds: Int) {
        // 此方法已被重构，保留为兼容性考虑
        // 具体逻辑已迁移到 updateGoalTimer 方法
    }
    
    private func updateGoalTimerState(goal: Goal, elapsedSeconds: Int, modelContext: ModelContext) {
        // 首先找到当前执行的子任务（未完成的第一个子任务）
        let uncompletedSubTasks = goal.subTasks
            .filter { !$0.isCompleted && !$0.isOverdue } // 过滤掉已完成和已超时的子任务
            .sorted(by: { $0.order < $1.order })
        
        if let currentSubTask = uncompletedSubTasks.first {
            // 获取或创建子任务的剩余时间记录
            if currentSubTask.remainingSecondsForTimer == nil {
                // 初始化剩余时间（小时转换为秒）
                currentSubTask.remainingSecondsForTimer = currentSubTask.estimatedHours * 60 * 60
            }
            
            // 减少剩余时间
            if var remainingSeconds = currentSubTask.remainingSecondsForTimer, remainingSeconds > 0 {
                let secondsToDeduct = min(remainingSeconds, elapsedSeconds)
                remainingSeconds -= secondsToDeduct
                currentSubTask.remainingSecondsForTimer = remainingSeconds
                
                // 如果时间到了，标记为超时未完成
                if remainingSeconds <= 0 {
                    // 重要：记录完成时的剩余时间为0
                    currentSubTask.remainingTimeWhenCompleted = 0
                    
                    // 标记为超时未完成
                    currentSubTask.markAsOverdue()
                    
                    // 继续处理下一个子任务（递归调用）
                    // 如果有未使用的时间，传递给下一个任务处理
                    let unusedSeconds = elapsedSeconds - secondsToDeduct
                    if unusedSeconds > 0 {
                        updateGoalTimerState(goal: goal, elapsedSeconds: unusedSeconds, modelContext: modelContext)
                    } else {
                        // 没有未使用的时间，仍然需要调用以确保下一个任务初始化
                        updateGoalTimerState(goal: goal, elapsedSeconds: 0, modelContext: modelContext)
                    }
                }
            }
        } else if goal.allSubTasksProcessed {
            // 只有当所有子任务都已处理（完成或超时）时，才结束目标执行
            goal.finishExecution()
            
            // 从管理列表中移除
            managingGoalIDs.remove(goal.id)
            goalLastUpdateTimes.removeValue(forKey: goal.id)
        }
    }
    
    private func registerForAppLifecycleNotifications() {
        // 注册应用进入后台通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        // 注册应用将要终止通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // 注册应用将要进入前台通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func applicationDidEnterBackground() {
        // 保存当前状态
        saveState()
        
        // 开始后台任务
        beginBackgroundTask()
    }
    
    @objc private func applicationWillTerminate() {
        // 保存当前状态
        saveState()
        
        // 结束后台任务
        endBackgroundTask()
    }
    
    @objc private func applicationWillEnterForeground() {
        // 结束后台任务
        endBackgroundTask()
        
        // 如果有管理中的目标，重启定时器
        if !managingGoalIDs.isEmpty && !isRunning {
            startTimer()
        }
    }
    
    private func beginBackgroundTask() {
        // 结束已有的后台任务
        endBackgroundTask()
        
        // 开始新的后台任务
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TimerManagerBackgroundTask") {
            // 到达时间限制时自动结束任务
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
} 