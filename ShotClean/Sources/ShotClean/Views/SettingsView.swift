import ShotCleanCore
import SwiftUI
import UIKit

/// S9 (minimal POC): read-only thresholds, receipt protection, privacy, full rescan, debug.
struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openURL) private var openURL

  private let thresholds = Thresholds.default

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

  var body: some View {
    Form {
      Section {
        LabeledContent(
          Strings.Settings.qrAge, value: Strings.Settings.days(thresholds.qrMinAgeDays))
        LabeledContent(
          Strings.Settings.ticketGrace, value: Strings.Settings.days(thresholds.ticketGraceDays))
        LabeledContent(
          Strings.Settings.orderAge, value: Strings.Settings.days(thresholds.orderMaxAgeDays))
        LabeledContent(
          Strings.Settings.nearSensitivity,
          value: Strings.Settings.distance(
            Format.decimal(Double(thresholds.nearDupMaxDistance))))
        LabeledContent(
          Strings.Settings.nearGap,
          value: Strings.Settings.minutes(Int(thresholds.nearDupMaxGap / 60)))
        LabeledContent(Strings.Settings.duplicateKeeper, value: Strings.Settings.keeperOldest)
      } header: {
        Text(Strings.Settings.rules)
      } footer: {
        Text(Strings.Settings.rulesFooter)
      }

      Section(Strings.Settings.protection) {
        Toggle(isOn: .constant(true)) {
          Label(Strings.Settings.alwaysKeepReceipts, systemImage: "checkmark.shield")
        }
        .disabled(true)
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

        NavigationLink(value: Route.debug) {
          Label(Strings.Settings.debug, systemImage: "ladybug")
        }

        LabeledContent(Strings.Settings.version, value: version)
      }
    }
    .navigationTitle(Strings.Settings.title)
  }
}
