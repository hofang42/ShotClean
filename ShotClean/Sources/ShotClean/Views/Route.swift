import ShotCleanCore

/// Destinations pushed on the overview's `NavigationStack`.
enum Route: Hashable {
  /// S5 grid for one category.
  case category(ShotCategory)
  /// S6 cluster review for exact or near duplicates.
  case clusters(Cluster.Kind)
  /// S7 swipe mode.
  case swipe
  /// Full-screen view of one screenshot.
  case detail(String)
  /// S9.
  case settings
  case debug
}
