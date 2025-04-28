import SwiftUI
import SwiftData

struct GoalEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: GoalViewModel
    var goal: Goal
    
    @State private var description: String
    @FocusState private var isTextFieldFocused: Bool
    @State private var showKeyboard = false
    
    // 初始化状态
    init(viewModel: GoalViewModel, goal: Goal) {
        self.viewModel = viewModel
        self.goal = goal
        
        // 初始化状态变量
        _description = State(initialValue: goal.title)
    }
    
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
            .navigationTitle("编辑目标")
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
                    Button("保存") {
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
        // 更新目标属性
        goal.title = description
        goal.goalDescription = ""
        
        // 保存更改
        viewModel.updateGoal(goal)
        dismiss()
    }
}

#Preview {
    // 创建一个模拟的Goal和ViewModel用于预览
    let previewGoal = Goal(
        title: "10天之内开发一个关于目标管理的应用",
        goalDescription: "",
        priority: .standard
    )
    
    let viewModel = GoalViewModel(modelContext: nil)
    
    return GoalEditView(viewModel: viewModel, goal: previewGoal)
} 