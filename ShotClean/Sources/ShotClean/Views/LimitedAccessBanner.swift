import SwiftUI

/// Limited-access banner on the overview: "Chỉ đang quét N ảnh bạn đã chọn" + "Chọn thêm".
struct LimitedAccessBanner: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: Theme.Spacing.m) {
      Image(systemName: "photo.badge.exclamationmark")
        .font(.title3)
        .foregroundStyle(ShotCategory.expiredTicket.tint)
        .accessibilityHidden(true)
      Text(Strings.Permission.limitedBanner(Format.count(model.screenshotCount)))
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(Strings.Permission.addMore) {
        Task { await model.presentLimitedLibraryPicker() }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(Theme.Spacing.m)
    .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.button))
  }
}
