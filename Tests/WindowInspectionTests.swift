import AppKit
import ApplicationServices

@main struct WindowInspectionTests {
 static func main() {
  typealias Inspection = AccessibilityWindowService.WindowInspection
  typealias Details = AccessibilityWindowService.WindowDetails
  let original = DesktopWindow(id: 42, ownerName: "Fixture", title: "Fixture", bundleID: "test.fixture", pid: 1, spaceID: 20, displayUUID: "display", isOnScreen: false, isSticky: false, icon: nil)
  for error in [AXError.apiDisabled, .cannotComplete, .failure] {
   let query = Inspection(windows: [:], error: error, hasUnresolvedIDs: false)
   var item = original
   query.apply(to: &item)
   precondition(query.presence(of: 42) == nil)
   precondition(item.isAccessibilityUnavailable && !item.isMinimizedStateKnown)
   precondition(!item.belongsToBackgroundSection && !item.isEligibleForBulkOperations)
   precondition(item.backgroundStateDescription.isEmpty)
  }
  let missing = Inspection(windows: [:], error: nil, hasUnresolvedIDs: false)
  precondition(missing.presence(of: 42) == false)
  precondition(missing.excludesBackgroundRecord(42, isAccessoryApplication: true, isOnCurrentSpace: true, isOnScreen: false, isApplicationHidden: false))
  precondition(!missing.excludesBackgroundRecord(42, isAccessoryApplication: false, isOnCurrentSpace: true, isOnScreen: false, isApplicationHidden: false))
  precondition(!missing.excludesBackgroundRecord(42, isAccessoryApplication: true, isOnCurrentSpace: false, isOnScreen: false, isApplicationHidden: false))
  precondition(!missing.excludesBackgroundRecord(42, isAccessoryApplication: true, isOnCurrentSpace: true, isOnScreen: true, isApplicationHidden: false))
  precondition(!missing.excludesBackgroundRecord(42, isAccessoryApplication: true, isOnCurrentSpace: true, isOnScreen: false, isApplicationHidden: true))
  for query in [Inspection(windows: [:], error: .cannotComplete, hasUnresolvedIDs: false), Inspection(windows: [:], error: .apiDisabled, hasUnresolvedIDs: false), Inspection(windows: [:], error: nil, hasUnresolvedIDs: true)] {
   precondition(!query.excludesBackgroundRecord(42, isAccessoryApplication: true, isOnCurrentSpace: true, isOnScreen: false, isApplicationHidden: false))
  }
  precondition(Inspection(windows: [:], error: nil, hasUnresolvedIDs: true).presence(of: 42) == nil)
  var item = original
  let partial = Inspection(windows: [42: Details(title: "Fixture", isMinimized: nil, isStandard: true)], error: nil, hasUnresolvedIDs: false)
  partial.apply(to: &item)
  precondition(partial.presence(of: 42) == true && !item.isAccessibilityUnavailable)
  precondition(!item.isMinimizedStateKnown && !item.belongsToBackgroundSection && !item.isEligibleForBulkOperations)
  let minimized = Inspection(windows: [42: Details(title: "Fixture", isMinimized: true, isStandard: true)], error: nil, hasUnresolvedIDs: false)
  minimized.apply(to: &item)
  precondition(item.isMinimizedStateKnown && item.belongsToBackgroundSection)
  missing.apply(to: &item)
  precondition(!item.isMinimizedStateKnown && !item.belongsToBackgroundSection)
  let restored = Inspection(windows: [42: Details(title: "Fixture", isMinimized: false, isStandard: true)], error: nil, hasUnresolvedIDs: false)
  restored.apply(to: &item)
  precondition(!restored.excludesBackgroundRecord(42, isAccessoryApplication: true, isOnCurrentSpace: true, isOnScreen: false, isApplicationHidden: false))
  precondition(item.isMinimizedStateKnown && !item.isMinimized && item.isEligibleForBulkOperations)
  precondition(item.backgroundStateDescription.isEmpty)
  print("PASS: permission denial, timeout, missing objects, unresolved IDs, partial attributes and recovery retain distinct inspection evidence")
 }
}
