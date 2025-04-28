import SwiftUI
import PhotosUI

struct GoalExecutionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: GoalViewModel
    let goal: Goal
    
    @State private var selectedSubTask: SubTask?
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImagesData: [Data] = []
    @State private var proofDescription: String = ""
    @State private var showingImagePicker = false
    @State private var isSubmitting = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 目标头部信息
                goalHeader
                
                // 进度追踪
                progressSection
                
                // 子任务列表
                subTaskSection
                
                // 完成按钮 - 仅在所有子任务完成但尚未触发评估时显示
                if goal.completedSubTasksCount == goal.subTasks.count && goal.executionStatus != .evaluating && goal.executionStatus != .completed {
                    Button(action: {
                        completeGoalAndEvaluate()
                    }) {
                        HStack {
                            Spacer()
                            Text("完成目标")
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
        .navigationTitle("执行目标")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingImagePicker) {
            uploadProofView
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("确定", role: .cancel) {
                // 如果是评估完成的消息，返回上一页
                if alertMessage.contains("评估已生成") {
                    dismiss()
                }
            }
        }
    }
    
    // 目标头部信息
    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 15) {
            // 目标标题
            Text(goal.title)
                .font(.title2)
                .fontWeight(.bold)
            
            // 目标描述（如果有）
            if !goal.goalDescription.isEmpty {
                Text(goal.goalDescription)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // 目标信息行
            HStack {
                if let startDate = goal.startExecutionDate {
                    Label(formatStartDateDisplay(startDate), systemImage: "clock")
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Label(goal.status.rawValue, systemImage: "circle.fill")
                    .foregroundColor(statusColor)
                
                Spacer()
                
                if let targetDate = goal.targetCompletionDate {
                    Label(formattedDate(targetDate), systemImage: "calendar")
                        .foregroundColor(.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5)
    }
    
    // 进度部分
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("执行进度")
                .font(.headline)
                .padding(.bottom, 5)
            
            HStack {
                Text("完成子任务: \(goal.completedSubTasksCount)/\(goal.subTasks.count)")
                    .font(.subheadline)
                
                Spacer()
                
                Text("\(Int(goal.subTasksProgress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
            }
            
            ProgressView(value: goal.subTasksProgress)
                .tint(.blue)
                .padding(.bottom, 5)
            
            if let startDate = goal.startExecutionDate {
                Text("开始执行于: \(formattedDateTime(startDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5)
    }
    
    // 子任务部分
    private var subTaskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("子任务列表")
                .font(.headline)
                .padding(.bottom, 5)
            
            // 手动构建子任务视图列表
            VStack(spacing: 8) {
                if goal.subTasks.isEmpty {
                    Text("没有子任务")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    let tasksToShow = min(goal.subTasks.count, 20) // 限制显示数量
                    ForEach(0..<tasksToShow, id: \.self) { i in
                        let subTask = goal.subTasks[i]
                        subTaskItemView(subTask)
                    }
                    
                    if goal.subTasks.count > 20 {
                        Text("还有\(goal.subTasks.count - 20)个子任务未显示...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 5)
    }
    
    // 辅助方法：子任务项视图
    private func subTaskItemView(_ subTask: SubTask) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // 简化文本和颜色处理
                let textColor = subTask.isOverdue ? Color.red : Color.primary
                Text(subTask.title)
                    .font(.body)
                    .strikethrough(subTask.isCompleted)
                    .foregroundColor(textColor)
                
                // 分解状态文本显示逻辑
                if subTask.isCompleted {
                    // 安全获取完成日期
                    if let completionDate = getCompletionDate(for: subTask) {
                        Text("完成于: \(formattedDate(completionDate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("已完成")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if subTask.isOverdue {
                    Text("超时未完成")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            // 提取子任务状态按钮视图
            subTaskStatusView(for: subTask)
        }
        .padding()
        // 简化背景颜色逻辑
        .background(backgroundColorForSubTask(subTask))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(subTask.isOverdue ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
        )
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
    
    // 辅助方法：根据子任务状态返回背景颜色
    private func backgroundColorForSubTask(_ subTask: SubTask) -> Color {
        if subTask.isOverdue {
            return Color(.systemRed).opacity(0.1)
        } else {
            return Color(.secondarySystemBackground)
        }
    }
    
    // 辅助方法：根据子任务状态返回对应的图标或按钮
    @ViewBuilder
    private func subTaskStatusView(for subTask: SubTask) -> some View {
        if subTask.isCompleted {
            // 显示已完成标记
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if subTask.isOverdue {
            // 显示超时标记
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        } else {
            // 上传按钮
            Button(action: {
                selectedSubTask = subTask
                showingImagePicker = true
            }) {
                Text("上传证明")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
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
                                            ForEach(Array(selectedImagesData.enumerated()), id: \.offset) { index, imageData in
                                                if let uiImage = UIImage(data: imageData) {
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
                            
                            // 描述文本框 - 移除标题，添加占位符
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $proofDescription)
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.systemGray6))
                                    .frame(minHeight: 120, maxHeight: 200)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                                    .padding(.bottom, 10)
                                
                                if proofDescription.isEmpty {
                                    Text("文字描述（可选）")
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
                        Button(action: {
                            submitProof()
                        }) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("提交证明")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedImagesData.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .disabled(selectedImagesData.isEmpty || isSubmitting)
                    }
                }
                .edgesIgnoringSafeArea(.bottom)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled() // 防止用户通过下拉手势关闭
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
                    print("照片加载失败: \(error)")
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
    
    // 提交证明
    private func submitProof() {
        guard let subTask = selectedSubTask, !selectedImagesData.isEmpty else { return }
        
        isSubmitting = true
        
        // 标记子任务为已完成
        subTask.markAsCompleted()
        
        // 保存证明
        viewModel.addCompletionProof(
            to: subTask,
            imagesData: selectedImagesData,
            description: proofDescription
        )
        
        // 保存更改
        viewModel.updateSubTask(subTask)
        
        // 模拟网络延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSubmitting = false
            
            // 检查是否所有子任务都已处理（完成或超时）
            if goal.allSubTasksProcessed {
                // 自动完成目标并进行评估
                completeGoalAndEvaluate()
            } else {
                // 显示成功消息
                alertMessage = "证明上传成功！"
                showAlert = true
                dismiss()
            }
        }
    }
    
    // 完成目标并自动评估
    private func completeGoalAndEvaluate() {
        // 更新目标状态为评估中
        viewModel.completeGoal(goal)
        
        // 触发AI评估
        AIGoalAnalysisService.shared.evaluateGoal(goal) { comment in
            // 设置评估结果
            viewModel.setGoalEvaluation(goal, comment: comment)
            
            // 显示完成消息并关闭视图
            alertMessage = "恭喜！目标已完成，AI评估已生成。"
            showAlert = true
        }
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
    
    // 日期格式化
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatStartDateDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    let viewModel = GoalViewModel(modelContext: nil)
    let previewGoal = createPreviewGoal()
    
    return NavigationStack {
        GoalExecutionView(viewModel: viewModel, goal: previewGoal)
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
    let subTask1 = SubTask(title: "设计UI")
    subTask1.markAsCompleted()
    subTask1.goal = previewGoal
    
    let subTask2 = SubTask(title: "实现核心功能")
    subTask2.goal = previewGoal
    
    let subTask3 = SubTask(title: "测试和优化")
    subTask3.goal = previewGoal
    
    previewGoal.subTasks = [subTask1, subTask2, subTask3]
    previewGoal.executionStatus = .executing
    previewGoal.startExecutionDate = Date().addingTimeInterval(-86400)
    
    return previewGoal
}
