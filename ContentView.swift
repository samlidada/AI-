//
//  ContentView.swift
//  Project
//
//  Created by 李大大 on 2025/4/3.
//

import SwiftUI
import SwiftData
import AuthenticationServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var timerManager: TimerManager
    @StateObject private var viewModel = GoalViewModel(modelContext: nil)
    @State private var showingAddGoal = false
    @State private var showingMenu = false
    @State private var searchText = ""
    @EnvironmentObject private var userManager: UserManager
    
    // 添加标志位判断是否处于审核环境
    private var isInReviewMode: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.object(forInfoDictionaryKey: "AppReviewMode") as? Bool ?? false
        #endif
    }
    
    // 当环境中的modelContext可用时，更新viewModel
    private func updateViewModel() {
        // 直接更新，不需要错误处理
        viewModel.modelContext = modelContext
        
        // 让TimerManager更新所有管理中目标的计时器状态
        timerManager.updateGoalsTimerState(modelContext: modelContext)
        
        // 然后刷新所有目标
        viewModel.fetchGoals()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 主内容区
                GoalListView(viewModel: viewModel, searchText: searchText)
                
                // 底部添加按钮
                VStack {
                    Divider()
                    HStack {
                        Spacer()
                        
                        // 显示目标总数
                        Text("\(viewModel.goals.count) 个目标")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .frame(height: 50)
                }
            }
            .navigationTitle("目标清单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        showingMenu = true
                    }) {
                        Image(systemName: "line.horizontal.3")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showingAddGoal = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingMenu) {
                MenuView()
            }
            .fullScreenCover(isPresented: $showingAddGoal) {
                AddGoalView(viewModel: viewModel)
            }
            .searchable(text: $searchText, prompt: "搜索目标")
        }
        .onAppear {
            updateViewModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AppStoreReviewLogin"))) { _ in
            // 当检测到App Store审核账号登录时，自动创建测试数据
            if userManager.isReviewAccount {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    viewModel.createTestData(for: "appreview@goalapp.test")
                }
            }
        }
    }
}

// 目标列表视图
struct GoalListView: View {
    @ObservedObject var viewModel: GoalViewModel
    var searchText: String
    
    var filteredSections: [DateSection] {
        if searchText.isEmpty {
            return viewModel.goalsByDateSection()
        } else {
            let filteredGoals = viewModel.goals.filter { goal in
                goal.title.localizedCaseInsensitiveContains(searchText) ||
                goal.goalDescription.localizedCaseInsensitiveContains(searchText)
            }
            return [DateSection(title: "搜索结果", goals: filteredGoals)]
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredSections) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.goals) { goal in
                        GoalRowView(goal: goal, viewModel: viewModel)
                            .swipeActions(edge: .trailing) {
                                if goal.status == .notStarted && viewModel.goals.count > 1 {
                                    Button(action: {
                                        viewModel.deleteGoal(goal)
                                    }) {
                                        Label("删除", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                    }
                }
            }
        }
        .overlay {
            if viewModel.goals.isEmpty {
                ContentUnavailableView {
                    Label("暂无目标", systemImage: "checklist")
                } description: {
                    Text("点击底部 + 按钮添加新目标")
                }
            }
        }
        .refreshable {
            viewModel.fetchGoals()
        }
    }
}

// 目标行视图
struct GoalRowView: View {
    let goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    
    var body: some View {
        NavigationLink(destination: GoalDetailView(viewModel: viewModel, goal: goal)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(goal.title)
                        .font(.headline)
                        .strikethrough(goal.isCompleted)
                    
                    Spacer()
                    
                    // 删除优先级标识
                }
                
                if !goal.goalDescription.isEmpty {
                    Text(goal.goalDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    // 状态指示器
                    statusIndicator
                    
                    Spacer()
                    
                    // 倒计时
                    countdownIndicator
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(goal.isCompleted ? 0.6 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // 状态指示器
    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // 优先显示"未按时完成"状态
            if goal.status == .overdue {
                Text(goal.status.rawValue)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            // 其次按执行状态显示
            else if goal.executionStatus == .evaluating || goal.executionStatus == .completed {
                // 评估中或已完成状态
                Text(goal.executionStatus.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !goal.subTasks.isEmpty && goal.executionStatus == .planning {
                // 规划中状态
                Text("规划中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if goal.executionStatus == .executing {
                // 执行中状态
                Text("执行中")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // 默认状态
                Text(goal.status.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // 倒计时指示器
    private var countdownIndicator: some View {
        Group {
            if goal.status == .overdue && goal.executionStatus == .completed {
                // 已评估但未按时完成的目标
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                    Text("未按时完成")
                        .font(.caption)
                }
                .foregroundColor(.red)
            }
            else if goal.isCompleted, let completedDate = goal.completedDate {
                // 普通完成显示
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption2)
                    Text("已完成于 \(formattedDate(completedDate))")
                        .font(.caption)
                }
                .foregroundColor(.green)
            } else if let daysRemaining = goal.daysRemaining {
                if daysRemaining > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text("还剩 \(daysRemaining) 天")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } else if daysRemaining == 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption2)
                        Text("今天到期")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption2)
                        Text("已逾期 \(abs(daysRemaining)) 天")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    // 状态颜色
    private var statusColor: Color {
        // 优先检查基础状态
        if goal.status == .overdue {
            return .red
        }
        
        // 其次根据执行状态判断
        switch goal.executionStatus {
        case .planning:
            return .purple
        case .executing:
            return .blue
        case .evaluating:
            return .orange
        case .completed:
            // 已完成状态使用绿色
            return .green
        }
    }
    
    // 日期格式化
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// 添加目标视图
struct AddGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: GoalViewModel
    
    @State private var description = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showKeyboard = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // 背景色
                    Color(.systemBackground)
                        .edgesIgnoringSafeArea(.all)
                    
                    // 文本编辑区域
                    TextEditor(text: $description)
                        .focused($isTextFieldFocused)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .font(.body)
                        .padding(.top, 10)
                        .padding(.horizontal, 20)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    // 占位文本
                    if description.isEmpty {
                        Text("输入您的目标...")
                            .font(.body)
                            .foregroundColor(Color(.placeholderText))
                            .padding(.top, 16)
                            .padding(.leading, 24)
                            .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle("新目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        // 先将键盘隐藏，然后淡出界面
                        isTextFieldFocused = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            showKeyboard = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        // 先将键盘隐藏，然后淡出界面
                        isTextFieldFocused = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            showKeyboard = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            saveGoal()
                        }
                    }
                    .disabled(description.isEmpty)
                    .font(.headline)
                    .foregroundColor(description.isEmpty ? .gray : .blue)
                }
            }
            .onAppear {
                // 稍微延迟键盘出现，先让界面渲染完毕
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeIn(duration: 0.2)) {
                        showKeyboard = true
                        isTextFieldFocused = true
                    }
                }
            }
        }
        .transition(.opacity)
    }
    
    private func saveGoal() {
        // 使用描述作为标题，其他参数设为默认值
        viewModel.addGoal(
            title: description,
            goalDescription: "",
            priority: .standard,
            targetDate: nil
        )
        dismiss()
    }
}

// 菜单视图
struct MenuView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var userManager = UserManager.shared
    @State private var showingLogoutAlert = false
    @State private var showingProfileEdit = false
    
    var body: some View {
        NavigationStack {
            List {
                // 用户配置区
                Section {
                    if userManager.isLoggedIn {
                        VStack {
                            HStack {
                                // 显示用户头像，点击进入个人资料编辑页面
                                Button(action: {
                                    showingProfileEdit = true
                                }) {
                                    if let avatar = userManager.userAvatar {
                                        Image(uiImage: avatar)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 50))
                                            .foregroundColor(.blue)
                                    }
                                }
                                
                                // 用户名和邮箱信息
                                Button(action: {
                                    showingProfileEdit = true
                                }) {
                                    VStack(alignment: .leading) {
                                        Text(userManager.displayName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if !userManager.userEmail.isEmpty {
                                            Text(userManager.userEmail)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // 箭头指示符
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showingProfileEdit = true
                            }
                        }
                    } else {
                        NavigationLink(destination: LoginView()) {
                            HStack {
                                Image(systemName: "person.circle")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading) {
                                    Text("未登录")
                                        .font(.headline)
                                    Text("点击登录或注册")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                
                // 功能区
                Section {
                    NavigationLink(destination: DataAnalysisView()) {
                        Label("数据分析", systemImage: "chart.bar")
                    }
                }
                
                // 用户协议和隐私政策
                Section(header: Text("法律条款")) {
                    NavigationLink(destination: LegalDocumentView(title: "用户协议", documentPath: "UserAgreement.md")) {
                        Label("用户协议", systemImage: "doc.text")
                    }
                    
                    NavigationLink(destination: LegalDocumentView(title: "隐私政策", documentPath: "PrivacyPolicy.md")) {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                }
            }
            .navigationTitle("菜单")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .alert("确定要退出登录吗？", isPresented: $showingLogoutAlert) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    userManager.logout()
                }
            } message: {
                Text("退出登录后，您的数据将不会自动同步")
            }
            .sheet(isPresented: $showingProfileEdit) {
                ProfileEditView()
            }
            .onAppear {
                // 刷新用户状态
                _ = userManager.isLoggedIn
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDidLogin"))) { _ in
                // 强制刷新视图
                userManager.objectWillChange.send()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserAvatarDidChange"))) { _ in
                // 头像更新时刷新视图
                userManager.objectWillChange.send()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserDidUpdate"))) { _ in
                // 用户信息更新时刷新视图
                userManager.objectWillChange.send()
            }
        }
    }
}

#Preview {
    ContentView()
}
