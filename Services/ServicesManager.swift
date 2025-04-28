import Foundation
import SwiftData

/// 服务管理器，用于初始化和管理所有服务
class ServicesManager: ObservableObject {
    static let shared = ServicesManager()
    
    // API 服务
    let siliconFlowAPIService: SiliconFlowAPIService
    
    // 目标分析服务
    let aiGoalAnalysisService: AIGoalAnalysisService
    
    // API配置
    private let apiKey = "sk-ymyhdfwdhgkksjnakhrimqgdfxpebirmpwemkkrkejcjnben"
    private let apiEndpoint = "https://api.siliconflow.cn/v1/chat/completions"
    
    // 其他服务可以在这里添加
    
    private init() {
        // 初始化API服务
        self.siliconFlowAPIService = SiliconFlowAPIService(apiKey: apiKey, endpoint: apiEndpoint)
        
        // 初始化目标分析服务
        self.aiGoalAnalysisService = AIGoalAnalysisService.shared
        
        // 打印初始化信息
        print("服务管理器已初始化")
        print("使用API模型: \(siliconFlowAPIService.currentModelName)")
    }
} 