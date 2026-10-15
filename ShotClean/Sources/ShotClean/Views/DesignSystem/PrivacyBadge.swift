import SwiftUI

/// "Xử lý trên máy · Không tải ảnh lên" (S1, S3, S9).
struct PrivacyBadge: View {
  var body: some View {
    Label(Strings.privacyBadge, systemImage: "lock.shield")
      .font(.footnote.weight(.medium))
      .foregroundStyle(Theme.keep)
      .padding(.horizontal, Theme.Spacing.m)
      .padding(.vertical, 6)
      .background(Theme.keep.opacity(0.12), in: .capsule)
  }
}
