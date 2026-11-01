import Foundation

struct RuleWindowIdentity {
 let id: UInt32
 let bundleID: String
 let applicationPath: String
 let title: String
 let spaceUUID: String
 let displayUUID: String
 let desktopIndex: Int
}

struct DesktopRuleChange {
 let windowID: UInt32
 let rule: WindowRule
 let isNew: Bool
 func agrees(with fresh: DesktopRuleChange) -> Bool {
  fresh.windowID == windowID && fresh.isNew == isNew &&
  (isNew || fresh.rule.id == rule.id) &&
  fresh.rule.bundleID == rule.bundleID && fresh.rule.applicationPath == rule.applicationPath &&
  fresh.rule.title == rule.title && fresh.rule.titleIsRegex == rule.titleIsRegex &&
  fresh.rule.targetSpaceUUID == rule.targetSpaceUUID &&
  fresh.rule.targetDisplayUUID == rule.targetDisplayUUID && fresh.rule.targetIndex == rule.targetIndex
 }
}

struct DesktopRuleUpdate {
 let changes: [DesktopRuleChange]
 let ambiguousWindowIDs: Set<UInt32>
}

enum DesktopRuleMatcher {
 struct Target {
  let uuid: String
  let displayUUID: String
  let index: Int
 }
 static func targetIndex(for rule: WindowRule, targets: [Target]) -> Int? {
  let matches: [Int]
  if let uuid = rule.targetSpaceUUID, !uuid.isEmpty {
   matches = targets.indices.filter { targets[$0].uuid == uuid && targets[$0].displayUUID == rule.targetDisplayUUID }
  } else {
   guard let index = rule.targetIndex, index >= 0, let display = rule.targetDisplayUUID, !display.isEmpty else { return nil }
   matches = targets.indices.filter { targets[$0].displayUUID == display && targets[$0].index == index }
  }
  return matches.count == 1 ? matches[0] : nil
 }
 static func matches(_ rule: WindowRule, _ window: RuleWindowIdentity) -> Bool {
  rule.matches(bundleID: window.bundleID, applicationPath: window.applicationPath, title: window.title)
 }

 static func update(rules: [WindowRule], windows: [RuleWindowIdentity], evaluate: (WindowRule, RuleWindowIdentity) -> WindowRule.MatchResult = { rule, window in
  rule.matchResult(bundleID: window.bundleID, applicationPath: window.applicationPath, title: window.title)
 }) -> DesktopRuleUpdate {
  let results = rules.map { rule in windows.map { window in
   evaluate(rule, window)
  } }
  let matchesByRule = results.map { row in row.indices.filter { row[$0] == .matched } }
  let matchesByWindow = windows.indices.map { index in rules.indices.filter { matchesByRule[$0].contains(index) } }
  var changes: [DesktopRuleChange] = []
  var ambiguous = Set<UInt32>()
  for (index, window) in windows.enumerated() {
   guard !window.spaceUUID.isEmpty, !window.displayUUID.isEmpty, window.desktopIndex >= 0,
    !window.bundleID.isEmpty || !window.applicationPath.isEmpty else { ambiguous.insert(window.id); continue }
   guard !results.contains(where: { $0[index] == .indeterminate }) else { ambiguous.insert(window.id); continue }
   let candidates = matchesByWindow[index]
   var rule: WindowRule
   if candidates.isEmpty {
    guard !window.bundleID.isEmpty || !window.applicationPath.isEmpty else { continue }
    // Identical open windows cannot be assigned distinct reliable rules.
    guard windows.filter({ $0.bundleID == window.bundleID && $0.applicationPath == window.applicationPath && $0.title == window.title }).count == 1 else { ambiguous.insert(window.id); continue }
    rule = WindowRule(bundleID: window.bundleID, applicationPath: window.applicationPath, title: window.title)
   } else if candidates.count == 1, matchesByRule[candidates[0]].count == 1, !results[candidates[0]].contains(where: { $0 == .indeterminate }) {
    rule = rules[candidates[0]]
    if rule.targetSpaceUUID == window.spaceUUID && rule.targetDisplayUUID == window.displayUUID && rule.targetIndex == window.desktopIndex { continue }
   } else { ambiguous.insert(window.id); continue }
   rule.targetSpaceUUID = window.spaceUUID
   rule.targetDisplayUUID = window.displayUUID
   rule.targetIndex = window.desktopIndex
   changes.append(DesktopRuleChange(windowID: window.id, rule: rule, isNew: candidates.isEmpty))
  }
  return DesktopRuleUpdate(changes: changes, ambiguousWindowIDs: ambiguous)
 }

 static func uniqueWindow(for rule: WindowRule, rules: [WindowRule], windows: [RuleWindowIdentity]) -> RuleWindowIdentity? {
  guard !windows.contains(where: { rule.matchResult(bundleID: $0.bundleID, applicationPath: $0.applicationPath, title: $0.title) == .indeterminate }) else { return nil }
  let candidates = windows.filter { matches(rule, $0) }
  guard candidates.count == 1, let window = candidates.first,
   !rules.contains(where: { $0.matchResult(bundleID: window.bundleID, applicationPath: window.applicationPath, title: window.title) == .indeterminate }),
   rules.filter({ matches($0, window) }).count == 1 else { return nil }
  return window
 }
}
