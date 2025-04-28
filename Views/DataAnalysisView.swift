import SwiftUI
import SwiftData
import Charts

struct DataAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var viewModel: AnalyticsViewModel
    @State private var selectedTimeRange: TimeRange = .month
    @State private var isRefreshing = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // 顶部统计卡片
                StatisticsCardView(viewModel: viewModel)
                
                // 效率分析
                ChartSection(
                    title: "执行效率分析",
                    chart: EfficiencyAnalysisChart(data: viewModel.efficiencyData)
                )
                
                // 个人洞察与建议
                InsightsCardView(insights: viewModel.personalInsights)
            }
            .padding()
        }
        .navigationTitle("数据分析")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(TimeRange.allCases) { range in
                        Button(range.rawValue) {
                            selectedTimeRange = range
                            viewModel.loadAnalyticsData(for: range)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedTimeRange.rawValue)
                        Image(systemName: "chevron.down")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
            }
        }
        .refreshable {
            isRefreshing = true
            viewModel.loadAnalyticsData(for: selectedTimeRange)
            isRefreshing = false
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
        }
        .alert("加载失败", isPresented: Binding<Bool>(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .onChange(of: selectedTimeRange) { 
            viewModel.loadAnalyticsData(for: selectedTimeRange)
        }
    }
}

// 统计卡片视图
struct StatisticsCardView: View {
    @ObservedObject var viewModel: AnalyticsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Text("目标统计")
                    .font(.headline)
                Spacer()
            }
            .padding([.horizontal, .top])
            
            // 指标行
            HStack(spacing: 20) {
                // 总目标数
                StatItem(
                    title: "总目标数",
                    value: "\(viewModel.totalGoals)",
                    icon: "target",
                    color: .blue
                )
                
                // 已完成
                StatItem(
                    title: "已完成",
                    value: "\(viewModel.completedGoals)",
                    icon: "checkmark.circle",
                    color: .green
                )
                
                // 进行中
                StatItem(
                    title: "进行中",
                    value: "\(viewModel.activeGoals)",
                    icon: "hourglass",
                    color: .orange
                )
                
                // 未按时完成
                StatItem(
                    title: "未按时完成",
                    value: "\(viewModel.overdueGoals)",
                    icon: "exclamationmark.circle",
                    color: .red
                )
            }
            .padding()
            
            Divider()
                .padding(.horizontal)
            
            // 指标行2
            HStack(spacing: 15) {
                // 平均完成时间
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("平均完成时间")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.averageTimeToComplete)
                            .font(.headline)
                    }
                }
                
                Spacer()
                
                // 最长目标间隔
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.purple)
                        VStack(alignment: .leading) {
                        Text("最长目标间隔")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        Text("\(viewModel.efficiencyData.maxGoalGapDays)天")
                                .font(.headline)
                    }
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// 统计项
struct StatItem: View {
    var title: String
    var value: String
    var icon: String
    var color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// 图表区域
struct ChartSection<ChartContent: View>: View {
    var title: String
    var chart: ChartContent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.leading)
            
            chart
                .frame(height: 250)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
        }
    }
}

// 效率分析图表
struct EfficiencyAnalysisChart: View {
    var data: EfficiencyData
    
    var body: some View {
        VStack(spacing: 15) {
            // 按时完成率
            VStack(spacing: 5) {
                HStack {
                    Text("按时完成率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(data.onTimeCompletionRate * 100))%")
                        .font(.caption)
                        .bold()
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .frame(width: geometry.size.width, height: 8)
                            .opacity(0.1)
                            .foregroundColor(.gray)
                        
                        Rectangle()
                            .frame(width: geometry.size.width * CGFloat(data.onTimeCompletionRate), height: 8)
                            .foregroundColor(.green)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 8)
            }
            
            // 超时率
            VStack(spacing: 5) {
                HStack {
                    Text("未按时完成率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(data.overdueRate * 100))%")
                        .font(.caption)
                        .bold()
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .frame(width: geometry.size.width, height: 8)
                            .opacity(0.1)
                            .foregroundColor(.gray)
                        
                        Rectangle()
                            .frame(width: geometry.size.width * CGFloat(data.overdueRate), height: 8)
                            .foregroundColor(.red)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 8)
            }
            
            // 目标创建频率
            VStack(spacing: 5) {
                HStack {
                    Text("目标创建频率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f个/周", data.goalsPerWeek))
                        .font(.caption)
                        .bold()
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .frame(width: geometry.size.width, height: 8)
                            .opacity(0.1)
                            .foregroundColor(.gray)
                        
                        Rectangle()
                            .frame(width: geometry.size.width * min(CGFloat(data.goalsPerWeek/5), 1.0), height: 8)
                            .foregroundColor(.purple)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 8)
            }
            
            // 目标持续度
            VStack(spacing: 5) {
                HStack {
                    Text("目标持续周期")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f天", data.averageCompletionDays))
                        .font(.caption)
                        .bold()
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .frame(width: geometry.size.width, height: 8)
                            .opacity(0.1)
                            .foregroundColor(.gray)
                        
                        // 将天数映射到宽度，最多不超过整个宽度
                        let maxDays: CGFloat = 30 // 假设30天是最大参考值
                        let daysWidth = min(geometry.size.width * CGFloat(data.averageCompletionDays) / maxDays, geometry.size.width)
                        
                        Rectangle()
                            .frame(width: daysWidth, height: 8)
                            .foregroundColor(.blue)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 8)
            }
        }
    }
}

// 洞察卡片视图
struct InsightsCardView: View {
    var insights: [Insight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("个人洞察")
                .font(.headline)
                .padding(.leading)
            
            if insights.isEmpty {
                Text("随着您使用应用并完成更多目标，这里将显示个性化的洞察和建议。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            } else {
                VStack(spacing: 12) {
                    ForEach(insights) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.icon)
                                .font(.headline)
                                .foregroundColor(insight.color)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.subheadline)
                                    .bold()
                                
                                Text(insight.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(insight.color.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}

struct DataAnalysisView_Previews: PreviewProvider {
    static var previews: some View {
        DataAnalysisView()
    }
} 