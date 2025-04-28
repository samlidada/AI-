import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import UIKit
import Combine

// 定义通知名称常量
extension Notification.Name {
    static let resetDragStates = Notification.Name("resetDragStates")
}

// 添加View扩展，支持if条件修饰
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// 加载类型枚举
enum LoadingType {
    case analyzing   // AI分析目标
    case evaluating  // AI评估目标
    
    var message: String {
        switch self {
        case .analyzing:
            return "AI正在分析您的目标..."
        case .evaluating:
            return "AI正在对整个目标进行评分..."
        }
    }
}

struct GoalDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var timerManager: TimerManager
    @ObservedObject var viewModel: GoalViewModel
    let goal: Goal
    
    @State private var showingAddSubTask = false
    @State private var newSubTaskTitle = ""
    @State private var showingRefreshSolution = false
    @State private var isLoading = false
    @State private var loadingType: LoadingType = .analyzing // 添加加载类型状态
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showingEditGoal = false
    @State private var isEditMode = false // 编辑模式状态
    @State private var showSubTasks = false // 控制是否显示子任务列表
    @State private var showConfirmStartExecution = false // 确认开始执行的弹窗
    @State private var editingSubTask: SubTask? // 正在编辑的子任务
    @State private var showEditSubTaskSheet = false // 控制编辑子任务的表单显示
    @State private var tempSubTaskTitle = "" // 临时存储编辑中的子任务标题
    @State private var tempSubTaskHours = 24 // 临时存储编辑中的子任务预计小时数（默认1天）
    @State private var draggingSubTaskID: UUID? = nil // 正在拖动的子任务ID
    
    // 执行页面相关状态变量
    @State private var selectedSubTask: SubTask? // 选中的子任务用于上传证明
    @State private var selectedPhotos: [PhotosPickerItem] = [] // 选中的多张照片
    @State private var selectedImagesData: [Data] = [] // 选中的多张照片数据
    @State private var proofDescription: String = "" // 证明描述
    @State private var showingUploadSheet = false // 控制上传表单显示
    @State private var isSubmitting = false // 提交状态
    
    // 当前执行子任务相关变量
    @State private var currentExecutingSubTask: SubTask? // 当前正在执行的子任务
    @State private var subTaskRemainingSeconds: Int = 0 // 当前子任务剩余秒数
    
    // 倒计时相关变量
    @State private var remainingSeconds: Int = 0
    @State private var timerSubscription: AnyCancellable?
    
    // 分享相关状态
    @State private var isShareSheetPresenting = false
    @State private var shareButtonRect: CGRect = .zero
    
    // 计算目标进度百分比
    private var progressPercentage: Int {
        let progress = goal.subTasksProgress * 100
        return Int(progress)
    }
    
    // 计算完成总目标所需时间（天）
    private var totalEstimatedDays: Int {
        return goal.subTasks.reduce(0) { sum, task in 
            return sum + task.estimatedHours 
        } / 24
    }
    
    // 判断是否处于执行阶段
    private var isExecutingPhase: Bool {
        return goal.executionStatus == .executing
    }
    
    // 判断是否处于评估或已完成阶段
    private var isEvaluatingOrCompleted: Bool {
        return goal.executionStatus == .evaluating || goal.executionStatus == .completed
    }
    
    // 判断是否显示总倒计时器(一小时以上都显示)
    private var shouldShowCountdown: Bool {
        let totalHours = goal.subTasks.reduce(0) { sum, task in 
            return sum + task.estimatedHours 
        }
        // 只要总预计时间大于等于1小时就显示
        return (isExecutingPhase || isEvaluatingOrCompleted) && totalHours >= 1
    }
    
    // 插入动画
    private var insertionTransition: AnyTransition {
        let insertion = AnyTransition.move(edge: .top).combined(with: .opacity)
        let removal = AnyTransition.move(edge: .bottom).combined(with: .opacity)
        
        return AnyTransition.asymmetric(
            insertion: insertion.animation(.spring(response: 0.4, dampingFraction: 0.6)),
            removal: removal.animation(.spring(response: 0.4, dampingFraction: 0.7))
        )
    }
    
    // 确认对话框状态
    @State private var showingConfirmationDialog = false
    @State private var confirmationTitle = ""
    @State private var confirmationMessage = ""
    @State private var confirmationAction: (() -> Void)? = nil
    
    // 添加新的状态变量来跟踪API错误
    @State private var showAPIError = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 目标头部信息
                goalHeader
                
                // 智能分解按钮或子任务列表
                if !showSubTasks && goal.subTasks.isEmpty {
                    // 智能分解按钮区域
                    VStack(spacing: 15) {
                        if showAPIError {
                            // 显示错误状态UI - 优化居中效果
                            VStack(spacing: 12) {
                                // 错误图标
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 28))
                                    .foregroundColor(.orange)
                                    .padding(.bottom, 4)
                                
                                Text("服务器无响应")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                                
                                if AIGoalAnalysisService.shared.hasReachedMaxAttempts(for: goal) {
                                    // 如果达到最大尝试次数，显示"请稍后再试"
                                    Text("请稍后再试")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .padding(.top, 2)
                                } else {
                                    // 否则显示刷新按钮
                                    Button(action: {
                                        generateAIAnalysis()
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 14))
                                            Text("刷新")
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .padding(.horizontal, 22)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                        .foregroundColor(.blue)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .padding(.top, 4)
                                }
                            }
                            .padding(.vertical, 24)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity) // 确保整个容器占据全宽
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                            )
                        } else {
                            Button(action: {
                                generateAIAnalysis()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "wand.and.stars.inverse")
                                        .font(.system(size: 18, weight: .medium))
                                    Text("智能分解")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(25)
                                .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 3)
                            }
                            .disabled(isLoading)
                            .buttonStyle(ScaleButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                } else if !goal.subTasks.isEmpty {
                    // 显示子任务列表
                    subTasksListView
                    
                    // 执行阶段按钮
                    executionPhaseButtons
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.3), value: isLoading)
            .animation(.easeInOut(duration: 0.3), value: showSubTasks)
            .onChange(of: goal.subTasks.count) { oldValue, newValue in
                if newValue > 0 && !showSubTasks {
                    showSubTasks = true
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("大目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 添加分享按钮到导航栏右侧，仅在目标已完成时显示
            if goal.isCompleted {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // 打开分享表单
                        shareGoal()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .background(
                        GeometryReader { geometry -> Color in
                            DispatchQueue.main.async {
                                // 保存按钮位置，用于iPad分享弹窗定位
                                shareButtonRect = geometry.frame(in: .global)
                            }
                            return Color.clear
                        }
                    )
                }
            }
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        }
        .alert(confirmationTitle, isPresented: $showingConfirmationDialog) {
            Button("取消", role: .cancel) { }
            Button("确定", role: .destructive) {
                confirmationAction?()
            }
        } message: {
            Text(confirmationMessage)
        }
        .alert("刷新AI方案", isPresented: $showingRefreshSolution) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                refreshAIAnalysis()
            }
        } message: {
            Text("确定要刷新AI分析方案吗？这将替换现有的子任务。")
        }
        .alert("开始执行目标", isPresented: $showConfirmStartExecution) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                startExecution()
            }
        } message: {
            Text("开始执行后，目标内容将被锁定无法编辑。确定要开始执行吗？")
        }
        .sheet(isPresented: $showingUploadSheet) {
            uploadProofView
        }
        .overlay {
            if showingAddSubTask {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showingAddSubTask = false
                            newSubTaskTitle = ""
                            tempSubTaskHours = 24
                        }
                    }
                
                addSubTaskView
                    .frame(width: UIScreen.main.bounds.width * 0.9)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .overlay {
            if showEditSubTaskSheet {
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showEditSubTaskSheet = false
                            editingSubTask = nil
                        }
                    }
                
                editSubTaskView
                    .frame(width: UIScreen.main.bounds.width * 0.9)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }
        // 添加LoadingView到全局overlay中
        .overlay {
            if isLoading {
                ZStack {
                    // 半透明背景遮罩
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                    
                    // 加载提示
                    LoadingView(text: loadingType.message)
                        .frame(width: UIScreen.main.bounds.width * 0.8)
                        .transition(.scale.combined(with: .opacity))
                }
                .zIndex(100)  // 确保总是在最顶层
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingAddSubTask)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showEditSubTaskSheet)
        .onAppear {
            // 检查目标状态，更新UI显示
            if !goal.subTasks.isEmpty {
                showSubTasks = true
            }
            
            // 如果已经在执行阶段，恢复倒计时状态
            if isExecutingPhase {
                // 从TimerManager更新状态
                if !timerManager.getManagedGoalIDs().contains(goal.id) {
                    timerManager.startManaging(goalID: goal.id)
                }
                
                // 更新倒计时状态
                updateCountdownState()
                
                // 订阅定时器更新
                timerSubscription = timerManager.timerPublisher
                    .sink { [self] _ in
                        self.updateCountdownState()
                    }
            }
            
            // 检查是否是一个评估中但没有AI评语的目标
            if goal.executionStatus == .evaluating && goal.aiComment == nil && !isLoading && !showAPIError {
                // 自动尝试获取AI评估
                loadingType = .evaluating
                isLoading = true
                
                // 触发AI评估
                AIGoalAnalysisService.shared.evaluateGoal(goal) { comment in
                    // 关闭加载状态
                    self.isLoading = false
                    
                    if comment == "服务器无响应，请刷新。" {
                        // 服务器请求失败，显示错误UI
                        self.showAPIError = true
                    } else {
                        // 设置评估结果
                        self.viewModel.setGoalEvaluation(self.goal, comment: comment)
                    }
                }
            }
        }
        .onDisappear {
            // 取消定时器订阅
            timerSubscription?.cancel()
            timerSubscription = nil
        }
    }
    
    // 分享目标
    private func shareGoal() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        
        var currentVC = rootVC
        while let presentedVC = currentVC.presentedViewController {
            currentVC = presentedVC
        }
        
        // 获取是否登录状态和用户信息
        let isUserLoggedIn = UserManager.shared.isLoggedIn
        let userName = UserManager.shared.displayName
        
        // 获取当前视图中的分享按钮位置用于iPad弹窗定位
        ShareImageGenerator.sharePoster(
            isUserLoggedIn: isUserLoggedIn,
            userName: userName.isEmpty ? "目标达人" : userName,
            userAvatar: nil, // 使用默认头像或Logo
            goal: goal,      // 直接传递整个目标对象
            contentView: nil, // 不使用自定义内容视图，让SharePosterView处理
            from: shareButtonRect,
            in: currentVC.view
        ) {
            // 分享完成后的回调
            isShareSheetPresenting = false
            
            // 显示成功提示
            alertMessage = "分享图片已生成"
            showAlert = true
        }
        
        isShareSheetPresenting = true
    }
    
    // 日期和时间格式化
    
    // 添加子任务视图
    private var addSubTaskView: some View {
        VStack(spacing: 15) {
            // 顶部取消和确认按钮
            HStack {
                Button("取消") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingAddSubTask = false
                        newSubTaskTitle = ""
                        tempSubTaskHours = 24
                    }
                }
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("保存") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        saveNewSubTask()
                    }
                }
                .disabled(newSubTaskTitle.isEmpty)
                .foregroundColor(newSubTaskTitle.isEmpty ? .gray : .blue)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            
            Divider()
                .padding(.vertical, 10)
            
            // 任务标题输入
            TextField("", text: $newSubTaskTitle)
                .font(.system(size: 17))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .overlay(
                    Group {
                        if newSubTaskTitle.isEmpty {
                            Text("输入子任务内容...")
                                .foregroundColor(.gray.opacity(0.7))
                                .padding(.leading, 36)
                                .padding(.top, 17)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                        }
                    }
                )
            
            // 预计小时数
            HStack(spacing: 0) {
                Text("预计完成小时数")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: {
                        if tempSubTaskHours > 24 {
                            tempSubTaskHours -= 24
                        }
                    }) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    Text("\(tempSubTaskHours)")
                        .font(.system(size: 18, weight: .medium))
                        .frame(minWidth: 30)
                    
                    Button(action: {
                        if tempSubTaskHours < 72 {
                            tempSubTaskHours += 24
                        }
                    }) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
        }
        .frame(height: 220)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
    
    // 编辑子任务视图
    private var editSubTaskView: some View {
        VStack(spacing: 15) {
            // 顶部取消和确认按钮
            HStack {
                Button("取消") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showEditSubTaskSheet = false
                        editingSubTask = nil
                    }
                }
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("保存") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        saveEditedSubTask()
                    }
                }
                .disabled(tempSubTaskTitle.isEmpty)
                .foregroundColor(tempSubTaskTitle.isEmpty ? .gray : .blue)
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            
            Divider()
                .padding(.vertical, 10)
            
            // 任务标题输入
            TextField("", text: $tempSubTaskTitle)
                .font(.system(size: 17))
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 20)
                .overlay(
                    Group {
                        if tempSubTaskTitle.isEmpty {
                            Text("编辑子任务内容...")
                                .foregroundColor(.gray.opacity(0.7))
                                .padding(.leading, 36)
                                .padding(.top, 17)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .allowsHitTesting(false)
                        }
                    }
                )
            
            // 预计小时数
            HStack(spacing: 0) {
                Text("预计完成小时数")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button(action: {
                        if tempSubTaskHours > 24 {
                            tempSubTaskHours -= 24
                        }
                    }) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "minus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    
                    Text("\(tempSubTaskHours)")
                        .font(.system(size: 18, weight: .medium))
                        .frame(minWidth: 30)
                    
                    Button(action: {
                        if tempSubTaskHours < 72 {
                            tempSubTaskHours += 24
                        }
                    }) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
        }
        .frame(height: 220)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
    
    // 保存新建的子任务
    private func saveNewSubTask() {
        viewModel.addSubTask(
            to: goal,
            title: newSubTaskTitle,
            estimatedDays: tempSubTaskHours / 24
        )
        
        // 重置表单并关闭
        newSubTaskTitle = ""
        tempSubTaskHours = 24
        showingAddSubTask = false
    }
    
    // 保存编辑后的子任务
    private func saveEditedSubTask() {
        guard let subTask = editingSubTask else { return }
        
        // 更新子任务信息
        subTask.title = tempSubTaskTitle
        subTask.estimatedHours = tempSubTaskHours
        
        // 保存更改
        viewModel.updateSubTask(subTask)
        
        // 关闭编辑界面
        showEditSubTaskSheet = false
        editingSubTask = nil
    }
    
    // 准备编辑子任务
    private func prepareEditSubTask(_ subTask: SubTask) {
        editingSubTask = subTask
        tempSubTaskTitle = subTask.title
        tempSubTaskHours = subTask.estimatedHours
        showEditSubTaskSheet = true
    }
    
    // 执行阶段按钮
    private var executionPhaseButtons: some View {
        VStack {
            if !isExecutingPhase && !isEvaluatingOrCompleted && goal.subTasks.count > 0 {
                // 规划阶段显示开始执行按钮
                Button(action: {
                    showConfirmStartExecution = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                        Text("开始执行")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: isEditMode ? 
                                              [Color.gray, Color.gray.opacity(0.8)] : 
                                              [Color.green, Color.green.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: isEditMode ? Color.gray.opacity(0.2) : Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                    .opacity(isEditMode ? 0.6 : 1.0)
                }
                .padding(.top, 10)
                .disabled(isEditMode)
            } else if isExecutingPhase {
                // 执行阶段视图 - 显示完成目标按钮
                if goal.allSubTasksCompleted || (goal.hasOverdueSubTasks && goal.allSubTasksProcessed) {
                    // 所有子任务已完成或者所有子任务都已处理（完成或超时）
                    Button(action: {
                        completeGoalAndStartEvaluation()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("完成目标")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding(.top, 10)
                } else if goal.hasOverdueSubTasks {
                    // 有超时子任务，但还有未处理的子任务，显示鼓励信息
                    VStack(spacing: 10) {
                        Text("有子任务已超时未完成，请继续完成剩余子任务")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        
                        Text("完成所有子任务可获得更全面的目标评估和更好的完成率")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 5)
                    }
                    .padding(.top, 10)
                }
            } else if isEvaluatingOrCompleted {
                // 评估或完成阶段 - 显示AI评语或错误信息
                VStack(spacing: 15) {
                    if showAPIError {
                        // 显示错误状态UI - 优化居中效果
                        VStack(spacing: 12) {
                            // 错误图标
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 28))
                                .foregroundColor(.orange)
                                .padding(.bottom, 4)
                            
                            Text("服务器无响应")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.red)
                            
                            if AIGoalAnalysisService.shared.hasReachedMaxAttempts(for: goal) {
                                // 如果达到最大尝试次数，显示"请稍后再试"
                                Text("请稍后再试")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            } else {
                                // 否则显示刷新按钮
                                Button(action: {
                                    completeGoalAndStartEvaluation()
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14))
                                        Text("刷新")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity) // 确保整个容器占据全宽
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                        )
                    } else if let comment = goal.aiComment, !comment.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI评语:")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text(comment)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity) // 确保整个容器占据全宽
            }
        }
    }
    
    // 返回评分的颜色
    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 {
            return .green
        } else if score >= 75 {
            return .blue
        } else if score >= 60 {
            return .orange
        } else {
            return .red
        }
    }
    
    // 目标头部信息
    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 目标标题和编辑按钮
            HStack(alignment: .top) {
                Text(goal.title)
                    .font(.system(size: 22, weight: .bold))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                // 编辑按钮 - 仅在规划阶段且没有子任务时显示
                if goal.executionStatus == .planning && goal.subTasks.isEmpty {
                    Button(action: {
                        // 显示编辑页面
                        showingEditGoal = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .shadow(color: .blue.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                }
            }
            
            // 将状态、创建时间、目标日期和预计时间集中到一个紧凑的区域
            HStack(spacing: 8) {
                // 左侧：状态标签 + 创建时间
                VStack(alignment: .leading, spacing: 4) {
                    // 状态标签
                    statusTag
                    
                    // 创建时间
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Text(formattedDateTime(goal.createdDate))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // 右侧：目标日期 + 预计完成时间
                VStack(alignment: .trailing, spacing: 4) {
                    // 目标日期
                    if let targetDate = goal.targetCompletionDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(formattedDate(targetDate))
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    // 预计完成时间
                    if !goal.subTasks.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 11))
                            Text("预计\(goal.subTasks.reduce(0) { $0 + $1.estimatedHours })小时")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .padding(.top, 0)
            
            // 进度指示器 - 仅当有子任务时显示
            if !goal.subTasks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("进度")
                            .font(.system(size: 12, weight: .medium))
                        
                        Spacer()
                        
                        Text("\(progressPercentage)% (\(goal.completedSubTasksCount)/\(goal.subTasks.count))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(CGFloat(progressPercentage) * 0.01 * UIScreen.main.bounds.width * 0.85, 0), height: 4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        )
        .sheet(isPresented: $showingEditGoal) {
            GoalEditView(viewModel: viewModel, goal: goal)
        }
        .sheet(isPresented: $showingUploadSheet) {
            uploadProofView
        }
    }
    
    // 子任务列表视图
    private var subTasksListView: some View {
        SubTasksListContainer(
            goal: goal,
            viewModel: viewModel,
            isExecutingPhase: isExecutingPhase,
            isEvaluatingOrCompleted: isEvaluatingOrCompleted,
            isEditMode: isEditMode,
            totalEstimatedDays: totalEstimatedDays,
            remainingSeconds: remainingSeconds,
            draggingSubTaskID: $draggingSubTaskID,
            currentExecutingSubTask: currentExecutingSubTask,
            subTaskRemainingSeconds: subTaskRemainingSeconds,
            onDragStateReset: {
                // 只发送通知，让容器组件自己处理状态重置
                NotificationCenter.default.post(name: .resetDragStates, object: nil)
            },
            onEditModeToggle: {
                isEditMode.toggle()
                if !isEditMode {
                    NotificationCenter.default.post(name: .resetDragStates, object: nil)
                }
            },
            onAddSubTask: {
                tempSubTaskHours = 24
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAddSubTask = true
                }
            },
            onRefreshSolution: {
                showingRefreshSolution = true
            },
            onEditSubTask: { subTask in
                prepareEditSubTask(subTask)
            },
            onUploadProof: { subTask in
                selectedSubTask = subTask
                showingUploadSheet = true
            },
            calculateProgressWidth: calculateProgressWidth,
            calculateRemainingTimePercentage: calculateRemainingTimePercentage,
            formatTime: formatTime,
            formatDaysHours: formatDaysHours,
            progressGradient: progressGradient,
            insertionTransition: insertionTransition
        )
    }
    
    // 添加这个新的结构体到适当的位置
    // 子任务列表容器
    struct SubTasksListContainer: View {
        let goal: Goal
        let viewModel: GoalViewModel
        let isExecutingPhase: Bool
        let isEvaluatingOrCompleted: Bool
        let isEditMode: Bool
        let totalEstimatedDays: Int
        let remainingSeconds: Int
        @Binding var draggingSubTaskID: UUID?
        let currentExecutingSubTask: SubTask?
        let subTaskRemainingSeconds: Int
        
        // 新增：拖拽操作锁定状态
        @State private var isReordering = false
        
        let onDragStateReset: () -> Void
        let onEditModeToggle: () -> Void
        let onAddSubTask: () -> Void
        let onRefreshSolution: () -> Void
        let onEditSubTask: (SubTask) -> Void
        let onUploadProof: (SubTask) -> Void
        
        let calculateProgressWidth: (GeometryProxy) -> CGFloat
        let calculateRemainingTimePercentage: () -> CGFloat
        let formatTime: (Int) -> String
        let formatDaysHours: (Int) -> String
        let progressGradient: (Bool) -> LinearGradient
        let insertionTransition: AnyTransition
        
        // 添加shouldShowCountdown计算属性
        private var shouldShowCountdown: Bool {
            let totalHours = goal.subTasks.reduce(0) { sum, task in 
                return sum + task.estimatedHours 
            }
            // 只要总预计时间大于等于1小时就显示
            return (isExecutingPhase || isEvaluatingOrCompleted) && totalHours >= 1
        }
        
        // 新增：重置拖拽状态的方法
        private func resetDragState() {
            withAnimation(.easeInOut(duration: 0.2)) {
                draggingSubTaskID = nil
            }
            
            // 延迟重置锁定状态，确保动画和操作已完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isReordering = false
            }
        }
        
        var body: some View {
            VStack(spacing: 15) {
                // 上部控制区域
                topControlArea
                
                // 子任务列表
                subTasksListArea
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
            )
            .onChange(of: draggingSubTaskID) { oldValue, newValue in
                // 当拖拽ID变为nil时，确保重置拖动状态
                if oldValue != nil && newValue == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isReordering = false
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetDragStates)) { _ in
                // 清除状态
                resetDragState()
            }
        }
        
        // 顶部控制区域
        private var topControlArea: some View {
            Group {
                if !isExecutingPhase && !isEvaluatingOrCompleted {
                    planningPhaseControls
                } else {
                    executionPhaseCountdown
                }
            }
        }
        
        // 规划阶段控制按钮
        private var planningPhaseControls: some View {
            HStack {
                // 编辑模式按钮 - 始终显示，不再限制子任务数量
                Button(action: onEditModeToggle) {
                    HStack(spacing: 5) {
                        Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil")
                            .font(.system(size: 14))
                        Text(isEditMode ? "完成编辑" : "编辑模式")
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(20)
                }
                
                Spacer()
                
                // 根据编辑模式显示不同按钮
                if isEditMode {
                    editModeButtons
                } else {
                    nonEditModeButtons
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
        }
        
        // 编辑模式按钮
        private var editModeButtons: some View {
            HStack {
                // 添加子任务按钮
                Button(action: onAddSubTask) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 14))
                        Text("添加子任务")
                            .font(.system(size: 14))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.1))
                    .foregroundColor(.purple)
                    .cornerRadius(20)
                }
                
                // 拖拽提示
                if goal.subTasks.count > 1 {
                    Text("长按并拖动可调整顺序")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                }
            }
        }
        
        // 非编辑模式按钮
        private var nonEditModeButtons: some View {
            Group {
                if AIGoalAnalysisService.shared.hasReachedMaxAttempts(for: goal) {
                    // 如果达到最大尝试次数，显示"请稍后再试"文本
                    Text("服务器无响应，请稍后再试")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                } else {
                    Button(action: onRefreshSolution) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                            Text("刷新方案")
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(20)
                    }
                }
            }
        }
        
        // 执行阶段倒计时显示
        private var executionPhaseCountdown: some View {
            Group {
                if shouldShowCountdown {
                    countdownView
                }
            }
        }
        
        // 倒计时视图
        private var countdownView: some View {
            VStack(spacing: 5) {
                // 顶部信息
                countdownHeaderView
                
                // 进度条
                countdownProgressBar
                
                // 提示信息
                countdownFooterView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEvaluatingOrCompleted ? Color.gray.opacity(0.08) : Color.indigo.opacity(0.08))
                    .shadow(color: isEvaluatingOrCompleted ? Color.gray.opacity(0.15) : Color.indigo.opacity(0.15), radius: 3, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        countdownBorderGradient,
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
        }
        
        // 倒计时头部视图
        private var countdownHeaderView: some View {
            HStack {
                // 左侧：图标和倒计时文本
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isEvaluatingOrCompleted ? .gray : .indigo)
                    Image(systemName: "hourglass")
                        .font(.system(size: 12))
                        .foregroundColor(isEvaluatingOrCompleted ? .gray : .indigo)
                        .if(!isEvaluatingOrCompleted) { view in
                            view.symbolEffect(.variableColor.iterative.reversing)
                        }
                    Text(isEvaluatingOrCompleted ? "计时结束" : "剩余倒计时")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isEvaluatingOrCompleted ? .gray : .indigo)
                }
                
                Spacer()
                
                // 右侧：百分比和倒计时
                countdownProgressInfo
            }
        }
        
        // 倒计时进度信息
        private var countdownProgressInfo: some View {
            HStack(spacing: 6) {
                // 百分比文本
                Text("剩余" + percentageText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isEvaluatingOrCompleted ? .gray.opacity(0.7) : .indigo.opacity(0.7))
                    .contentTransition(.numericText())
                
                // 时间文本
                Text(timeText)
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(isEvaluatingOrCompleted ? .gray : .indigo)
                    .contentTransition(.numericText())
            }
        }
        
        // 百分比文本计算
        private var percentageText: String {
            if isEvaluatingOrCompleted {
                if let finalRemaining = goal.finalRemainingSeconds {
                    // 使用总秒数而不是天数*24*60*60
                    let totalSecs = CGFloat(goal.subTasks.reduce(0) { total, subTask in
                        return total + (subTask.estimatedHours * 60 * 60)
                    })
                    
                    // 避免除以零
                    if totalSecs <= 0 {
                        return "0%"
                    }
                    
                    // 计算剩余时间百分比，而不是完成百分比
                    let percentage = Int((CGFloat(finalRemaining) / totalSecs) * 100)
                    return "\(percentage)%"
                } else {
                    return "0%"  // 如果没有剩余时间，表示已全部完成，剩余0%
                }
            } else {
                // 计算剩余时间百分比
                let percentage = Int(calculateRemainingTimePercentage() * 100)
                return "\(percentage)%"
            }
        }
        
        // 时间文本计算
        private var timeText: String {
            if isEvaluatingOrCompleted {
                return goal.finalTimeDisplay ?? formatTime(0)
            } else {
                return formatTime(remainingSeconds)
            }
        }
        
        // 倒计时进度条
        private var countdownProgressBar: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 5)
                    
                    // 进度
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressGradient(isEvaluatingOrCompleted))
                        .frame(width: calculateProgressWidth(geometry), height: 5)
                        .animation(isEvaluatingOrCompleted ? .none : .linear(duration: 1.0), value: remainingSeconds)
                }
            }
            .frame(height: 5)
        }
        
        // 倒计时底部信息
        private var countdownFooterView: some View {
            HStack {
                if isEvaluatingOrCompleted {
                    completedTimeInfo
                } else {
                    Text("预计将在 \(formatDaysHours(remainingSeconds)) 内完成")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                
                Spacer()
            }
        }
        
        // 完成时间信息
        private var completedTimeInfo: some View {
            Group {
                if let finalRemainingSeconds = goal.finalRemainingSeconds {
                    let totalSeconds = goal.subTasks.reduce(0) { total, subTask in
                        return total + (subTask.estimatedHours * 60 * 60)
                    }
                    let usedSeconds = totalSeconds - finalRemainingSeconds
                    Text("已完成，用时 \(formatDaysHours(usedSeconds))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                } else {
                    let totalSeconds = goal.subTasks.reduce(0) { total, subTask in
                        return total + (subTask.estimatedHours * 60 * 60)
                    }
                    Text("已完成，用时 \(formatDaysHours(totalSeconds))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        
        // 倒计时边框渐变
        private var countdownBorderGradient: LinearGradient {
            LinearGradient(
                gradient: Gradient(colors: isEvaluatingOrCompleted ? 
                                  [.gray.opacity(0.3), .gray.opacity(0.2)] : 
                                  [.indigo.opacity(0.3), .blue.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
        // 子任务列表区域
        private var subTasksListArea: some View {
            let sortedSubTasks = goal.subTasks.sorted(by: { $0.order < $1.order })
            
            return VStack(spacing: 0) {
                // 首个拖放区域
                if isEditMode && draggingSubTaskID != nil && !isReordering {
                    SubTaskDropZoneIndicator(isActive: true)
                        .padding(.bottom, 8)
                }
                
                ForEach(Array(sortedSubTasks.enumerated()), id: \.1.id) { index, subTask in
                    subTaskRow(for: subTask, at: index, in: sortedSubTasks)
                }
                
                // 最后一个拖放区域
                if isEditMode && draggingSubTaskID != nil && !isReordering {
                    SubTaskDropZoneIndicator(isActive: true)
                        .padding(.top, 8)
                }
            }
            .padding(.vertical, 10)
            // 减少动画触发频率，在拖拽过程中暂停动画
            .animation(isReordering ? nil : .spring(response: 0.5, dampingFraction: 0.7), value: goal.subTasks.map(\.order))
            .animation(isReordering ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: draggingSubTaskID)
        }
        
        // 子任务行视图
        private func subTaskRow(for subTask: SubTask, at index: Int, in allTasks: [SubTask]) -> some View {
            Group {
                SubTaskRowView(
                    subTask: subTask,
                    viewModel: viewModel,
                    isEditMode: isEditMode,
                    isExecuting: isExecutingPhase,
                    currentExecutingSubTask: currentExecutingSubTask,
                    subTaskRemainingSeconds: subTaskRemainingSeconds,
                    onEdit: {
                        onEditSubTask(subTask)
                    },
                    onUploadProof: {
                        onUploadProof(subTask)
                    },
                    onDragStarted: { id in
                        // 只有在未进行拖拽操作时才允许新的拖拽
                        if !isReordering {
                            isReordering = true
                            withAnimation(.easeInOut(duration: 0.2)) {
                                draggingSubTaskID = id
                            }
                        }
                    },
                    onDragEnded: {
                        resetDragState()
                    }
                )
                .transition(insertionTransition)
                .zIndex(draggingSubTaskID == subTask.id ? 10 : 0)
                
                // 中间拖放区域 (除最后一项外)
                if index < allTasks.count - 1 && isEditMode {
                    SubTaskDropZoneIndicator(isActive: draggingSubTaskID != nil && draggingSubTaskID != subTask.id && !isReordering)
                        .padding(.vertical, 4)
                }
            }
        }
    }
    
    // 开始执行目标
    private func startExecution() {
        // 调用ViewModel的方法开始执行
        viewModel.startGoalExecution(goal)
        
        // 重置所有拖拽状态
        NotificationCenter.default.post(name: .resetDragStates, object: nil)
        draggingSubTaskID = nil
        
        // 初始化子任务倒计时状态
        initializeSubTasksTimerState()
        
        // 让TimerManager开始管理这个目标
        timerManager.startManaging(goalID: goal.id)
        
        // 订阅定时器更新
        timerSubscription = timerManager.timerPublisher
            .sink { [self] _ in
                self.updateCountdownState()
            }
        
        // 显示提示
        alertMessage = "目标已锁定，进入执行阶段！"
        showAlert = true
    }
    
    // 状态标签
    private var statusTag: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // 显示目标状态和执行阶段
            Text(getDisplayStatus())
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1))
        .cornerRadius(6)
    }
    
    // 获取显示状态
    private func getDisplayStatus() -> String {
        // 如果有子任务，优先显示"规划中"状态
        if !goal.subTasks.isEmpty && goal.executionStatus == .planning {
            return "规划中"
        } else {
            return goal.status.rawValue
        }
    }
    
    // AI分析
    private func generateAIAnalysis() {
        loadingType = .analyzing
        isLoading = true
        showAPIError = false // 重置错误状态
        
        // 不再调用清除方案缓存的方法，避免删除已有方案
        // AIGoalAnalysisService.shared.clearPlanCache(for: goal)
        
        AIGoalAnalysisService.shared.analyzeGoal(goal) { generatedSubTasks in
            self.isLoading = false
            
            if generatedSubTasks.isEmpty {
                // API请求失败，显示错误
                self.showAPIError = true
            } else {
                // 清除现有子任务
                self.goal.subTasks.removeAll()
                
                // 添加新生成的子任务
                for subTask in generatedSubTasks {
                    self.goal.subTasks.append(subTask)
                }
                
                // 保存更改
                self.viewModel.updateGoal(self.goal)
                
                // 显示成功提示，强调"规划中"状态
                self.alertMessage = "AI已成功分解目标，生成\(generatedSubTasks.count)个子任务。您现在处于\"规划中\"状态，请检查子任务并进行调整。"
                self.showAlert = true
            }
        }
    }
    
    // 刷新AI分析
    private func refreshAIAnalysis() {
        loadingType = .analyzing
        isLoading = true
        showAPIError = false // 重置错误状态
        
        AIGoalAnalysisService.shared.refreshAnalysis(goal) { generatedSubTasks in
            self.isLoading = false
            
            if generatedSubTasks.isEmpty {
                // API请求失败，显示错误
                self.showAPIError = true
            } else {
                // 清除现有子任务
                self.goal.subTasks.removeAll()
                
                // 添加新生成的子任务
                for subTask in generatedSubTasks {
                    self.goal.subTasks.append(subTask)
                }
                
                // 保存更改
                self.viewModel.updateGoal(self.goal)
                
                // 获取当前方案索引和总数
                let goalId = self.goal.id
                let service = AIGoalAnalysisService.shared
                let currentIndex = service.getCurrentPlanIndex(for: goalId)
                let totalPlans = service.getTotalPlansCount(for: goalId)
                
                // 显示成功提示，同样强调"规划中"状态
                self.alertMessage = "AI已成功更新目标分解方案 (方案\(currentIndex + 1)/\(totalPlans))，生成\(generatedSubTasks.count)个子任务。您现在处于\"规划中\"状态，请检查子任务并进行调整。"
                self.showAlert = true
            }
        }
    }
    
    // 状态颜色
    private var statusColor: Color {
        // 如果是"规划中"状态，使用特定颜色
        if !goal.subTasks.isEmpty && goal.executionStatus == .planning {
            return .purple
        }
        
        // 其他状态使用原有颜色
        switch goal.status {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .overdue: return .red
        }
    }
    
    // 日期和时间格式化 - GoalDetailView
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    // 纯日期格式化 - GoalDetailView
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    // 上传证明视图
    private var uploadProofView: some View {
        NavigationStack {
            ZStack {
                // 背景颜色
                Color(.systemGroupedBackground).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // 主内容区域
                    ScrollView {
                        VStack(spacing: 20) {
                            // 多图选择器
                            PhotosPicker(selection: $selectedPhotos, matching: .images, photoLibrary: .shared()) {
                                VStack {
                                    Image(systemName: "photo.stack")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                        .padding()
                                    
                                    Text("选择照片")
                                        .foregroundColor(.blue)
                                }
                                .frame(height: 120)
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .onChange(of: selectedPhotos) { oldValue, newValue in
                                loadSelectedPhotos(items: newValue)
                            }
                            
                            // 显示已选择的图片
                            if !selectedImagesData.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("已选择\(selectedImagesData.count)张照片")
                                        .font(.headline)
                                        .padding(.bottom, 5)
                                    
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(0..<selectedImagesData.count, id: \.self) { index in
                                                if let uiImage = UIImage(data: selectedImagesData[index]) {
                                                    ZStack(alignment: .topTrailing) {
                                                        Image(uiImage: uiImage)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: 120, height: 120)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                                        
                                                        // 删除按钮
                                                        Button(action: {
                                                            removeImage(at: index)
                                                        }) {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .font(.system(size: 22))
                                                                .foregroundColor(.white)
                                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                                        }
                                                        .padding(6)
                                                    }
                                                }
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                            
                            // 说明输入框 - 移除标题，添加占位符
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $proofDescription)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.systemGray6))
                                    .frame(minHeight: 120, maxHeight: 200)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(.systemGray4), lineWidth: 1)
                                    )
                                    .padding(.bottom, 10)
                                
                                if proofDescription.isEmpty {
                                    Text("成果描述（可选）")
                                        .foregroundColor(Color(.placeholderText))
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                            
                            Spacer().frame(height: 100) // 底部留出空间
                        }
                        .padding(.horizontal)
                        .padding(.top, 16)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // 底部固定区域
                    VStack(spacing: 0) {
                        Divider()
                        
                        // 提交按钮
                        Button(action: submitProof) {
                            Group {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("提交完成成果")
                                        .fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .background(selectedImagesData.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .disabled(selectedImagesData.isEmpty || isSubmitting)
                    }
                }
            }
            .navigationTitle("完成成果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        resetUploadForm()
                    }
                }
            }
        }
        .interactiveDismissDisabled() // 防止用户通过下拉手势关闭
    }
    
    // 重置上传表单
    private func resetUploadForm() {
        selectedSubTask = nil
        selectedPhotos = []
        selectedImagesData = []
        proofDescription = ""
        showingUploadSheet = false
    }
    
    // 加载选中的多张照片
    private func loadSelectedPhotos(items: [PhotosPickerItem]) {
        selectedImagesData = [] // 清空现有数据
        
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    if let data = data {
                        DispatchQueue.main.async {
                            self.selectedImagesData.append(data)
                        }
                    }
                case .failure(let error):
                    print("Error loading image: \(error)")
                    DispatchQueue.main.async {
                        self.alertMessage = "加载图片失败: \(error.localizedDescription)"
                        self.showAlert = true
                    }
                }
            }
        }
    }
    
    // 移除指定索引的图片
    private func removeImage(at index: Int) {
        if index < selectedImagesData.count {
            selectedImagesData.remove(at: index)
            
            // 同步更新selectedPhotos数组
            if index < selectedPhotos.count {
                var updatedPhotos = selectedPhotos
                updatedPhotos.remove(at: index)
                selectedPhotos = updatedPhotos
            }
        }
    }
    
    // 准备上传证明
    private func prepareForUploadProof() {
        // 使用当前执行的子任务
        if let currentTask = currentExecutingSubTask {
            // 检查是否超时
            if currentTask.isOverdue {
                alertMessage = "该子任务已超时未完成，无法上传证明。"
                showAlert = true
                return
            }
            
            selectedSubTask = currentTask
            showingUploadSheet = true
        } else {
            // 如果没有当前执行的子任务，查找第一个未完成且未超时的子任务
            if let nextSubTask = goal.subTasks.first(where: { !$0.isCompleted && !$0.isOverdue }) {
                selectedSubTask = nextSubTask
                showingUploadSheet = true
            } else if goal.hasOverdueSubTasks {
                alertMessage = "存在超时未完成的子任务，无法继续执行。请完成目标进入评估阶段。"
                showAlert = true
            } else if goal.allSubTasksCompleted {
                alertMessage = "所有子任务已完成！可以点击完成目标按钮进入评估阶段。"
                showAlert = true
            } else {
                alertMessage = "没有可执行的子任务。"
                showAlert = true
            }
        }
    }
    
    // 提交证明
    private func submitProof() {
        guard let subTask = selectedSubTask, !selectedImagesData.isEmpty else {
            return
        }
        
        // 检查子任务是否超时
        if subTask.isOverdue {
            alertMessage = "该子任务已超时未完成，无法上传证明。"
            showAlert = true
            resetUploadForm()
            return
        }
        
        isSubmitting = true
        
        // 保存证明
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // 创建证明对象
            viewModel.addCompletionProof(
                to: subTask,
                imagesData: selectedImagesData,
                description: proofDescription
            )
            
            // 记录完成时的剩余时间
            subTask.remainingTimeWhenCompleted = subTaskRemainingSeconds
            
            // 标记子任务完成
            viewModel.markSubTaskCompleted(subTask)
            
            // 重置表单
            resetUploadForm()
            
            // 显示成功消息
            alertMessage = "成果上传成功！"
            showAlert = true
            isSubmitting = false
            
            // 启动下一个子任务
            startNextSubTask()
            
            // 如果所有子任务都已处理（完成或超时），自动进入AI评估阶段
            if goal.allSubTasksProcessed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // 不再显示确认对话框，直接完成目标并进入评估
                    completeGoalAndStartEvaluation()
                }
            }
        }
    }
    
    // 完成目标并立即开始评估
    private func completeGoalAndStartEvaluation() {
        // 保存最终倒计时状态
        goal.finalRemainingSeconds = remainingSeconds
        goal.finalTimeDisplay = formatTime(seconds: remainingSeconds)
        
        // 保存进度百分比
        _ = calculateRemainingTimePercentage()
        
        // 停止倒计时
        stopCountdown()
        
        // 更新目标状态为评估中
        viewModel.completeGoal(goal)
        
        // 设置加载状态，显示评分提示
        loadingType = .evaluating
        isLoading = true
        showAPIError = false // 重置错误状态
        
        // 触发AI评估
        AIGoalAnalysisService.shared.evaluateGoal(goal) { comment in
            // 关闭加载状态
            self.isLoading = false
            
            if comment == "服务器无响应，请刷新。" {
                // 服务器请求失败，显示错误UI
                self.showAPIError = true
            } else {
                // 设置评估结果
                self.viewModel.setGoalEvaluation(self.goal, comment: comment)
                
                // 显示完成消息
                self.alertMessage = "恭喜！目标已完成，AI评估已生成。"
                self.showAlert = true
            }
        }
    }
    
    // 保留原完成目标方法，但不再使用
    private func completeGoal() {
        // 停止倒计时
        stopCountdown()
        
        viewModel.completeGoal(goal)
        
        // 显示完成消息
        alertMessage = "恭喜！目标已完成，即将进入评估阶段。"
        showAlert = true
    }
    
    // 格式化开始日期显示
    private func formatStartDateDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "开始于: \(formatter.string(from: date))"
    }
    
    // 格式化秒数为时:分:秒格式
    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // 添加新方法
    private func updateCountdownState() {
        guard isExecutingPhase else { return }
        
        // 更新TimerManager中的状态
        if let modelContext = viewModel.modelContext {
            timerManager.updateGoalsTimerState(modelContext: modelContext)
        }
        
        // 更新视图状态
        updateViewCountdownState()
    }
    
    private func updateViewCountdownState() {
        // 获取所有未完成且未超时的子任务
        let activeSubTasks = goal.subTasks
            .filter { !$0.isCompleted && !$0.isOverdue }
            .sorted(by: { $0.order < $1.order })
        
        // 更新当前执行的子任务
        currentExecutingSubTask = activeSubTasks.first
        
        // 更新子任务剩余时间
        if let currentTask = currentExecutingSubTask,
           let remainingSeconds = currentTask.remainingSecondsForTimer {
            subTaskRemainingSeconds = remainingSeconds
        }
        
        // 更新总体剩余时间
        calculateRemainingTotalTime()
    }
    
    private func calculateRemainingTotalTime() {
        // 计算子任务的总预计时间（秒）
        let totalEstimatedSeconds = goal.subTasks.reduce(0) { total, subTask in
            return total + (subTask.estimatedHours * 60 * 60)
        }
        
        // 已完成子任务消耗的实际时间总和（秒）
        let completedTasksActualTime = goal.subTasks
            .filter { $0.isCompleted && $0.remainingTimeWhenCompleted != nil }
            .reduce(0) { total, subTask in
                // 使用子任务的预计时间减去完成时剩余的时间，得到实际用时
                let subTaskTotalSeconds = subTask.estimatedHours * 60 * 60
                let remainingSeconds = subTask.remainingTimeWhenCompleted ?? 0
                let actualUsedSeconds = subTaskTotalSeconds - remainingSeconds
                return total + actualUsedSeconds
            }
        
        // 当前执行中子任务已用时间
        var currentTaskUsedSeconds = 0
        if let currentTask = currentExecutingSubTask,
           let remainingSeconds = currentTask.remainingSecondsForTimer {
            let totalSeconds = currentTask.estimatedHours * 60 * 60
            currentTaskUsedSeconds = totalSeconds - remainingSeconds
        }
        
        // 总共已用时间 = 已完成任务实际用时 + 当前任务已用时间
        let totalUsedSeconds = completedTasksActualTime + currentTaskUsedSeconds
        
        // 计算剩余时间
        remainingSeconds = totalEstimatedSeconds - totalUsedSeconds
        
        // 确保剩余时间不小于0
        remainingSeconds = max(0, remainingSeconds)
    }
    
    // 添加初始化子任务计时器状态的方法
    private func initializeSubTasksTimerState() {
        // 获取所有未完成且未超时的子任务，按顺序排序
        let activeSubTasks = goal.subTasks
            .filter { !$0.isCompleted && !$0.isOverdue }
            .sorted(by: { $0.order < $1.order })
        
        // 初始化第一个子任务的倒计时
        if let firstSubTask = activeSubTasks.first {
            firstSubTask.remainingSecondsForTimer = firstSubTask.estimatedHours * 60 * 60
        }
        
        // 初始化总倒计时
        calculateRemainingTotalTime()
    }
    
    // 修改开始倒计时方法
    private func startCountdown() {
        // 初始化子任务计时器状态
        initializeSubTasksTimerState()
        
        // 让TimerManager开始管理这个目标
        timerManager.startManaging(goalID: goal.id)
        
        // 订阅定时器更新
        timerSubscription = timerManager.timerPublisher
            .sink { [self] _ in
                self.updateCountdownState()
            }
    }
    
    // 修改停止倒计时方法
    private func stopCountdown() {
        // 取消定时器订阅
        timerSubscription?.cancel()
        timerSubscription = nil
    }
    
    // 修改开始下一个子任务的执行方法
    private func startNextSubTask() {
        updateViewCountdownState()
    }
    
    // 修改停止子任务倒计时方法，现在是空方法，由TimerManager管理
    private func stopSubTaskCountdown() {
        // 空方法，由TimerManager管理
    }
    
    // 计算剩余时间进度条宽度
    private func calculateRemainingTimeWidth(totalWidth: CGFloat) -> CGFloat {
        // 获取总时间（秒）
        let totalSeconds = CGFloat(goal.subTasks.reduce(0) { total, subTask in
            return total + (subTask.estimatedHours * 60 * 60)
        })
        
        // 计算剩余时间的秒数
        let remainingSecs = CGFloat(remainingSeconds)
        
        // 计算剩余时间百分比
        let percentageRemaining = remainingSecs / totalSeconds
        
        // 计算宽度
        let width = percentageRemaining * totalWidth
        
        // 确保不会小于0或大于总宽度
        return min(max(width, 0), totalWidth)
    }
    
    // 计算剩余时间百分比
    private func calculateRemainingTimePercentage() -> CGFloat {
        // 获取总时间（秒）
        let totalSeconds = CGFloat(goal.subTasks.reduce(0) { total, subTask in
            return total + (subTask.estimatedHours * 60 * 60)
        })
        
        // 如果总时间为0，避免除以零错误
        if totalSeconds <= 0 {
            return 0
        }
        
        // 获取剩余时间（秒）
        let remainingSecs = CGFloat(self.remainingSeconds)
        
        // 计算并返回百分比
        return remainingSecs / totalSeconds
    }
    
    // 格式化天数和小时
    private func formatDaysHours(_ seconds: Int) -> String {
        let minutes = (seconds / 60) % 60
        let hours = seconds / 3600
        let days = hours / 24
        let remainingHours = hours % 24
        
        if days > 0 {
            return "\(days)天\(remainingHours)小时\(minutes)分钟"
        } else if hours > 0 {
            return "\(remainingHours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }
    
    // 计算进度条宽度的辅助方法，用于简化复杂表达式
    private func calculateProgressWidth(geometry: GeometryProxy) -> CGFloat {
        let width = geometry.size.width
        
        // 评估或完成状态
        if isEvaluatingOrCompleted {
            // 如果有finalRemainingSeconds，计算比例
            if let finalRemainingSeconds = goal.finalRemainingSeconds {
                // 提取计算步骤为简单变量
                let totalSeconds = CGFloat(goal.subTasks.reduce(0) { total, subTask in
                    return total + (subTask.estimatedHours * 60 * 60)
                })
                let finalRemaining = CGFloat(finalRemainingSeconds)
                let ratio = finalRemaining / totalSeconds  // 使用剩余时间占比
                
                // 应用比例到宽度
                return width * ratio
            } 
            // 没有finalRemainingSeconds，返回0宽度（表示已全部使用完）
            return 0
        } 
        
        // 执行中状态，使用计算的剩余时间宽度
        return calculateRemainingTimeWidth(totalWidth: width)
    }
    
    // 添加这个函数到适当位置，用于简化渐变的选择逻辑
    private func progressGradient(isEvaluatingOrCompleted: Bool) -> LinearGradient {
        // 选择适当的颜色
        let colors: [Color] = isEvaluatingOrCompleted ?
            [.gray, .gray.opacity(0.7)] :
            [.indigo, .blue.opacity(0.7)]
        
        // 创建并返回渐变
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // 显示确认对话框的辅助方法
    private func showConfirmationDialog(_ title: String, message: String, action: @escaping () -> Void) {
        confirmationTitle = title
        confirmationMessage = message
        confirmationAction = action
        showingConfirmationDialog = true
    }
}

// 子任务行视图
struct SubTaskRowView: View {
    let subTask: SubTask
    @ObservedObject var viewModel: GoalViewModel
    var isEditMode: Bool
    var isExecuting: Bool
    var currentExecutingSubTask: SubTask?
    var subTaskRemainingSeconds: Int
    var onEdit: () -> Void
    var onUploadProof: () -> Void
    var onDragStarted: ((UUID) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    @State private var isDragging = false
    @State private var isTargeted = false
    @State private var showingProofDetail = false
    
    // 判断当前子任务是否为正在执行的子任务
    private var isCurrentExecuting: Bool {
        return isExecuting && currentExecutingSubTask?.id == subTask.id
    }
    
    // 判断子任务是否等待执行（未完成且非当前执行）
    private var isWaitingForExecution: Bool {
        return isExecuting && !subTask.isCompleted && currentExecutingSubTask?.id != subTask.id
    }
    
    // 添加对超时未完成状态的判断
    private var isOverdue: Bool {
        return subTask.isOverdue
    }
    
    var body: some View {
        // 创建和配置主要视图内容
        let mainContent = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                taskDetailsColumn
                
                Spacer()
                
                actionButtonsColumn
            }
        }
        .padding()
        
        // 应用样式和动画效果
        return mainContent
            .background(backgroundColorForState)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColorForState, lineWidth: isTargeted || isDragging ? 2 : 1)
            )
            .scaleEffect(scaleEffect)
            .shadow(color: shadowColorForState, radius: isTargeted || isDragging ? 5 : 0, x: 0, y: isTargeted || isDragging ? 3 : 0)
            .opacity(isDragging ? 0.75 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
            .onReceive(NotificationCenter.default.publisher(for: .resetDragStates)) { _ in
                // 接收到重置通知时，立即重置拖拽状态
                isDragging = false
                isTargeted = false
            }
            .onDrag {
                // 仅在编辑模式下允许拖拽
                if isEditMode && !isExecuting {
                    self.isDragging = true
                    // 触觉反馈
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    // 通知父视图拖拽开始
                    onDragStarted?(subTask.id)
                    
                    // 将SubTask的ID传递给NSItemProvider
                    return NSItemProvider(object: self.subTask.id.uuidString as NSString)
                } else {
                    return NSItemProvider()
                }
            }
            .onChange(of: isDragging) { oldValue, newValue in
                if oldValue == true && newValue == false {
                    // 通知父视图拖拽结束
                    onDragEnded?()
                }
            }
            // 将复杂的sheet内容替换为使用辅助视图
            .sheet(isPresented: $showingProofDetail) {
                ProofDetailView(subTask: subTask, viewModel: viewModel)
            }
            // 将onDrop调用替换为使用createDropDelegate()函数
            .onDrop(of: [UTType.text.identifier], delegate: createDropDelegate())
    }
    
    // 创建DropDelegate的辅助函数，简化onDrop调用的复杂度
    private func createDropDelegate() -> SubTaskDropDelegate {
        return SubTaskDropDelegate(
            subTask: subTask, 
            viewModel: viewModel, 
            isDragging: $isDragging, 
            isTargeted: $isTargeted,
            draggedItemID: subTask.id
        )
    }
    
    // 子任务详情列
    private var taskDetailsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 子任务标题
            Text(subTask.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(textColor)
                .strikethrough(subTask.isCompleted)
                .lineLimit(3)
            
            // 预计完成时间显示
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("预计需要 \(subTask.estimatedHours) 小时")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            // 任务状态信息
            taskStatusInfo
        }
    }
    
    // 任务状态信息显示（已完成/超时/当前执行）
    private var taskStatusInfo: some View {
        Group {
            if subTask.isCompleted {
                completedTaskInfo
            } else if isOverdue {
                overdueTaskInfo
            } else if isCurrentExecuting {
                currentExecutingTaskInfo
            }
        }
    }
    
    // 已完成状态信息
    private var completedTaskInfo: some View {
        Group {
            if let completedDate = subTask.completionDate {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("已完成于 \(formattedDate(completedDate))")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                    
                    // 如果有剩余时间记录，显示剩余时间
                    if let remainingTime = subTask.remainingTimeWhenCompleted {
                        HStack {
                            Image(systemName: "timer")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("倒计时: \(formatTime(seconds: remainingTime))")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
        }
    }
    
    // 超时未完成状态信息
    private var overdueTaskInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                Text("超时未完成")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            
            // 显示倒计时已结束
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                Text("倒计时: 00:00:00")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 2)
    }
    
    // 当前执行中的任务信息
    private var currentExecutingTaskInfo: some View {
        HStack {
            Image(systemName: "timer")
                .font(.system(size: 12))
                .foregroundColor(.red)
            Text("倒计时: \(formatTime(seconds: subTaskRemainingSeconds))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
        }
        .padding(.top, 2)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.red.opacity(0.1))
        )
    }
    
    // 操作按钮列
    private var actionButtonsColumn: some View {
        Group {
            if isEditMode {
                editModeButtons
            } else if isExecuting {
                executingModeButtons
            } else if subTask.isCompleted {
                completedTaskButtons
            }
        }
    }
    
    // 编辑模式按钮
    private var editModeButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onEdit()
                }
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            
            // 只有当子任务数量大于1时才显示删除按钮
            if let goal = viewModel.getGoalForSubTask(subTask), goal.subTasks.count > 1 {
                Button(action: {
                    deleteSubTask()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            // 拖动手柄
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.gray)
                .font(.system(size: 14))
                .opacity(0.8)
        }
        .padding(.trailing, 6)
    }
    
    // 执行阶段按钮
    private var executingModeButtons: some View {
        Group {
            if subTask.isCompleted {
                // 已完成状态 - 显示查看证明按钮
                Button(action: {
                    showingProofDetail = true
                }) {
                    Image(systemName: "photo.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            } else if isOverdue {
                // 超时未完成状态 - 显示锁定图标
                Image(systemName: "lock.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red)
            } else if isCurrentExecuting {
                // 当前执行状态 - 显示上传证明按钮
                Button(action: {
                    onUploadProof()
                }) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            } else {
                // 等待执行状态 - 显示等待图标
                Image(systemName: "clock.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
            }
        }
    }
    
    // 已完成任务的按钮
    private var completedTaskButtons: some View {
        Group {
            // 非编辑模式下已完成的子任务 - 显示查看证明按钮（如果有证明）
            if viewModel.getCompletionProof(for: subTask) != nil {
                Button(action: {
                    showingProofDetail = true
                }) {
                    Image(systemName: "photo.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
            } else {
                // 没有证明的已完成子任务显示完成图标
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            }
        }
    }
    
    // 根据状态返回文本颜色
    private var textColor: Color {
        if isOverdue {
            return .red
        } else if subTask.isCompleted {
            return .secondary
        } else {
            return .primary
        }
    }
    
    // 根据状态计算缩放效果
    private var scaleEffect: CGFloat {
        if isDragging {
            return 1.05
        } else if isTargeted {
            return 1.02
        } else {
            return 1.0
        }
    }
    
    // 根据状态返回背景颜色
    private var backgroundColorForState: Color {
        // 首先检查是否被拖拽目标
        if isTargeted {
            return Color.blue.opacity(0.1)
        }
        
        // 检查超时状态
        if isOverdue {
            return Color.red.opacity(0.1) // 超时未完成使用红色背景
        }
        
        // 然后检查执行状态
        if isCurrentExecuting {
            return Color.blue.opacity(0.15) // 当前执行的子任务使用蓝色背景
        }
        
        // 检查完成状态
        if subTask.isCompleted {
            return Color(.secondarySystemBackground).opacity(0.3) // 已完成使用灰色背景
        }
        
        // 检查等待执行状态
        if isWaitingForExecution {
            return Color(.secondarySystemBackground).opacity(0.5) // 待执行使用灰色背景
        }
        
        // 默认背景
        return Color(.secondarySystemBackground).opacity(0.5)
    }
    
    // 根据状态返回边框颜色
    private var borderColorForState: Color {
        // 首先检查是否为拖拽目标
        if isTargeted {
            return Color.blue.opacity(0.5)
        }
        
        // 检查是否正在拖拽
        if isDragging {
            return Color.blue.opacity(0.3)
        }
        
        // 检查超时状态
        if isOverdue {
            return Color.red.opacity(0.5) // 超时未完成使用红色边框
        }
        
        // 检查执行状态
        if isCurrentExecuting {
            return Color.blue.opacity(0.5) // 当前执行的子任务使用蓝色边框
        }
        
        // 检查完成状态
        if subTask.isCompleted {
            return Color.green.opacity(0.3) // 已完成使用绿色边框
        }
        
        // 默认无边框
        return Color.clear
    }
    
    // 根据状态返回阴影颜色
    private var shadowColorForState: Color {
        // 首先检查是否为拖拽目标
        if isTargeted {
            return Color.blue.opacity(0.3)
        }
        
        // 检查是否正在拖拽
        if isDragging {
            return Color.blue.opacity(0.2)
        }
        
        // 检查超时状态
        if isOverdue {
            return Color.red.opacity(0.3) // 超时未完成使用红色阴影
        }
        
        // 检查执行状态
        if isCurrentExecuting {
            return Color.blue.opacity(0.3) // 当前执行的子任务使用蓝色阴影
        }
        
        // 默认无阴影
        return Color.clear
    }
    
    // 删除子任务
    private func deleteSubTask() {
        viewModel.deleteSubTask(subTask)
    }
    
    // 日期格式化 - SubTaskRowView
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    // 日期和时间格式化 - SubTaskRowView
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    // 格式化秒数为时:分:秒格式
    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// 拖放委托
struct SubTaskDropDelegate: DropDelegate {
    let subTask: SubTask
    let viewModel: GoalViewModel
    @Binding var isDragging: Bool
    @Binding var isTargeted: Bool
    var draggedItemID: UUID? = nil
    
    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [UTType.text.identifier]).first else { 
            isDragging = false
            isTargeted = false
            return false 
        }
        
        itemProvider.loadObject(ofClass: NSString.self) { (data, error) in
            guard let sourceID = data as? String,
                  let sourceUUID = UUID(uuidString: sourceID),
                  let goal = self.subTask.goal else {
                DispatchQueue.main.async {
                    self.isDragging = false
                    self.isTargeted = false
                }
                return
            }
            
            DispatchQueue.main.async {
                // 防止拖到自己的位置
                if sourceUUID != self.subTask.id {
                    // 应用挤压动画效果
                    let animation = Animation.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.1)
                    
                    withAnimation(animation) {
                        // 使用基于ID的重排序方法，而不是基于索引
                        self.viewModel.reorderSubTasksByID(for: goal, fromID: sourceUUID, toID: self.subTask.id)
                    }
                    
                    // 播放触感反馈
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    // 延迟重置状态，使动画有时间完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.isDragging = false
                        self.isTargeted = false
                        
                        // 发送全局通知以确保所有视图都重置状态
                        NotificationCenter.default.post(name: .resetDragStates, object: nil)
                    }
                } else {
                    // 拖到自己的位置，直接重置状态
                    self.isDragging = false
                    self.isTargeted = false
                }
            }
        }
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // 拖拽进入时的视觉提示
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            self.isTargeted = true
        }
    }
    
    func dropExited(info: DropInfo) {
        // 拖拽退出时清除视觉提示
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            self.isTargeted = false
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// 加载视图
struct LoadingView: View {
    var text: String
    
    var body: some View {
        HStack(spacing: 15) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

// 按钮缩放效果
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// 子任务拖拽区域指示器
struct SubTaskDropZoneIndicator: View {
    var isActive: Bool
    
    var body: some View {
        Rectangle()
            .fill(Color.blue.opacity(0.15))
            .frame(height: isActive ? 20 : 0)
            .cornerRadius(10)
            .padding(.horizontal, 10)
            .overlay(
                Group {
                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Text("放置在这里")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                        }
                    }
                }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
    }
}

#Preview {
    let viewModel = GoalViewModel(modelContext: nil)
    let previewGoal = createPreviewGoal()
    
    return NavigationStack {
        GoalDetailView(viewModel: viewModel, goal: previewGoal)
    }
}

// 创建预览用的模拟数据
private func createPreviewGoal() -> Goal {
    let previewGoal = Goal(
        title: "开发iOS应用",
        goalDescription: "创建一个目标管理应用",
        priority: .standard,
        targetCompletionDate: Calendar.current.date(byAdding: .day, value: 10, to: Date())
    )
    
    // 添加一些子任务
    let subTask1 = SubTask(title: "完成第一阶段目标，重点关注基础内容搭建")
    subTask1.markAsCompleted()
    subTask1.goal = previewGoal
    
    let subTask2 = SubTask(title: "完成第二阶段目标，重点关注基础内容搭建")
    subTask2.goal = previewGoal
    
    let subTask3 = SubTask(title: "完成第三阶段目标，重点关注基础内容搭建")
    subTask3.goal = previewGoal
    
    // 添加到目标中
    previewGoal.subTasks = [subTask1, subTask2, subTask3]
    
    return previewGoal
}

// 将证明详情移到单独的视图中
private struct ProofDetailView: View {
    let subTask: SubTask
    let viewModel: GoalViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if let completionProof = viewModel.getCompletionProof(for: subTask) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // 任务标题
                        Text(subTask.title)
                            .font(.headline)
                            .padding(.top)
                        
                        // 证明图片部分
                        proofImagesSection(completionProof)
                        
                        // 证明描述
                        proofDescriptionSection(completionProof)
                        
                        // 完成时间
                        proofCompletionTimeSection()
                        
                        Spacer()
                    }
                    .padding()
                }
                .navigationTitle("完成成果")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("关闭") {
                            dismiss()
                        }
                    }
                }
            }
        } else {
            Text("未找到成果信息")
                .foregroundColor(.secondary)
                .padding()
        }
    }
    
    // 照片显示部分
    private func proofImagesSection(_ proof: CompletionProof) -> some View {
        Group {
            let imagesData = proof.allImagesData
            if !imagesData.isEmpty {
                VStack {
                    TabView {
                        ForEach(0..<imagesData.count, id: \.self) { index in
                            if let uiImage = UIImage(data: imagesData[index]) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .cornerRadius(12)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle())
                    .frame(height: 300)
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                    
                    // 照片计数
                    Text("\(imagesData.count) 张照片")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // 描述部分
    private func proofDescriptionSection(_ proof: CompletionProof) -> some View {
        Group {
            if let description = proof.proofDescription, !description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("成果说明:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // 完成时间部分
    private func proofCompletionTimeSection() -> some View {
        Group {
            // 完成时间
            if let completedDate = subTask.completionDate {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text("完成于: \(formattedDateTime(completedDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 5)
            }
            
            // 显示完成时的剩余时间（如果有）
            if let remainingTime = subTask.remainingTimeWhenCompleted {
                HStack {
                    Image(systemName: "timer")
                        .foregroundColor(.orange)
                    Text("倒计时: \(formatTime(seconds: remainingTime))")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                .padding(.top, 5)
            }
        }
    }
    
    // 格式化时间函数
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // 格式化秒数为时分秒
    private func formatTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
