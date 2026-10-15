import ShotCleanCore
import SwiftUI
import UIKit

/// Temporary root view so the app compiles and the platform layer can be exercised.
/// R5 replaces it with the real screens (S1–S8).
struct RootPlaceholderView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      List {
        Section("Trạng thái") {
          Text(phaseDescription)
          if model.isLimitedAccess {
            Button("Chọn thêm ảnh") {
              Task { await model.presentLimitedLibraryPicker() }
            }
          }
        }
        actions
        if let result = model.result {
          Section("Nhóm (\(model.screenshotCount) ảnh)") {
            ForEach(ShotCleanCore.Category.allCases, id: \.self) { category in
              LabeledContent(category.rawValue, value: "\(result.ids(in: category).count)")
            }
            LabeledContent("Chọn sẵn để xoá", value: "\(model.selection.count)")
            LabeledContent("Không tải được (iCloud)", value: "\(model.unavailableIDs.count)")
          }
        }
      }
      .navigationTitle("ShotClean")
    }
    .task {
      if model.hasCompletedOnboarding { await model.start() }
    }
  }

  @ViewBuilder private var actions: some View {
    Section {
      switch model.phase {
      case .needsOnboarding:
        Button("Bắt đầu") { Task { await model.start() } }
      case .needsPermission:
        Button("Cho phép truy cập") { Task { await model.requestPermission() } }
      case .denied:
        Button("Mở Cài đặt") {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      case .scanning:
        Button("Huỷ", role: .cancel) { model.cancelScan() }
      case .ready:
        Button("Quét lại toàn bộ") { Task { await model.rescan(full: true) } }
      }
    }
  }

  private var phaseDescription: String {
    switch model.phase {
    case .needsOnboarding: "Chưa giới thiệu"
    case .needsPermission: "Cần quyền truy cập Ảnh"
    case .denied: "Không có quyền truy cập Ảnh"
    case .scanning(let done, let total): "Đang quét \(done) / \(total)"
    case .ready: "Sẵn sàng"
    }
  }
}
