import Foundation
import SwiftData
import UIKit

/// A hand-drawn signature, stored as a transparent PNG and stamped onto exported timesheets.
@Model
final class SavedSignature {
    var id: UUID
    var name: String
    @Attribute(.externalStorage) var imageData: Data
    var createdAt: Date

    init(id: UUID = UUID(), name: String, imageData: Data, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.createdAt = createdAt
    }

    var image: UIImage? { UIImage(data: imageData) }
}
