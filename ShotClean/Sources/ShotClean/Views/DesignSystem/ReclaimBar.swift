import Charts
import SwiftUI

/// One stacked bar showing reclaimable space per category (S4 hero), plus a legend that pairs
/// each color with its symbol and name. Falls back to photo counts when no sizes are known.
struct ReclaimBar: View {
  struct Segment: Identifiable {
    let category: ShotCategory
    let count: Int
    let bytes: Int64
    var id: ShotCategory { category }
  }

  let segments: [Segment]

  private var usesBytes: Bool { segments.contains { $0.bytes > 0 } }

  private var visibleSegments: [Segment] {
    segments.filter { usesBytes ? $0.bytes > 0 : $0.count > 0 }
  }

  private func value(of segment: Segment) -> Double {
    usesBytes ? Double(segment.bytes) : Double(segment.count)
  }

  var body: some View {
    let visible = visibleSegments
    let total = visible.reduce(0) { $0 + value(of: $1) }

    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      Chart(visible) { segment in
        BarMark(
          x: .value("Dung lượng", value(of: segment)),
          y: .value("Nhóm", "all")
        )
        .foregroundStyle(segment.category.tint)
      }
      .chartXAxis(.hidden)
      .chartYAxis(.hidden)
      .chartLegend(.hidden)
      .chartXScale(domain: 0...max(total, 1))
      .chartPlotStyle { plot in
        plot.clipShape(.capsule)
      }
      .frame(height: 12)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Strings.Overview.chartLabel(accessibilitySummary(visible)))

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.s, alignment: .leading)],
        alignment: .leading,
        spacing: Theme.Spacing.xs
      ) {
        ForEach(visible) { segment in
          Label {
            Text(segment.category.shortTitle)
          } icon: {
            Image(systemName: segment.category.symbolName)
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(segment.category.tint)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .accessibilityHidden(true)
    }
  }

  private func accessibilitySummary(_ visible: [Segment]) -> String {
    visible.map { segment in
      let amount =
        usesBytes
        ? Format.bytes(segment.bytes)
        : Strings.Overview.photoCount(Format.count(segment.count))
      return "\(segment.category.title) \(amount)"
    }
    .joined(separator: ", ")
  }
}
