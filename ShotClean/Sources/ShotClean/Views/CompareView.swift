import SwiftUI

/// Two screenshots side by side with synchronized pinch zoom (S6 "So sánh").
struct CompareView: View {
  let keeperID: String
  let otherIDs: [String]

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var otherIndex = 0
  @State private var scale: CGFloat = 1
  @State private var baseScale: CGFloat = 1

  var body: some View {
    NavigationStack {
      VStack(spacing: Theme.Spacing.m) {
        if otherIDs.count > 1 {
          Picker(Strings.Cluster.compareWith, selection: $otherIndex) {
            ForEach(otherIDs.indices, id: \.self) { index in
              Text(Strings.Cluster.photoNumber(index + 2)).tag(index)
            }
          }
          .pickerStyle(.segmented)
        }

        HStack(spacing: Theme.Spacing.s) {
          panel(id: keeperID, caption: Strings.Cluster.keeperTag, isKeeper: true)
          if otherIDs.indices.contains(otherIndex) {
            panel(
              id: otherIDs[otherIndex], caption: Strings.Cluster.photoNumber(otherIndex + 2),
              isKeeper: false)
          }
        }
        .gesture(magnify)
        .onTapGesture(count: 2) {
          scale = 1
          baseScale = 1
        }
      }
      .padding(Theme.Spacing.l)
      .background(Theme.background)
      .navigationTitle(Strings.Cluster.compareTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(Strings.close) { dismiss() }
        }
      }
    }
  }

  private var magnify: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        scale = min(max(baseScale * value.magnification, 1), 5)
      }
      .onEnded { _ in
        baseScale = scale
      }
  }

  private func panel(id: String, caption: String, isKeeper: Bool) -> some View {
    let features = model.features(for: id)
    return VStack(spacing: Theme.Spacing.xs) {
      Color.clear
        .aspectRatio(Theme.thumbnailAspectRatio, contentMode: .fit)
        .overlay {
          ThumbnailImage(id: id, pointSize: CGSize(width: 400, height: 710))
            .scaleEffect(scale)
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.thumbnail))
        .overlay {
          RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
            .strokeBorder(isKeeper ? Theme.keep : .clear, lineWidth: 3)
        }
      Label(caption, systemImage: isKeeper ? "checkmark.circle.fill" : "photo")
        .font(.caption.weight(.semibold))
        .foregroundStyle(isKeeper ? Theme.keep : Color.secondary)
      if let features {
        Text(Format.date(features.createdAt))
          .font(.caption2)
          .foregroundStyle(.secondary)
        Text("\(features.pixelSize.width) × \(features.pixelSize.height)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}
