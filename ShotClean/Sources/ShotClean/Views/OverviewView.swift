import ShotCleanCore
import SwiftUI

/// S4, the root screen: hero with reclaimable space, category cards (tap opens, the trailing
/// circle selects / deselects the whole category in place), protected receipts card and a
/// floating bar with one primary CTA ("Dọn ngay N ảnh · X MB" → summary sheet → iOS dialog)
/// plus "Vuốt duyệt". Owns the navigation stack and the single S8 sheet presentation point.
struct OverviewView: View {
  private struct Summary {
    var counts: [ShotCategory: Int] = [:]
    var bytes: [ShotCategory: Int64] = [:]
    var candidateCount = 0
    var candidateBytes: Int64 = 0
    /// All cleanable candidates, including near duplicates that need review.
    var reviewCount = 0
  }

  @Environment(AppModel.self) private var model
  @Environment(AppRouter.self) private var router
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    @Bindable var router = router

    NavigationStack(path: $router.path) {
      content
        .background(Theme.background)
        .navigationTitle(Strings.appName)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: Route.settings) {
              Label(Strings.Overview.settings, systemImage: "gearshape")
            }
          }
        }
        .navigationDestination(for: Route.self) { route in
          destination(for: route)
        }
    }
    .sheet(item: $router.pendingDeletion) { pending in
      DeleteSummarySheet(pending: pending)
    }
  }

  @ViewBuilder private var content: some View {
    if let result = model.result, model.screenshotCount > 0 || !result.verdicts.isEmpty {
      overview(result)
    } else {
      ScrollView {
        VStack(spacing: Theme.Spacing.l) {
          banners
          ContentUnavailableView(
            Strings.Overview.emptyTitle,
            systemImage: "camera.viewfinder",
            description: Text(Strings.Overview.emptyMessage))
        }
        .padding(Theme.Spacing.l)
      }
    }
  }

  private func overview(_ result: AnalysisResult) -> some View {
    let summary = makeSummary(result)
    // Everything currently selected: the settings-aware preselection (keeper rule, enabled
    // filters, protected / undated assets excluded) minus the user's deselections, plus what the
    // user picked with the category toggles or inside a category.
    let quickIDs = model.selection
    let receipts = result.ids(in: .transferReceipt)

    return ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        banners
        hero(summary)

        VStack(spacing: Theme.Spacing.s) {
          ForEach(ShotCategory.cleanable, id: \.self) { category in
            let count = summary.counts[category] ?? 0
            if count > 0 {
              let bulkIDs = model.bulkSelectableIDs(in: category)
              NavigationLink(value: route(for: category)) {
                CategoryCard(
                  category: category,
                  count: count,
                  bytes: summary.bytes[category] ?? 0,
                  badgeText: ShotCategory.reviewOnly.contains(category)
                    ? Strings.Overview.needsReview : nil,
                  reservesAccessory: !bulkIDs.isEmpty
                )
              }
              .buttonStyle(.plain)
              .overlay(
                alignment: dynamicTypeSize.isAccessibilitySize ? .bottomLeading : .trailing
              ) {
                if !bulkIDs.isEmpty {
                  categoryToggle(category, ids: bulkIDs)
                    .padding(Theme.Spacing.l)
                }
              }
            }
          }
        }

        if !receipts.isEmpty {
          Text(Strings.Overview.protectedSection)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          NavigationLink(value: Route.category(.transferReceipt)) {
            CategoryCard(
              category: .transferReceipt,
              count: receipts.count,
              bytes: 0,
              isProtected: true,
              detail: Strings.Overview.protectedDetail(Format.count(receipts.count))
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(Theme.Spacing.l)
    }
    .safeAreaInset(edge: .bottom) {
      if !quickIDs.isEmpty || !model.swipeQueue.isEmpty {
        FloatingActionBar {
          VStack(spacing: Theme.Spacing.s) {
            if !quickIDs.isEmpty {
              let bytes = result.reclaimableBytes(quickIDs, sizes: model.sizes)
              Button {
                router.requestDeletion(of: quickIDs)
              } label: {
                Label(
                  bytes > 0
                    ? Strings.Overview.cleanNow(Format.count(quickIDs.count), Format.bytes(bytes))
                    : Strings.Overview.cleanNowCount(Format.count(quickIDs.count)),
                  systemImage: "sparkles"
                )
                .font(.headline)
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 30)
              }
              .buttonStyle(.borderedProminent)
              .tint(Theme.accent)
              .accessibilityHint(Strings.Overview.cleanNowHint)
            }

            if !model.swipeQueue.isEmpty {
              Button {
                router.path.append(.swipe)
              } label: {
                Label(Strings.Overview.swipeReview, systemImage: "hand.draw")
                  .frame(maxWidth: .infinity)
              }
              .buttonStyle(.bordered)
            }
          }
        }
      }
    }
  }

  /// One-tap select / deselect of a whole category without opening it. Selects only
  /// bulk-selectable ids (never receipts, protected or undated assets, never cluster keepers).
  private func categoryToggle(_ category: ShotCategory, ids: Set<String>) -> some View {
    let selectedCount = model.selection.intersection(ids).count
    let isAll = selectedCount == ids.count
    let symbol =
      isAll ? "checkmark.circle.fill" : (selectedCount > 0 ? "minus.circle.fill" : "circle")
    return Button {
      model.setSelected(!isAll, for: ids)
    } label: {
      Image(systemName: symbol)
        .font(.title2.weight(.semibold))
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(selectedCount > 0 ? Theme.accent : Color.secondary)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: CategoryCard.accessorySize, height: CategoryCard.accessorySize)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .sensoryFeedback(.selection, trigger: isAll)
    .accessibilityLabel(
      isAll
        ? Strings.Overview.deselectCategory(category.title)
        : Strings.Overview.selectCategory(category.title))
    .accessibilityValue("\(Format.count(selectedCount)) / \(Format.count(ids.count))")
  }

  @ViewBuilder private var banners: some View {
    BackgroundScanBanner()
    if model.isLimitedAccess {
      LimitedAccessBanner()
    }
    if !model.unavailableIDs.isEmpty {
      Label(
        Strings.Overview.unavailable(Format.count(model.unavailableIDs.count)),
        systemImage: "icloud.slash"
      )
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
  }

  private func hero(_ summary: Summary) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
      Group {
        if summary.candidateCount > 0 {
          Text(Strings.Overview.reclaimable(Format.bytes(summary.candidateBytes)))
        } else if summary.reviewCount > 0 {
          Text(Strings.Overview.needsReview)
        } else {
          Text(Strings.Overview.nothingToClean)
        }
      }
      .font(.title.bold())
      .fontDesign(.rounded)
      .monospacedDigit()
      .foregroundStyle(.white)
      .contentTransition(.numericText())
      // Keeps long titles clear of the decorative sparkles in the top-trailing corner.
      .padding(.trailing, Theme.Spacing.xl)

      if summary.reviewCount > 0 {
        ReclaimBar(
          segments: ShotCategory.cleanable.map { category in
            ReclaimBar.Segment(
              category: category,
              count: summary.counts[category] ?? 0,
              bytes: summary.bytes[category] ?? 0)
          }
        )
        .padding(Theme.Spacing.m)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card - 6))
      }

      Text(
        Strings.Overview.fromPhotos(
          Format.count(summary.candidateCount), Format.count(model.screenshotCount))
      )
      .font(.footnote)
      .foregroundStyle(.white.opacity(0.85))
    }
    .padding(Theme.Spacing.xl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.brandGradient, in: .rect(cornerRadius: Theme.Radius.hero))
    .overlay(alignment: .topTrailing) {
      Image(systemName: "sparkles")
        .symbolRenderingMode(.hierarchical)
        .font(.title2)
        .foregroundStyle(.white.opacity(0.8))
        .padding(Theme.Spacing.l)
        .accessibilityHidden(true)
    }
    .shadow(color: Theme.brandStart.opacity(0.3), radius: 14, y: 6)
  }

  private func makeSummary(_ result: AnalysisResult) -> Summary {
    var summary = Summary()
    for category in ShotCategory.cleanable {
      let ids = Set(result.ids(in: category))
      let bytes = result.reclaimableBytes(ids, sizes: model.sizes)
      summary.counts[category] = ids.count
      summary.bytes[category] = bytes
      summary.reviewCount += ids.count
      // REV-18: the headline promises only what can be cleaned without review; review-only
      // categories (near duplicates, utility photos) are shown as cards ("Cần bạn xem") only.
      guard !ShotCategory.reviewOnly.contains(category) else { continue }
      // Old screenshots with important-looking text are `.review`, not candidates.
      let candidates = ids.filter { result.verdicts[$0]?.suggestion == .delete }
      summary.candidateCount += candidates.count
      summary.candidateBytes +=
        candidates.count == ids.count
        ? bytes : result.reclaimableBytes(candidates, sizes: model.sizes)
    }
    return summary
  }

  private func route(for category: ShotCategory) -> Route {
    switch category {
    case .exactDuplicate: .clusters(.exact)
    case .nearDuplicate: .clusters(.near)
    case .burstShot: .clusters(.burst)
    default: .category(category)
    }
  }

  @ViewBuilder private func destination(for route: Route) -> some View {
    switch route {
    case .category(let category): CategoryGridView(category: category)
    case .clusters(let kind): ClusterReviewView(kind: kind)
    case .swipe: SwipeReviewView()
    case .detail(let id): ScreenshotDetailView(id: id)
    case .settings: SettingsView()
    case .debug: DebugView()
    }
  }
}
