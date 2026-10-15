import SwiftUI
import UIKit

/// Asynchronously loaded screenshot thumbnail that fills its frame. Decorative for VoiceOver;
/// the containing view provides the label.
struct ThumbnailImage: View {
  let id: String
  /// Expected display size in points; converted to pixels for the request.
  var pointSize = CGSize(width: 120, height: 213)

  @Environment(AppModel.self) private var model
  @Environment(\.displayScale) private var displayScale
  @State private var image: UIImage?

  var body: some View {
    Theme.placeholder
      .overlay {
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          Image(systemName: "photo")
            .font(.title3)
            .foregroundStyle(.tertiary)
        }
      }
      .clipped()
      .accessibilityHidden(true)
      .task(id: id) {
        image = nil
        let pixels = CGSize(
          width: pointSize.width * displayScale, height: pointSize.height * displayScale)
        image = await model.thumbnail(for: id, size: pixels)
      }
  }
}
