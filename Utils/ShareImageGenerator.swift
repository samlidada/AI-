import SwiftUI
import UIKit

/// 分享图片生成器
/// 用于将SwiftUI视图转换为可分享的UIImage
struct ShareImageGenerator {
    
    /// 将SwiftUI视图转换为UIImage，支持自适应高度
    /// - Parameters:
    ///   - view: 要转换的SwiftUI视图
    ///   - width: 图片宽度，默认为390（iPhone 13 Pro宽度）
    /// - Returns: 生成的UIImage，如果转换失败则返回nil
    static func generateImage(from view: some View, width: CGFloat = 390) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        
        // 首先计算视图的理想尺寸
        let targetSize = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        
        // 配置视图控制器的尺寸
        controller.view.frame = CGRect(origin: .zero, size: targetSize)
        controller.view.backgroundColor = .clear
        
        // 创建一个与视图实际大小相符的渲染上下文
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
    
    /// 创建并显示分享界面
    /// - Parameters:
    ///   - image: 要分享的图片
    ///   - sourceRect: 分享弹出框的来源位置（iPad上需要）
    ///   - sourceView: 分享弹出框的来源视图（iPad上需要）
    ///   - completion: 分享完成后的回调
    static func shareImage(_ image: UIImage, from sourceRect: CGRect, in sourceView: UIView, completion: @escaping () -> Void) {
        let items: [Any] = [image]
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // 配置iPad上的弹出框位置
        if let popoverController = activityVC.popoverPresentationController {
            popoverController.sourceRect = sourceRect
            popoverController.sourceView = sourceView
        }
        
        // 寻找当前视图控制器并显示分享界面
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var currentVC = rootVC
            while let presentedVC = currentVC.presentedViewController {
                currentVC = presentedVC
            }
            
            currentVC.present(activityVC, animated: true)
            
            // 设置分享完成的回调
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                completion()
            }
        }
    }
    
    /// 创建一个分享海报并显示分享界面
    /// - Parameters:
    ///   - isUserLoggedIn: 用户是否已登录
    ///   - userName: 用户名称
    ///   - userAvatar: 用户头像
    ///   - goal: 目标对象，用于生成海报内容
    ///   - contentView: 自定义内容视图，如果提供则优先使用此视图而不是goal
    ///   - sourceRect: 分享弹出框的来源位置
    ///   - sourceView: 分享弹出框的来源视图
    ///   - completion: 分享完成后的回调
    static func sharePoster(
        isUserLoggedIn: Bool,
        userName: String? = nil,
        userAvatar: UIImage? = nil,
        goal: Goal? = nil,
        contentView: AnyView? = nil,
        from sourceRect: CGRect,
        in sourceView: UIView,
        completion: @escaping () -> Void
    ) {
        // 创建海报视图
        let posterView = SharePosterView(
            isUserLoggedIn: isUserLoggedIn,
            userName: userName,
            userAvatar: userAvatar,
            goal: goal,
            contentView: contentView
        )
        
        // 生成图片，使用自适应高度
        if let image = generateImage(from: posterView) {
            // 显示分享界面
            shareImage(image, from: sourceRect, in: sourceView, completion: completion)
        } else {
            // 图片生成失败
            completion()
        }
    }
} 