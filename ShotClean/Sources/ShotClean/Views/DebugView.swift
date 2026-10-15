import ShotCleanCore
import SwiftUI

/// POC debug screen: counts, OCR languages and every analyzed screenshot with its category,
/// suggestion, reason and OCR text. Data stays on device; nothing is exported.
struct DebugView: View {
  private struct Row: Identifiable {
    let id: String
    let verdict: Verdict
    let text: String
  }

  @Environment(AppModel.self) private var model
  @State private var languages: [String]?
  @State private var query = ""

  private var filteredRows: [ShotCategory: [Row]] {
    guard let result = model.result else { return [:] }
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    var rows: [ShotCategory: [Row]] = [:]
    for category in ShotCategory.allCases {
      rows[category] = result.ids(in: category).compactMap { id in
        guard let verdict = result.verdicts[id] else { return nil }
        let text = model.features(for: id)?.text ?? ""
        if !needle.isEmpty {
          let haystack = "\(id)\n\(verdict.reason)\n\(text)".lowercased()
          guard haystack.contains(needle) else { return nil }
        }
        return Row(id: id, verdict: verdict, text: text)
      }
    }
    return rows
  }

  var body: some View {
    let rows = filteredRows

    List {
      countsSection

      ForEach(ShotCategory.allCases, id: \.self) { category in
        let items = rows[category] ?? []
        if !items.isEmpty {
          Section("\(category.title) (\(Format.count(items.count)))") {
            ForEach(items) { row in
              DisclosureGroup {
                Text(row.text.isEmpty ? Strings.Detail.noText : row.text)
                  .font(.caption.monospaced())
                  .textSelection(.enabled)
              } label: {
                rowLabel(row)
              }
            }
          }
        }
      }
    }
    .navigationTitle(Strings.Debug.title)
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $query, prompt: Strings.Debug.search)
    .task {
      guard languages == nil else { return }
      // Static, computed once by the analyzer; read off the main actor because it may
      // create a Vision request the first time.
      languages = await Task.detached(priority: .utility) {
        ScreenshotAnalyzer.recognitionLanguages
      }.value
    }
  }

  private var countsSection: some View {
    let result = model.result
    return Section(Strings.Debug.counts) {
      LabeledContent(Strings.Debug.screenshots, value: Format.count(model.screenshotCount))
      LabeledContent(Strings.Debug.analyzed, value: Format.count(result?.verdicts.count ?? 0))
      LabeledContent(Strings.Debug.unavailable, value: Format.count(model.unavailableIDs.count))
      LabeledContent(Strings.Debug.clusters, value: Format.count(result?.clusters.count ?? 0))
      LabeledContent(
        Strings.Debug.preselected,
        value: Format.count(result?.preselectedForDeletion().count ?? 0))
      LabeledContent(Strings.Debug.selected, value: Format.count(model.selection.count))
      LabeledContent(Strings.Debug.swipeQueue, value: Format.count(model.swipeQueue.count))
      LabeledContent(
        Strings.Debug.ocrLanguages,
        value: languages.map { $0.joined(separator: ", ") } ?? Strings.Debug.loading)
    }
  }

  private func rowLabel(_ row: Row) -> some View {
    HStack(alignment: .top, spacing: Theme.Spacing.m) {
      ThumbnailImage(id: row.id, pointSize: CGSize(width: 44, height: 78))
        .frame(width: 44, height: 78)
        .clipShape(.rect(cornerRadius: 6))
      VStack(alignment: .leading, spacing: 2) {
        Text("\(Strings.Debug.suggestion): \(row.verdict.suggestion.title)")
          .font(.subheadline.weight(.semibold))
        if !row.verdict.reason.isEmpty {
          Text(row.verdict.reason)
            .font(.footnote)
        }
        if let date = model.captureDate(for: row.id) {
          Text(Format.date(date))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(row.id)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }
}
