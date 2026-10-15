/// Pure bookkeeping for the delete selection (REV-1, REV-6, REV-9). No PhotoKit, no UI.
///
/// Rules:
/// - `reset` (first result, full rescan): selection = preselection, user choices forgotten.
/// - `merge` (incremental scan, deletion): ids that no longer exist are dropped; ids the user
///   touched keep the user's choice; untouched ids keep their state, except that preselection is
///   added only for ids that are new since the last merge, and untouched ids that are no longer
///   preselected are dropped (the safe direction).
struct SelectionState: Equatable, Sendable {
  /// Ids currently selected for deletion.
  private(set) var selected: Set<String> = []
  /// Ids whose selection the user changed explicitly. Rescans never override these.
  private(set) var touched: Set<String> = []
  /// Original (Core) cluster keeper id → keeper chosen by the user.
  private(set) var keeperOverrides: [String: String] = [:]
  /// Ids present in the last analysis.
  private(set) var knownIDs: Set<String> = []

  /// First result or full rescan: start over from `preselected`.
  mutating func reset(knownIDs: Set<String>, preselected: Set<String>) {
    self.knownIDs = knownIDs
    selected = preselected.intersection(knownIDs)
    touched = []
    keeperOverrides = [:]
  }

  /// Incremental update: keeps the user's choices for ids that still exist.
  mutating func merge(knownIDs: Set<String>, preselected: Set<String>) {
    let newIDs = knownIDs.subtracting(self.knownIDs)
    let touchedStill = touched.intersection(knownIDs)
    let userChoices = selected.intersection(touchedStill)
    let untouchedPre = preselected.intersection(knownIDs).subtracting(touchedStill)
    let automatic = untouchedPre.intersection(newIDs.union(selected))
    selected = userChoices.union(automatic)
    touched = touchedStill
    keeperOverrides = keeperOverrides.filter {
      knownIDs.contains($0.key) && knownIDs.contains($0.value)
    }
    self.knownIDs = knownIDs
  }

  /// Ids that were deleted (or otherwise vanished) outside a scan.
  mutating func remove(_ ids: Set<String>) {
    selected.subtract(ids)
    touched.subtract(ids)
    knownIDs.subtract(ids)
    keeperOverrides = keeperOverrides.filter { !ids.contains($0.key) && !ids.contains($0.value) }
  }

  /// Explicit user choice for one id.
  mutating func setSelected(_ isSelected: Bool, for id: String) {
    touched.insert(id)
    if isSelected { selected.insert(id) } else { selected.remove(id) }
  }

  /// Explicit user choice for several ids (select all / none).
  mutating func setSelected(_ isSelected: Bool, for ids: some Sequence<String>) {
    for id in ids { setSelected(isSelected, for: id) }
  }

  mutating func toggle(_ id: String) {
    setSelected(!selected.contains(id), for: id)
  }

  /// The keeper shown for a cluster whose Core keeper is `coreKeeperID`.
  func keeper(forCoreKeeper coreKeeperID: String, members: [String]) -> String {
    guard let chosen = keeperOverrides[coreKeeperID], members.contains(chosen) else {
      return coreKeeperID
    }
    return chosen
  }

  /// User picks `newKeeper` in a cluster. The new keeper is deselected; when
  /// `selectPreviousKeeper` is true (exact duplicates, not a receipt) the old keeper is selected.
  mutating func setKeeper(
    _ newKeeper: String, coreKeeperID: String, members: [String], selectPreviousKeeper: Bool
  ) {
    let oldKeeper = keeper(forCoreKeeper: coreKeeperID, members: members)
    guard newKeeper != oldKeeper else { return }
    keeperOverrides[coreKeeperID] = newKeeper
    setSelected(false, for: newKeeper)
    if selectPreviousKeeper { setSelected(true, for: oldKeeper) }
  }
}
