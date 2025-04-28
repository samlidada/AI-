import SwiftUI
import SwiftData

struct GoalEvaluationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: GoalViewModel
    let goal: Goal
    
    @State private var isLoading = false
    @State private var showShareSheet = false
    @State private var screenshotImage: UIImage?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 目标头部信息
                goalHeader
                
                // 评估结果区
                VStack(alignment: .leading, spacing: 15) {
                    Text("评估结果")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                ProgressView()
                                    .padding()
                                Text("AI正在评估您的目标完成情况...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else if let comment = goal.aiComment {
                        // AI评语
                        VStack(alignment: .leading, spacing: 10) {
                            Text("AI评语")
                                .font(.subheadline)
                            
                            Text(comment)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                        .padding(.top, 5)
                    } else {
                        // 开始评估按钮
                        VStack(spacing: 15) {
                            Text("准备就绪，等待AI评估")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                startEvaluation()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("开始AI评估")
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.05), radius: 5)
                
                // 已完成子任务列表
                completedTasksSection
                
                // 分享按钮
                if goal.aiComment != nil {
                    Button(action: {
                        prepareShareContent()
                    }) {
                        HStack {
                            Spacer()
                            Label("分享成果", systemImage: "square.and.arrow.up")
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.top, 10)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("目标评估")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 如果已经在评估中状态，自动开始评估
            if goal.executionStatus == .evaluating && goal.aiComment == nil {
                startEvaluation()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = screenshotImage {
                ShareSheet(items: [image])
            }
        }
    }
    
    // 目标头部信息
    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            // 目标基本信息
            VStack(alignment: .leading, spacing: 12) {
                // 目标标题
                Text(goal.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                // 目标描述
                if !goal.goalDescription.isEmpty {
                    Text(goal.goalDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 5)
                }
                
                // 目标信息栏
                HStack(spacing: 15) {
                    // 删除优先级标签
                    
                    // 目标状态
                    Label(goal.status.rawValue, systemImage: "circle.fill")
                        .foregroundColor(statusColor)
                    
                    // 截止日期
                    if let targetDate = goal.targetCompletionDate {
                        Label(formattedDate(targetDate), systemImage: "calendar")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
            }
            
            // 进度指示器
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("全部完成")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text("\(goal.completedSubTasksCount)/\(goal.subTasks.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: 1.0)
                    .tint(.green)
            }
            .padding(.top, 5)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5)
    }
    
    // 已完成子任务列表
    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("子任务完成情况")
                .font(.headline)
                .padding(.bottom, 5)
            
            // 直接使用VStack而不是ForEach
            VStack(spacing: 8) {
                // 手动迭代每个子任务
                Group {
                    if goal.subTasks.isEmpty {
                        Text("没有子任务")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        // 只显示前10个子任务，避免视图过于复杂
                        let tasksToShow = min(goal.subTasks.count, 10)
                        
                        ForEach(0..<tasksToShow, id: \.self) { i in
                            let subTask = goal.subTasks[i]
                            subTaskRow(subTask)
                        }
                        
                        if goal.subTasks.count > 10 {
                            Text("还有\(goal.subTasks.count - 10)个子任务未显示...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5)
    }
    
    // 辅助方法：创建子任务行视图
    private func subTaskRow(_ subTask: SubTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Text(subTask.title)
                    .font(.body)
                    .strikethrough(subTask.isCompleted)
            }
            
            // 检查SubTask是否已完成
            if subTask.isCompleted {
                // 尝试获取完成日期
                if let completionDate = getCompletionDate(for: subTask) {
                    Text("完成于: \(formattedDate(completionDate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("已完成")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    // 辅助方法：安全获取完成日期
    private func getCompletionDate(for subTask: SubTask) -> Date? {
        // 尝试直接访问completionDate
        if let completionDate = subTask.completionDate {
            return completionDate
        }
        // 如果无法访问completionDate但任务已完成，返回当前日期
        if subTask.isCompleted {
            return Date()
        }
        return nil
    }
    
    // 开始评估
    private func startEvaluation() {
        isLoading = true
        
        // 使用AIGoalAnalysisService进行评估
        AIGoalAnalysisService.shared.evaluateGoal(goal) { comment in
            // 更新目标评估结果
            DispatchQueue.main.async {
                self.viewModel.setGoalEvaluation(self.goal, comment: comment)
                self.isLoading = false
            }
        }
    }
    
    // 准备分享内容
    private func prepareShareContent() {
        let renderer = ImageRenderer(content: sharingContent)
        if let uiImage = renderer.uiImage {
            screenshotImage = uiImage
            showShareSheet = true
        }
    }
    
    // 用于生成分享的内容视图
    private var sharingContent: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("目标达成报告")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.bottom)
            
            Text(goal.title)
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 5)
            
            HStack {
                Spacer()
                
                if let completedDate = goal.completedDate {
                    Text("完成于: \(formattedDate(completedDate))")
                        .font(.subheadline)
                }
            }
            .padding(.bottom)
            
            if let comment = goal.aiComment {
                Text("AI评价:")
                    .font(.headline)
                
                Text(comment)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            
            Spacer()
            
            Text("子任务完成情况:")
                .font(.headline)
                .padding(.top)
            
            // 直接列出子任务，不使用ForEach
            VStack(alignment: .leading, spacing: 2) {
                let tasksToShow = min(goal.subTasks.count, 10)
                
                ForEach(0..<tasksToShow, id: \.self) { i in
                    let subTask = goal.subTasks[i]
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Text(subTask.title)
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                }
                
                if goal.subTasks.count > 10 {
                    Text("还有\(goal.subTasks.count - 10)个子任务未显示...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack {
                Text("Powered by AI目标拆解")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("共完成 \(goal.subTasks.count) 个子任务")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 600, height: 800)
        .background(Color.white)
    }
    
    // 日期格式化
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // 状态颜色
    private var statusColor: Color {
        switch goal.status {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .overdue: return .red
        }
    }
}

// 分享表单
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 不需要做任何事情
    }
}

#Preview {
    let preview = createPreviewContent()
    return NavigationStack {
        GoalEvaluationView(viewModel: preview.viewModel, goal: preview.goal)
    }
}

// 辅助函数：创建预览内容
private func createPreviewContent() -> (viewModel: GoalViewModel, goal: Goal) {
    // 创建预览用的模拟数据
    let previewGoal = Goal(
        title: "开发iOS应用",
        goalDescription: "创建一个目标管理应用",
        priority: .standard,
        targetCompletionDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())
    )
    
    // 添加一些已完成的子任务
    let subTask1 = SubTask(title: "设计UI")
    subTask1.goal = previewGoal
    subTask1.markAsCompleted()
    
    let subTask2 = SubTask(title: "实现核心功能")
    subTask2.goal = previewGoal
    subTask2.markAsCompleted()
    
    let subTask3 = SubTask(title: "测试和优化")
    subTask3.goal = previewGoal
    subTask3.markAsCompleted()
    
    previewGoal.subTasks = [subTask1, subTask2, subTask3]
    previewGoal.executionStatus = .evaluating
    previewGoal.markAsCompleted()
    
    let viewModel = GoalViewModel(modelContext: nil)
    
    return (viewModel, previewGoal)
} 