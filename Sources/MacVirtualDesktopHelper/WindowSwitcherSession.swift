import AppKit

/// Pure selection state for the hold-Option window switcher. UI and input
/// adapters feed it immutable candidates, keeping wrap-around deterministic.
final class WindowSwitcherSession {
 enum State { case preparing, selecting, committing, cancelled }
 private(set) var state: State = .preparing
 private(set) var candidates: [DesktopWindow]
 private(set) var selectedIndex: Int?
 private(set) var committed = false

 init(candidates: [DesktopWindow], currentID: UInt32?, mostRecentIDs: [UInt32] = [], reverse: Bool = false) {
  var seen = Set<UInt32>()
  var order = mostRecentIDs.compactMap { id -> DesktopWindow? in
   guard seen.insert(id).inserted else { return nil }
   return candidates.first(where: { $0.id == id })
  }
  order += candidates.filter { item in !order.contains(where: { $0.id == item.id }) }.sorted {
   let owner = $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName)
   if owner != .orderedSame { return owner == .orderedAscending }
   let title = $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle)
   if title != .orderedSame { return title == .orderedAscending }
   return $0.id < $1.id
  }
  self.candidates = order
  if let currentID, let index = order.firstIndex(where: { $0.id == currentID }) {
   selectedIndex = index
  } else {
   // Start from the virtual position before the first item (or after the
   // last item for reverse selection), so an unavailable focus window does
   // not bias the initial direction.
   selectedIndex = nil
  }
  state = .selecting
  advance(reverse: reverse)
 }

 var selected: DesktopWindow? { selectedIndex.flatMap { candidates.indices.contains($0) ? candidates[$0] : nil } }
 func advance(reverse: Bool = false) {
  guard state == .selecting, !candidates.isEmpty else { return }
  let step = reverse ? -1 : 1
  var index = selectedIndex ?? (reverse ? 0 : -1)
  for _ in candidates.indices {
   index = (index + step + candidates.count) % candidates.count
   if !candidates[index].isAccessibilityUnavailable { selectedIndex = index; return }
  }
  selectedIndex = nil
 }
 func cancel() { guard !committed else { return }; state = .cancelled; selectedIndex = nil }
 func commit() -> DesktopWindow? {
  guard state == .selecting, !committed, let selected, !selected.isAccessibilityUnavailable else { return nil }
  committed = true; state = .committing; return selected
 }
}
