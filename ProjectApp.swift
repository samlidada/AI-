//
//  ProjectApp.swift
//  Project
//
//  Created by 李大大 on 2025/4/3.
//

import SwiftUI
import SwiftData
import Foundation

@main
struct ProjectApp: App {
    // 使用 @AppStorage 存储模型版本，无需直接操作UserDefaults
    @AppStorage("ModelVersion") private var modelVersion = "1.0.3"
    
    // 将resetDatabase设为false，避免每次启动都清空数据库
    // 如果需要重置，可以临时改为true
    private let resetDatabase = false
    
    // 使用StateObject确保在App的生命周期内只初始化一次
    @StateObject private var databaseManager = DatabaseManager()
    
    // 初始化TimerManager
    @StateObject private var timerManager = TimerManager.shared
    
    // 添加用户管理器
    @StateObject private var userManager = UserManager.shared
    
    // 添加分析视图模型
    @StateObject private var analyticsViewModel = AnalyticsViewModel()
    
    // 添加服务管理器
    @StateObject private var servicesManager = ServicesManager.shared
    
    // 控制是否显示启动屏幕
    @State private var showLaunchScreen = true
    
    // 检查用户是否已同意协议
    @AppStorage("hasAgreedToTerms") private var hasAgreedToTerms = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasAgreedToTerms {
                    ContentView()
                        .modelContainer(databaseManager.container)
                        .environmentObject(timerManager) // 通过环境对象提供TimerManager
                        .environmentObject(userManager) // 通过环境对象提供UserManager
                        .environmentObject(analyticsViewModel) // 通过环境对象提供AnalyticsViewModel
                        .onAppear {
                            // 初始化服务
                            _ = servicesManager
                            
                            // 如果需要重置数据库，在这里执行
                            if resetDatabase {
                                Task {
                                    try? await databaseManager.resetAllData()
                                }
                            }
                            
                            // 延迟2秒后关闭启动屏幕
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showLaunchScreen = false
                                }
                            }
                        }
                } else {
                    AgreementView()
                }
                
                // 显示自定义启动屏幕覆盖层
                if showLaunchScreen && hasAgreedToTerms {
                    // 启动页面覆盖
                    ZStack {
                        Color(.black)
                            .edgesIgnoringSafeArea(.all)
                        
                        Image("LaunchImage")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack {
                            Spacer()
                            
                            // 在底部添加一个加载指示器
                            VStack(spacing: 15) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("2025启动中...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(.bottom, 100)
                            
                            Spacer()
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1) // 确保启动屏幕在最上层
                }
            }
        }
    }
}

// 将数据库管理逻辑移到单独的类中
class DatabaseManager: ObservableObject {
    let container: ModelContainer
    
    init() {
        do {
            self.container = try ModelContainer(
                for: Goal.self, SubTask.self, CompletionProof.self, ProofImage.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
            print("✅ 成功创建持久化存储数据库")
        } catch {
            print("⚠️ 创建持久化数据库失败: \(error)")
            print("尝试使用内存存储模式...")
            
            do {
                self.container = try ModelContainer(
                    for: Goal.self, SubTask.self, CompletionProof.self, ProofImage.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                print("✅ 成功创建内存数据库")
            } catch {
                fatalError("无法创建任何类型的ModelContainer: \(error)")
            }
        }
    }
    
    // 重置所有数据
    @MainActor func resetAllData() async throws {
        let context = container.mainContext
        
        // 删除所有数据
        try context.delete(model: CompletionProof.self)
        try context.delete(model: ProofImage.self)
        try context.delete(model: SubTask.self)
        try context.delete(model: Goal.self)
        print("数据库已重置")
    }
}
