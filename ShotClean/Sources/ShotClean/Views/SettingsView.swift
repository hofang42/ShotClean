import ShotCleanCore
import SwiftUI
import UIKit

/// S9: editable cleanup rules and filters, scan scope, protection, Shortcuts hook, privacy, full
/// rescan, debug. Rule changes are applied to the cached analyses right away (no rescan);
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

  var body: some View {
    Form {
      Section {
        ForEach(
          [
            ShotCategory.exactDuplicate, .nearDuplicate, .burstShot, .oldScreenshot,
            .lowQualityPhoto, .utilityPhoto, .expiredTicket, .expiredOrder, .qrCode,
          ],
          id: \.self
        ) { category in
          Toggle(isOn: categoryBinding(category)) {
            Label(category.title, systemImage: category.symbolName)
          }
        }
      } header: {
        Text(Strings.Settings.filters)
      } footer: {
        Text(Strings.Settings.filtersFooter)
      }

      Section {
        Toggle(isOn: $draft.scanCameraPhotos) {
          Label(Strings.Settings.scanCameraPhotos, systemImage: "camera")
        }
      } header: {
        Text(Strings.Settings.scope)
      } footer: {
        Text(Strings.Settings.scopeFooter)
      }

      Section {
        Stepper(
          value: $draft.oldScreenshotMinAgeDays, in: CleanupSettings.oldScreenshotAgeRange,
          step: 7
        ) {
          LabeledContent(
            Strings.Settings.oldScreenshotAge,
            value: Strings.Settings.days(draft.oldScreenshotMinAgeDays))
        }
        Stepper(value: $draft.qrMinAgeDays, in: 0...365) {
          LabeledContent(Strings.Settings.qrAge, value: Strings.Settings.days(draft.qrMinAgeDays))
        }
        Stepper(value: $draft.ticketGraceDays, in: 0...30) {
          LabeledContent(
            Strings.Settings.ticketGrace, value: Strings.Settings.days(draft.ticketGraceDays))
        }
        Stepper(value: $draft.orderMaxAgeDays, in: 1...365, step: 5) {
          LabeledContent(
            Strings.Settings.orderAge, value: Strings.Settings.days(draft.orderMaxAgeDays))
        }
      } header: {
        Text(Strings.Settings.rules)
      } footer: {
        Text(Strings.Settings.rulesFooter)
      }

      Section(Strings.Settings.duplicates) {
        Picker(Strings.Settings.duplicateKeeper, selection: $draft.keeperRule) {
          ForEach(CleanupSettings.KeeperRule.allCases, id: \.self) { rule in
            Text(keeperTitle(rule)).tag(rule)
          }
        }
        Toggle(Strings.Settings.preselectNear, isOn: $draft.preselectNearDuplicates)
        VStack(alignment: .leading) {
          LabeledContent(
            Strings.Settings.nearSensitivity,
            value: Format.decimal(draft.nearDupMaxDistance))
          Slider(value: $draft.nearDupMaxDistance, in: 0.15...0.6, step: 0.05) {
            Text(Strings.Settings.nearSensitivity)
          } minimumValueLabel: {
            Text(Strings.Settings.sensitivityLow).font(.caption)
          } maximumValueLabel: {
            Text(Strings.Settings.sensitivityHigh).font(.caption)
          }
        }
        Stepper(value: $draft.nearDupMaxGapMinutes, in: 1...120) {
          LabeledContent(
            Strings.Settings.nearGap, value: Strings.Settings.minutes(draft.nearDupMaxGapMinutes))
        }
        Stepper(value: $draft.burstMaxGapSeconds, in: CleanupSettings.burstGapRange) {
          LabeledContent(
            Strings.Settings.burstGap, value: Strings.Settings.seconds(draft.burstMaxGapSeconds))
        }
        Button(Strings.Settings.resetDefaults, systemImage: "arrow.uturn.backward") {
          draft = .default
        }
        .disabled(draft == .default)
      }

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
      // Debounce slider drags; the model reclassifies only for real changes.
      try? await Task.sleep(for: .milliseconds(400))
      guard isLoaded, !Task.isCancelled else { return }
      await model.updateSettings(draft)
    }
  }
}
