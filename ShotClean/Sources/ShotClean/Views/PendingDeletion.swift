import Foundation

/// A batch of screenshots the user wants to delete; drives the S8 summary sheet.
struct PendingDeletion: Identifiable {
  let id = UUID()
  let ids: Set<String>
}
