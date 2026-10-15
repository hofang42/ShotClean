import ShotCleanCore
import SwiftUI

/// Large view of one screenshot with its full reason, metadata and (POC only) the OCR text.
struct ScreenshotDetailView: View {
  let id: String

  @Environment(AppModel.self) private var model

  var body: some View {
    let verdict = model.result?.verdicts[id]
    let features = model.features(for: id)
    let isSelected = model.selection.contains(id)

    List {
      Section {
        Color.clear
          .aspectRatio(Theme.thumbnailAspectRatio, contentMode: .fit)
          .overlay {
            ThumbnailImage(id: id, pointSize: CGSize(width: 400, height: 710))
          }
          .clipShape(.rect(cornerRadius: Theme.Radius.thumbnail))
          .frame(maxWidth: 400)
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
      }

      Section {
        if let verdict {
          LabeledContent {
            Text(verdict.category.title)
          } label: {
            Label {
              Text(Strings.Detail.reason)
            } icon: {
              Image(systemName: verdict.category.symbolName)
                .foregroundStyle(verdict.category.tint)
            }
          }
          if !verdict.reason.isEmpty {
            Text(verdict.reason)
          }
        }
        if let features {
          let date = model.captureDate(for: id)
          LabeledContent(
            Strings.Detail.captured, value: date.map(Format.date) ?? Strings.Detail.unknown
          )
          .accessibilityValue(date.map(Format.spokenDate) ?? Strings.Detail.unknown)
          LabeledContent(
            Strings.Detail.size,
            value: features.fileSize.map(Format.bytes) ?? Strings.Detail.unknown)
          LabeledContent(
            Strings.Detail.pixels,
            value: "\(features.pixelSize.width) × \(features.pixelSize.height)")
        }
      }

      // REV-22: OCR text (may include bank receipts) is shown only in debug builds.
      #if DEBUG
        if let features {
          Section(Strings.Detail.ocrText) {
            Text(features.text.isEmpty ? Strings.Detail.noText : features.text)
              .font(.footnote.monospaced())
              .foregroundStyle(features.text.isEmpty ? .secondary : .primary)
              .textSelection(.enabled)
          }
        }
      #endif
    }
    .navigationTitle(Strings.Detail.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(
          isSelected ? Strings.Detail.deselect : Strings.Detail.select,
          systemImage: isSelected ? "checkmark.circle.fill" : "circle"
        ) {
          model.toggleSelection(id)
        }
      }
    }
  }
}
