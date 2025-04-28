import SwiftUI

/// 分享海报视图
/// 用于生成包含用户信息和品牌元素的分享海报
struct SharePosterView: View {
    // MARK: - 属性
    
    /// 用户是否已登录
    var isUserLoggedIn: Bool
    
    /// 用户名称
    var userName: String?
    
    /// 用户头像
    var userAvatar: UIImage?
    
    /// 目标对象
    var goal: Goal?
    
    /// 自定义内容视图
    var contentView: AnyView?
    
    // 添加调试标记
    @State private var logoLoadFailed = false
    @State private var companyLogoLoadFailed = false
    
    // MARK: - 初始化方法
    
    /// 创建分享海报视图
    /// - Parameters:
    ///   - isUserLoggedIn: 用户是否已登录
    ///   - userName: 用户名称，未登录用户可为nil
    ///   - userAvatar: 用户头像，未登录用户可为nil
    ///   - goal: 目标对象，用于展示目标信息
    ///   - contentView: 自定义内容视图，若提供则优先使用
    init(isUserLoggedIn: Bool, userName: String? = nil, userAvatar: UIImage? = nil, goal: Goal? = nil, contentView: AnyView? = nil) {
        self.isUserLoggedIn = isUserLoggedIn
        self.userName = userName
        self.userAvatar = userAvatar
        self.goal = goal
        self.contentView = contentView
    }
    
    // MARK: - 计算属性
    
    /// 显示的用户名
    private var displayName: String {
        if isUserLoggedIn, let name = userName, !name.isEmpty {
            return name
        }
        return "未登录用户"
    }
    
    /// 显示的头像
    private var displayAvatar: Image {
        if isUserLoggedIn, let avatar = userAvatar {
            return Image(uiImage: avatar)
        }
        // 使用SF Symbol作为备选
        return logoLoadFailed ? Image(systemName: "person.circle.fill") : Image("Logo")
    }
    
    // 子任务颜色数组
    private let taskColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .yellow, .teal, .indigo
    ]
    
    // MARK: - 视图组件
    
    /// 用户头像视图
    private var userAvatarView: some View {
        displayAvatar
            .resizable()
            .scaledToFill()
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
    
    /// 检查Logo是否加载成功
    private func checkLogoLoading() {
        if !isUserLoggedIn && userAvatar == nil {
            if UIImage(named: "Logo") == nil {
                logoLoadFailed = true
                print("⚠️ Logo图像加载失败")
            } else {
                print("✅ Logo图像加载成功")
            }
        }
    }
    
    /// 公司Logo视图
    private var companyLogoView: some View {
        Group {
            if companyLogoLoadFailed {
                // 使用SF Symbol作为备选
                Image(systemName: "building.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .foregroundColor(.white)
            } else {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
            }
        }
    }
    
    /// 检查公司Logo是否加载成功
    private func checkCompanyLogoLoading() {
        if UIImage(named: "Logo") == nil {
            companyLogoLoadFailed = true
            print("⚠️ Logo图像加载失败")
        } else {
            print("✅ Logo图像加载成功")
        }
    }
    
    /// 自定义格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日"
        return formatter.string(from: date)
    }
    
    /// 自定义格式化日期和时间
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    /// 格式化分钟显示
    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 1 {
            return "不到1分钟"
        } else if minutes == 1 {
            return "1分钟"
        } else {
            return "\(minutes)分钟"
        }
    }
    
    /// 顶部公司标识栏
    private var companyHeader: some View {
        HStack(spacing: 8) {
            companyLogoView
                .frame(width: 30, height: 30)
            
            Text("大project, 点滴前行")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }
    
    /// 海报标题
    private var posterTitle: some View {
        Text("我又解锁了一个目标")
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(.white)
            .padding(.top, 30)
            .padding(.bottom, 50)
            .fixedSize(horizontal: false, vertical: true) // 确保文本能够自适应高度
    }
    
    /// 自定义内容视图的包装
    @ViewBuilder
    private var customContentWrapper: some View {
        if let customView = contentView {
            customView
        } else {
            EmptyView()
        }
    }
    
    /// 目标使用时间文本
    @ViewBuilder
    private func goalTimeText(_ goal: Goal) -> some View {
        // 计算所有已完成子任务的用时总和
        let totalUsedMinutes = goal.subTasks.reduce(0) { total, subTask in
            if let remainingTime = subTask.remainingTimeWhenCompleted {
                let estimatedSeconds = subTask.estimatedHours * 60 * 60
                let remainingSeconds = remainingTime
                let usedSeconds = estimatedSeconds - remainingSeconds
                let usedMinutes = max(1, Int(usedSeconds / 60))
                return total + usedMinutes
            }
            return total
        }
        
        Text("\(formatMinutes(totalUsedMinutes))")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
    }
    
    /// 创建基于目标的信息视图
    @ViewBuilder
    private var targetGoalInfoView: some View {
        if let goal = goal {
            VStack(spacing: 15) {
                // 目标标题 - 完整显示
                Text(goal.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 25)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true) // 允许标题垂直扩展
                
                // 开始和结束时间信息
                if let startDate = goal.startExecutionDate,
                   let endDate = goal.completedDate {
                    HStack(spacing: 25) {
                        // 开始时间
                        VStack(spacing: 3) {
                            Text("开始时间")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                            Text(formatDateTime(startDate))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                        
                        // 分隔线
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: 24)
                        
                        // 结束时间
                        VStack(spacing: 3) {
                            Text("完成时间")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.8))
                            Text(formatDateTime(endDate))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    .padding(.bottom, 20)
                }
                
                // 子任务环绕图
                GeometryReader { geo in
                    ZStack {
                        // 中央圆形 - 总时间统计
                        Circle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 120, height: 120)
                            .overlay(
                                // 添加按子任务完成时间比例的填充
                                ZStack {
                                    // 计算每个子任务的用时比例并绘制对应弧形
                                    ForEach(0..<min(goal.subTasks.count, 8), id: \.self) { index in
                                        let subTask = goal.subTasks[index]
                                        if subTask.remainingTimeWhenCompleted != nil {
                                            let (startAngle, endAngle) = calculateSubTaskAngle(goal: goal, subTaskIndex: index)
                                            
                                            Circle()
                                                .trim(from: startAngle / 360, to: endAngle / 360)
                                                .stroke(
                                                    taskColors[index % taskColors.count],
                                                    style: StrokeStyle(lineWidth: 8, lineCap: .butt)
                                                )
                                                .rotationEffect(.degrees(-90))
                                                .frame(width: 100, height: 100)
                                        }
                                    }
                                    
                                    // 文字信息放在最上层
                                    VStack(spacing: 4) {
                                        Text("总用时")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                        
                                        goalTimeText(goal)
                                    }
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.2))
                                            .frame(width: 90, height: 90)
                                    )
                                }
                            )
                        
                        // 子任务分布图 - 使用气泡对话样式
                        ForEach(0..<min(goal.subTasks.count, 8), id: \.self) { index in
                            let subTask = goal.subTasks[index]
                            let angle = Double(index) * (360.0 / Double(min(goal.subTasks.count, 8)))
                            // 根据子任务数量和容器宽度动态调整半径
                            let containerWidth = geo.size.width
                            let maxRadius = min(containerWidth, 390) / 2 - 50 // 减去边距
                            let radius: CGFloat = goal.subTasks.count <= 4 ? maxRadius * 0.7 : maxRadius
                            
                            let xPos = sin(angle * .pi / 180) * radius
                            let yPos = -cos(angle * .pi / 180) * radius
                            
                            // 气泡对话框
                            ZStack {
                                // 气泡背景
                                RoundedRectangle(cornerRadius: 15)
                                    .fill(taskColors[index % taskColors.count].opacity(0.7))
                                    .frame(width: 110, height: 80)
                                    .overlay(
                                        // 添加连接线 - 简化为函数调用避免复杂表达式
                                        ConnectingLine(
                                            angle: angle,
                                            color: taskColors[index % taskColors.count].opacity(0.7),
                                            lineWidth: 2.0,
                                            lineStyle: .dashed(dashPattern: [5, 3]),
                                            insetDistance: 10,
                                            outsetDistance: 5
                                        )
                                    )
                                
                                // 内容
                                VStack(spacing: 3) {
                                    // 步骤编号
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Text("\(index + 1)")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(taskColors[index % taskColors.count])
                                        )
                                    
                                    // 子任务名称完整显示
                                    Text(subTask.title)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 100)
                                    
                                    // 用时
                                    if let remainingTime = subTask.remainingTimeWhenCompleted {
                                        // 计算实际用时（预计总秒数 - 剩余秒数）
                                        let estimatedSeconds = subTask.estimatedHours * 60 * 60
                                        let remainingSeconds = remainingTime
                                        let usedSeconds = estimatedSeconds - remainingSeconds
                                        
                                        // 转换为分钟
                                        let usedMinutes = max(1, Int(usedSeconds / 60))
                                        
                                        Text("用时 \(formatMinutes(usedMinutes))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.9))
                                    } else {
                                        // 估计时间转换为分钟
                                        let estimatedMinutes = subTask.estimatedHours * 60
                                        
                                        Text("计划 \(formatMinutes(estimatedMinutes))")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                            .offset(x: xPos, y: yPos)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 380)
                    .position(x: geo.size.width / 2, y: 190) // 将ZStack居中
                }
                .frame(height: 380)
                .padding(.bottom, 20) // 添加底部间距
            }
        } else {
            // 如果没有目标，显示一个空视图
            EmptyView()
        }
    }
    
    /// 目标信息视图
    @ViewBuilder
    private var goalInfoView: some View {
        if contentView != nil {
            customContentWrapper
        } else if goal != nil {
            targetGoalInfoView
        } else {
            // 如果两者都没有，显示一个占位视图
            VStack {
                Text("暂无目标数据")
                    .foregroundColor(.white)
            }
            .frame(minHeight: 100) // 改为最小高度，而不是固定高度
        }
    }
    
    // MARK: - 视图主体
    
    var body: some View {
        ScrollView {
            ZStack {
                // 背景渐变
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.7),
                        Color.blue.opacity(0.9)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .edgesIgnoringSafeArea(.all)
                
                // 装饰性圆形背景 - 使用GeometryReader实现相对定位
                GeometryReader { geometry in
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 300, height: 300)
                        .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.2)
                    
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 200, height: 200)
                        .position(x: geometry.size.width * 0.1, y: geometry.size.height * 0.8)
                }
                
                // 主要内容
                VStack(spacing: 0) {
                    // 顶部公司标识
                    companyHeader
                    
                    // 中间内容区
                    VStack(spacing: 0) {
                        // 用户头像和姓名居中显示
                        VStack(spacing: 10) {
                            // 用户头像
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                                .overlay(
                                    userAvatarView
                                        .frame(width: 56, height: 56)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                            
                            // 用户名称
                            Text(displayName)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 15)
                        
                        // 标题
                        posterTitle
                        
                        // 目标信息区域
                        goalInfoView
                        
                        Spacer(minLength: 20)
                    }
                }
                .onAppear {
                    print("📱 SharePosterView已加载")
                    checkLogoLoading()
                    checkCompanyLogoLoading()
                }
            }
            .frame(width: 390)
            .frame(minHeight: 720) // 改为最小高度而不是固定高度
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
    
    /// 计算子任务在圆环中的角度范围
    private func calculateSubTaskAngle(goal: Goal, subTaskIndex: Int) -> (Double, Double) {
        // 1. 计算所有子任务的总用时（分钟）
        let totalUsedMinutes = goal.subTasks.reduce(0) { total, subTask in
            if let remainingTime = subTask.remainingTimeWhenCompleted {
                let estimatedSeconds = subTask.estimatedHours * 60 * 60
                let remainingSeconds = remainingTime
                let usedSeconds = estimatedSeconds - remainingSeconds
                let usedMinutes = max(1, Int(usedSeconds / 60))
                return total + usedMinutes
            }
            return total
        }
        
        // 至少为1分钟，防止除以零
        let totalMinutes = max(1, totalUsedMinutes)
        
        // 2. 计算已完成的子任务用时（分钟）
        var completedSubTasksMinutes: [Int] = []
        
        for i in 0..<min(goal.subTasks.count, 8) {
            let subTask = goal.subTasks[i]
            if let remainingTime = subTask.remainingTimeWhenCompleted {
                let estimatedSeconds = subTask.estimatedHours * 60 * 60
                let remainingSeconds = remainingTime
                let usedSeconds = estimatedSeconds - remainingSeconds
                let usedMinutes = max(1, Int(usedSeconds / 60))
                
                completedSubTasksMinutes.append(usedMinutes)
            } else {
                completedSubTasksMinutes.append(0)
            }
        }
        
        // 3. 计算前面所有子任务的累计时间占比
        var startRatio = 0.0
        for i in 0..<subTaskIndex {
            startRatio += Double(completedSubTasksMinutes[i]) / Double(totalMinutes)
        }
        
        // 4. 计算当前子任务的时间占比
        let currentRatio = Double(completedSubTasksMinutes[subTaskIndex]) / Double(totalMinutes)
        
        // 5. 转换为角度（0-360度）
        let startAngle = startRatio * 360.0
        let endAngle = startAngle + (currentRatio * 360.0)
        
        return (startAngle, endAngle)
    }
}

// MARK: - 预览
#if DEBUG
struct SharePosterView_Previews: PreviewProvider {
    static var previews: some View {
        let demoView = createDemoSharePosterView()
        return demoView
    }
    
    static func createDemoSharePosterView() -> some View {
        // 示例Goal
        let goal = Goal(title: "制作一款APP", goalDescription: "完成一个iOS应用开发")
        
        // 添加示例子任务
        let subTask1 = SubTask(title: "对谈")
        subTask1.goal = goal
        subTask1.order = 0
        subTask1.estimatedHours = 2
        
        let subTask2 = SubTask(title: "所有子任务")
        subTask2.goal = goal
        subTask2.order = 1
        subTask2.estimatedHours = 3
        
        let subTask3 = SubTask(title: "研究")
        subTask3.goal = goal
        subTask3.order = 2
        subTask3.estimatedHours = 1
        
        let subTask4 = SubTask(title: "完成方案")
        subTask4.goal = goal
        subTask4.order = 3
        subTask4.estimatedHours = 2
        
        let subTask5 = SubTask(title: "成果提交")
        subTask5.goal = goal
        subTask5.order = 4
        subTask5.estimatedHours = 1
        
        let subTask6 = SubTask(title: "所有交付时间")
        subTask6.goal = goal
        subTask6.order = 5
        subTask6.estimatedHours = 3
        
        goal.subTasks = [subTask1, subTask2, subTask3, subTask4, subTask5, subTask6]
        
        // 设置开始和完成时间
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .day, value: -10, to: now)!
        
        // 手动设置Goal的属性
        goal.startExecutionDate = startDate
        goal.completedDate = now
        
        return SharePosterView(
            isUserLoggedIn: false,
            goal: goal
        )
    }
}
#endif

// 连接线组件 - 用于简化复杂表达式
struct ConnectingLine: View {
    let angle: Double
    let color: Color
    var lineWidth: CGFloat = 2
    var lineStyle: LineStyle = .solid
    var insetDistance: CGFloat = 20
    var outsetDistance: CGFloat = 0
    
    enum LineStyle {
        case solid
        case dashed(dashPattern: [CGFloat])
    }
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let centerX = geo.size.width / 2
                let centerY = geo.size.height / 2
                
                let lineAngle = (180 - angle.truncatingRemainder(dividingBy: 360)) * .pi / 180
                
                // 内部起点（向内缩进）
                let startX = centerX - CGFloat(sin(lineAngle)) * outsetDistance
                let startY = centerY - CGFloat(cos(lineAngle)) * outsetDistance
                
                // 外部终点（向外延伸）
                let endX = centerX - CGFloat(sin(lineAngle)) * insetDistance
                let endY = centerY - CGFloat(cos(lineAngle)) * insetDistance
                
                path.move(to: CGPoint(x: startX, y: startY))
                path.addLine(to: CGPoint(x: endX, y: endY))
            }
            .stroke(
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: {
                        switch lineStyle {
                        case .solid:
                            return []
                        case .dashed(let dashPattern):
                            return dashPattern
                        }
                    }()
                )
            )
            .foregroundColor(color)
        }
    }
}

// 为LineStyle的dashed情况提供默认值
extension ConnectingLine.LineStyle: Equatable {
    static func == (lhs: ConnectingLine.LineStyle, rhs: ConnectingLine.LineStyle) -> Bool {
        switch (lhs, rhs) {
        case (.solid, .solid):
            return true
        case (.dashed, .dashed):
            return true
        default:
            return false
        }
    }
}

extension ConnectingLine {
    /// 创建虚线样式的连接线
    static func dashed(angle: Double, color: Color, dashPattern: [CGFloat] = [5, 3]) -> ConnectingLine {
        var line = ConnectingLine(angle: angle, color: color)
        line.lineStyle = .dashed(dashPattern: dashPattern)
        return line
    }
} 