import ShotCleanCore
import SwiftUI
import UIKit

/// S9: one-tap presets (Thận trọng / Cân bằng / Mạnh tay, "Tuỳ chỉnh" when the draft matches
/// none), a live "Sẽ chọn sẵn N ảnh · X MB" line, compact category chips, scan scope, an
/// "Nâng cao" group with menu pickers for every threshold, protection, Shortcuts hook, privacy,
/// full rescan, debug. Rule changes are applied to the cached analyses right away (no rescan);
/// toggling camera-photo scanning rescans incrementally.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL
  /// Local draft; pushed to the model when it changes.
  @State private var draft = CleanupSettings.default
  @State private var isLoaded = false
  @State private var didCopyURL = false

  private var isScanning: Bool {
    if case .scanning = model.phase { return true }
    return false
  }

  private var version: String {
    let info = Bundle.main.infoDictionary
    let short = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(short) (\(build))"
  }

  private func categoryBinding(_ category: ShotCleanCore.Category) -> Binding<Bool> {
    Binding(
      get: { draft.enabledCategories.contains(category) },
      set: { isOn in
        if isOn {
          draft.enabledCategories.insert(category)
        } else {
          draft.enabledCategories.remove(category)
        }
      })
  }

  private func keeperTitle(_ rule: CleanupSettings.KeeperRule) -> String {
    switch rule {
    case .automatic: Strings.Settings.keeperAutomatic
    case .oldest: Strings.Settings.keeperOldest
    case .newest: Strings.Settings.keeperNewest
    case .largestFile: Strings.Settings.keeperLargestFile
    }
  }

  private func presetTitle(_ preset: CleanupSettings.Preset?) -> String {
    switch preset {
    case .cautious: Strings.Settings.presetCautious
    case .balanced: Strings.Settings.presetBalanced
    case .aggressive: Strings.Settings.presetAggressive
    case nil: Strings.Settings.presetCustom
    }
  }

  private func presetFooter(_ preset: CleanupSettings.Preset?) -> String {
    switch preset {
    case .cautious: Strings.Settings.presetCautiousFooter
    case .balanced: Strings.Settings.presetBalancedFooter
    case .aggressive: Strings.Settings.presetAggressiveFooter
    case nil: Strings.Settings.presetCustomFooter
    }
  }

  /// Segment shown for the draft: the preset whose rules equal it, else "Tuỳ chỉnh". Picking a
  /// preset rewrites the draft's rules; "Tuỳ chỉnh" itself changes nothing.
  private var presetBinding: Binding<CleanupSettings.Preset?> {
    Binding(
      get: { draft.preset },
      set: { newValue in
        if let newValue { draft = draft.applying(newValue) }
      })
  }

  /// Menu values: the offered values plus the stored one when it is none of them (settings
  /// saved by an older build), so a menu never shows an empty selection.
  private func options(_ values: [Int], current: Int) -> [Int] {
    values.contains(current) ? values : (values + [current]).sorted()
  }

  private static let ageOptions = [7, 14, 30, 60, 90, 180, 365]
  private static let qrAgeOptions = [1, 3, 7, 14, 30, 60, 90]
  private static let ticketGraceOptions = [0, 1, 2, 3, 7]
  private static let orderAgeOptions = [7, 14, 30, 60, 90, 180]
  private static let nearGapOptions = [1, 5, 10, 30, 60, 120]
  private static let burstGapOptions = [3, 5, 8, 15]
  /// Near-duplicate distance thresholds: Chặt / Vừa (default) / Rộng.
  private static let sensitivityValues: [Double] = [0.25, 0.35, 0.45]

  private static func sensitivityTitle(_ value: Double) -> String {
    switch value {
    case 0.25: Strings.Settings.sensitivityLow
    case 0.35: Strings.Settings.sensitivityMedium
    case 0.45: Strings.Settings.sensitivityHigh
    default: Strings.Settings.sensitivityCustom(Format.decimal(value))
    }
  }

  private static let categoryOrder: [ShotCategory] = [
    .exactDuplicate, .nearDuplicate, .burstShot, .oldScreenshot,
    .lowQualityPhoto, .utilityPhoto, .expiredTicket, .expiredOrder, .qrCode,
  ]

  private var preselectPreview: String? {
    guard let result = model.result else { return nil }
    let ids = model.preselectedIDs
    let bytes = result.reclaimableBytes(ids, sizes: model.sizes)
    return bytes > 0
      ? Strings.Settings.preselectPreview(Format.count(ids.count), Format.bytes(bytes))
      : Strings.Settings.preselectPreviewCount(Format.count(ids.count))
  }

  private func intPicker(
    _ title: String, _ value: Binding<Int>, _ values: [Int], label: @escaping (Int) -> String
  ) -> some View {
    Picker(title, selection: value) {
      ForEach(options(values, current: value.wrappedValue), id: \.self) { option in
        Text(label(option)).tag(option)
      }
    }
    .pickerStyle(.menu)
  }

  var body: some View {
    Form {
      presetSection
      categorySection

      Section {
        Toggle(isOn: $draft.scanCameraPhotos) {
          Label(Strings.Settings.scanCameraPhotos, systemImage: "camera")
        }
      } header: {
        Text(Strings.Settings.scope)
      } footer: {
        Text(Strings.Settings.scopeFooter)
      }

      advancedSection

      Section(Strings.Settings.protection) {
        Toggle(isOn: .constant(true)) {
          Label(Strings.Settings.alwaysKeepReceipts, systemImage: "checkmark.shield")
        }
        .disabled(true)
        Toggle(isOn: .constant(true)) {
          Label(Strings.Settings.alwaysKeepProtected, systemImage: "heart")
        }
        .disabled(true)
      }

      Section {
        Text(Strings.Settings.shortcutsText)
          .font(.subheadline)
        LabeledContent(Strings.Settings.shortcuts) {
          Text(Strings.Settings.shortcutURL)
            .font(.callout.monospaced())
            .textSelection(.enabled)
        }
        Button {
          UIPasteboard.general.string = Strings.Settings.shortcutURL
          didCopyURL = true
        } label: {
          Label(
            didCopyURL ? Strings.Settings.copied : Strings.Settings.copyURL,
            systemImage: didCopyURL ? "checkmark" : "doc.on.doc")
        }
      } header: {
        Text(Strings.Settings.shortcuts)
      } footer: {
        Text(Strings.Settings.shortcutsNote)
      }

      Section(Strings.Settings.privacy) {
        PrivacyBadge()
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
        Text(Strings.Settings.privacyText)
          .font(.subheadline)
        Button(Strings.Settings.photoAccess, systemImage: "photo.on.rectangle") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
        if model.isLimitedAccess {
          Button(Strings.Permission.addMore, systemImage: "plus.circle") {
            Task { await model.presentLimitedLibraryPicker() }
          }
        }
      }

      Section(Strings.Settings.other) {
        Button {
          Task { await model.rescan(full: true) }
        } label: {
          Label(
            isScanning ? Strings.Settings.scanning : Strings.Settings.rescanAll,
            systemImage: "arrow.clockwise")
        }
        .disabled(isScanning)

        // REV-22: the Debug screen lists OCR text; keep it out of release builds.
        #if DEBUG
          NavigationLink(value: Route.debug) {
            Label(Strings.Settings.debug, systemImage: "ladybug")
          }
        #endif

        LabeledContent(Strings.Settings.version, value: version)
      }
    }
    .navigationTitle(Strings.Settings.title)
    .onAppear {
      draft = model.settings
      isLoaded = true
    }
    .onDisappear {
      // Leaving within the debounce window cancels the task below; never drop the change.
      guard isLoaded else { return }
      let pending = draft
      Task { await model.updateSettings(pending) }
    }
    .task(id: draft) {
      // Debounce quick changes; the model reclassifies only for real changes.
      try? await Task.sleep(for: .milliseconds(400))
      guard isLoaded, !Task.isCancelled else { return }
      await model.updateSettings(draft)
    }
  }

  private var presetSection: some View {
    Section {
      Picker(Strings.Settings.preset, selection: presetBinding) {
        ForEach(CleanupSettings.Preset.allCases) { preset in
          Text(presetTitle(preset)).tag(Optional(preset))
        }
        if draft.preset == nil {
          Text(Strings.Settings.presetCustom).tag(CleanupSettings.Preset?.none)
        }
      }
      .pickerStyle(.segmented)
      .sensoryFeedback(.selection, trigger: draft.preset)

      if let preselectPreview {
        Label(preselectPreview, systemImage: "checkmark.circle")
          .font(.subheadline.weight(.semibold))
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(.snappy, value: model.preselectedIDs.count)
      }
    } header: {
      Text(Strings.Settings.preset)
    } footer: {
      Text(presetFooter(draft.preset))
    }
  }

  private var categorySection: some View {
    Section {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Spacing.s)],
        spacing: Theme.Spacing.s
      ) {
        ForEach(Self.categoryOrder, id: \.self) { category in
          let isOn = draft.enabledCategories.contains(category)
          Toggle(isOn: categoryBinding(category)) {
            Label(category.shortTitle, systemImage: category.symbolName)
              .font(.subheadline.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
              .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
          }
          .toggleStyle(.button)
          .buttonStyle(.bordered)
          .tint(isOn ? Theme.accent : Color.secondary)
          .accessibilityLabel(category.title)
        }
      }
      .padding(.vertical, Theme.Spacing.xs)
    } header: {
      Text(Strings.Settings.filters)
    } footer: {
      Text(Strings.Settings.filtersFooter)
    }
  }

  private var advancedSection: some View {
    Section {
      DisclosureGroup(Strings.Settings.advanced) {
        intPicker(
          Strings.Settings.oldScreenshotAge, $draft.oldScreenshotMinAgeDays, Self.ageOptions,
          label: Strings.Settings.days)
        intPicker(
          Strings.Settings.qrAge, $draft.qrMinAgeDays, Self.qrAgeOptions,
          label: Strings.Settings.days)
        intPicker(
          Strings.Settings.ticketGrace, $draft.ticketGraceDays, Self.ticketGraceOptions,
          label: Strings.Settings.days)
        intPicker(
          Strings.Settings.orderAge, $draft.orderMaxAgeDays, Self.orderAgeOptions,
          label: Strings.Settings.days)

        Picker(Strings.Settings.duplicateKeeper, selection: $draft.keeperRule) {
          ForEach(CleanupSettings.KeeperRule.allCases, id: \.self) { rule in
            Text(keeperTitle(rule)).tag(rule)
          }
        }
        .pickerStyle(.menu)
        Toggle(Strings.Settings.preselectNear, isOn: $draft.preselectNearDuplicates)
        Picker(Strings.Settings.nearSensitivity, selection: $draft.nearDupMaxDistance) {
          let values =
            Self.sensitivityValues.contains(draft.nearDupMaxDistance)
            ? Self.sensitivityValues
            : (Self.sensitivityValues + [draft.nearDupMaxDistance]).sorted()
          ForEach(values, id: \.self) { value in
            Text(Self.sensitivityTitle(value)).tag(value)
          }
        }
        .pickerStyle(.menu)
        intPicker(
          Strings.Settings.nearGap, $draft.nearDupMaxGapMinutes, Self.nearGapOptions,
          label: Strings.Settings.minutes)
        intPicker(
          Strings.Settings.burstGap, $draft.burstMaxGapSeconds, Self.burstGapOptions,
          label: Strings.Settings.seconds)

        Button(Strings.Settings.resetDefaults, systemImage: "arrow.uturn.backward") {
          draft = .default
        }
        .disabled(draft == .default)
      }
    } footer: {
      Text(Strings.Settings.rulesFooter)
    }
  }
}
