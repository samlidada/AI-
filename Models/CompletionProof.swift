import Foundation
import SwiftData

@Model
class CompletionProof {
    var id: UUID
    // 主图片数据 - 兼容旧版本
    var imageData: Data
    // 额外的图片数据
    @Relationship(deleteRule: .cascade)
    var additionalImages: [ProofImage]
    var proofDescription: String?
    var uploadDate: Date
    @Relationship(deleteRule: .nullify)
    var subTask: SubTask?
    
    // 获取所有图片数据，包括主图片和额外图片
    var allImagesData: [Data] {
        var images = [imageData]
        images.append(contentsOf: additionalImages.map { $0.imageData })
        return images
    }
    
    init(imagesData: [Data], description: String? = nil, subTask: SubTask? = nil) {
        self.id = UUID()
        
        // 确保至少有一张图片
        if let firstImage = imagesData.first {
            self.imageData = firstImage
        } else {
            // 如果没有提供图片，创建一个空的Data对象
            self.imageData = Data()
        }
        
        // 先初始化所有基本属性
        self.proofDescription = description
        self.uploadDate = Date()
        self.subTask = subTask
        
        // 处理额外的图片
        self.additionalImages = []
        if imagesData.count > 1 {
            for i in 1..<imagesData.count {
                let proofImage = ProofImage(imageData: imagesData[i])
                self.additionalImages.append(proofImage)
            }
        }
    }
}

// 用于存储额外的图片
@Model
class ProofImage {
    var id: UUID
    var imageData: Data
    var uploadDate: Date
    
    init(imageData: Data) {
        self.id = UUID()
        self.imageData = imageData
        self.uploadDate = Date()
    }
}
