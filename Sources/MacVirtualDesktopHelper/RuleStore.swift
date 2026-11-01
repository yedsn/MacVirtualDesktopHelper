import Foundation

struct HotKeyBinding: Codable {
 var action: String
 var keyCode: UInt32
 var modifiers: UInt32
}

struct WindowRule: Codable, Identifiable {
 enum MatchResult { case matched, notMatched, indeterminate }
 var id = UUID()
 var bundleID: String
 var applicationPath: String
 var title: String
 var titleIsRegex = false
 var targetSpaceUUID: String?
 var targetDisplayUUID: String?
 var targetIndex: Int?

 func matches(bundleID: String, applicationPath: String, title: String) -> Bool {
  matchResult(bundleID: bundleID, applicationPath: applicationPath, title: title) == .matched
 }

 func matchResult(bundleID: String, applicationPath: String, title: String, timeLimit: TimeInterval = 0.05) -> MatchResult {
  guard !self.bundleID.isEmpty || !self.applicationPath.isEmpty else { return .indeterminate }
  guard self.bundleID.isEmpty || self.bundleID == bundleID,
        self.applicationPath.isEmpty || self.applicationPath == applicationPath else { return .notMatched }
  if !titleIsRegex { return self.title == title ? .matched : .notMatched }
  guard timeLimit > 0, let expression = try? NSRegularExpression(pattern: self.title) else { return .indeterminate }
  let deadline = Date().addingTimeInterval(timeLimit)
  var matched = false
  var timedOut = false
  expression.enumerateMatches(in: title, options: [.reportProgress], range: NSRange(title.startIndex..., in: title)) { result, _, stop in
   if Date() >= deadline { timedOut = true; stop.pointee = true; return }
   if result != nil { matched = true; stop.pointee = true }
  }
  return timedOut ? .indeterminate : matched ? .matched : .notMatched
 }
}

struct RuleSnapshot: Codable, Identifiable {
 var id = UUID()
 var name: String
 var createdAt = Date()
 var automatic = false
 var cleanupRules: [WindowRule]
 var desktopRules: [WindowRule]
 var includesCleanupRules = true
 enum CodingKeys: String, CodingKey { case id, name, createdAt, automatic, cleanupRules, desktopRules, includesCleanupRules }
 init(name: String, automatic: Bool, cleanupRules: [WindowRule], desktopRules: [WindowRule]) {
  self.name = name; self.automatic = automatic
  self.cleanupRules = cleanupRules; self.desktopRules = desktopRules
 }
 init(from decoder: Decoder) throws {
  let values = try decoder.container(keyedBy: CodingKeys.self)
  id = try values.decode(UUID.self, forKey: .id)
  name = try values.decode(String.self, forKey: .name)
  createdAt = try values.decode(Date.self, forKey: .createdAt)
  automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
  includesCleanupRules = try values.decodeIfPresent(Bool.self, forKey: .includesCleanupRules) ?? values.contains(.cleanupRules)
  cleanupRules = try values.decodeIfPresent([WindowRule].self, forKey: .cleanupRules) ?? []
  desktopRules = try values.decode([WindowRule].self, forKey: .desktopRules)
 }
}

struct RuleState: Codable {
 var version = 1
 var cleanupRules: [WindowRule] = []
 var desktopRules: [WindowRule] = []
 var snapshots: [RuleSnapshot] = []
 var snapshotSettings: SnapshotSettings?
 var settings: ApplicationSettings?
}

struct ApplicationSettings: Codable {
 var language: String?
 var theme = "auto"
 var desktopDisplayMode = "all-desktops"
 var windowManager = "built-in"
 var hideNavigationAtBounds = false
 var hotKeys: [HotKeyBinding]?
 var overlay: OverlaySettings?
 var restoreWindowFocus: Bool?
 var menuIconSpacing: Double?
 var menuForeground: String?
 var menuSymbolForeground: String?
 var menuBackground: String?
 var menuFontName: String?
 var menuFontSize: Double?
 var showDockIcon: Bool?
 var overviewFontSize: Double?
 var frostedWindow: Bool?
 var showDesktopNameInitial: Bool?
}

struct OverlaySettings: Codable {
 var showSwitch = true
 var showStatus = false
 var duration = 2.0
 var position = "center"
 var allDisplays = true
 var translucent = true
 var animate = true
 var statusPosition: String?
 var statusAllDisplays: Bool?
 var statusTranslucent: Bool?
 var statusAnimate: Bool?
 static let positions = ["topleft", "topcenter", "topright", "middleleft", "middlecenter", "middleright", "bottomleft", "bottomcenter", "bottomright"]
}

struct SnapshotSettings: Codable {
 var enabled = false
 var intervalMinutes = 30
 var maximumCount = 3
}

final class RuleStore {
 private(set) var state: RuleState
 let url: URL
 init(url: URL) throws {
  self.url = url
  if FileManager.default.fileExists(atPath: url.path) {
   state = try JSONDecoder().decode(RuleState.self, from: Data(contentsOf: url))
   try Self.validate(state)
  } else { state = RuleState() }
 }
 static func validate(_ state: RuleState) throws {
  guard state.version == 1 else { throw validationError("不支持的规则文件版本") }
  if let settings = state.settings {
   guard settings.language == nil || ["zh-CN", "en"].contains(settings.language!) else { throw validationError("应用语言无效") }
   if let size = settings.overviewFontSize, !size.isFinite || !(11...20).contains(size) { throw validationError("概览字号须为 11–20 点") }
   if let size = settings.menuFontSize, !size.isFinite || !(8...16).contains(size) { throw validationError("菜单栏字号须为 8–16 点") }
   if let name = settings.menuFontName, name.isEmpty || name.count > 200 { throw validationError("菜单栏字体名称无效") }
   for color in [settings.menuForeground, settings.menuSymbolForeground, settings.menuBackground].compactMap({ $0 }) {
    guard color.count == 7, color.first == "#", UInt32(color.dropFirst(), radix: 16) != nil else { throw validationError("颜色须为 #RRGGBB") }
   }
   if let spacing = settings.menuIconSpacing, !spacing.isFinite || !(0...24).contains(spacing) { throw validationError("菜单栏图标间距须为 0–24 点") }
   if let overlay = settings.overlay {
    guard overlay.duration.isFinite, (0...60).contains(overlay.duration), (OverlaySettings.positions + ["center", "top", "bottom"]).contains(overlay.position), overlay.statusPosition == nil || OverlaySettings.positions.contains(overlay.statusPosition!) else { throw validationError("桌面浮层设置无效") }
   }
   guard ["auto", "light", "dark"].contains(settings.theme),
    ["all-desktops", "navigation"].contains(settings.desktopDisplayMode),
    ["built-in", "system"].contains(settings.windowManager) else { throw validationError("应用设置无效") }
   var combinations = Set<String>()
   for hotkey in settings.hotKeys ?? [] {
    let desktop = hotkey.action.hasPrefix("desktop:") ? Int(hotkey.action.dropFirst(8)) : nil
    guard ["manager", "forward", "backward", "previous"].contains(hotkey.action) || (1...9).contains(desktop ?? 0),
     hotkey.keyCode <= 127, hotkey.modifiers != 0, hotkey.modifiers & ~UInt32(256 | 512 | 2048 | 4096) == 0,
     combinations.insert(String(hotkey.keyCode) + ":" + String(hotkey.modifiers)).inserted else { throw validationError("全局快捷键无效或重复") }
   }
  }
  if let settings = state.snapshotSettings {
   guard (1...10080).contains(settings.intervalMinutes), (1...1000).contains(settings.maximumCount) else { throw validationError("自动快照间隔或保留数无效") }
  }
  for rules in [state.cleanupRules, state.desktopRules] + state.snapshots.flatMap({ [$0.cleanupRules, $0.desktopRules] }) {
   guard Set(rules.map(\.id)).count == rules.count else { throw validationError("规则 ID 重复") }
   for rule in rules {
    guard rule.title.utf16.count <= 4096 else { throw validationError("匹配标题过长") }
    guard !rule.bundleID.isEmpty || !rule.applicationPath.isEmpty else { throw validationError("规则缺少应用身份") }
    if rule.titleIsRegex { _ = try NSRegularExpression(pattern: rule.title) }
    if let index = rule.targetIndex, index < 0 { throw validationError("目标桌面序号无效") }
   }
  }
  guard Set(state.snapshots.map(\.id)).count == state.snapshots.count else { throw validationError("快照 ID 重复") }
 }
 private static func validationError(_ message: String) -> NSError {
  NSError(domain: "MacVirtualDesktopHelper.RuleState", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
 }
 func update(_ change: (inout RuleState) throws -> Void) throws {
  var next = state
  try change(&next)
  try Self.validate(next)
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(next)
  try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try data.write(to: url, options: .atomic)
  state = next
 }
 func capture(name: String, automatic: Bool = false, maximumAutomatic: Int = 3) throws {
  guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, maximumAutomatic > 0 else { throw Self.validationError("快照名称或保留数量无效") }
  try update { state in
   state.snapshots.append(RuleSnapshot(name: name, automatic: automatic, cleanupRules: state.cleanupRules, desktopRules: state.desktopRules))
   if automatic {
    let ordered = state.snapshots.filter(\.automatic).sorted { $0.createdAt < $1.createdAt }
    let remove = Set(ordered.prefix(max(0, ordered.count - maximumAutomatic)).map(\.id))
    state.snapshots.removeAll { remove.contains($0.id) }
   }
  }
 }
 func restore(id: UUID) throws {
  guard let snapshot = state.snapshots.first(where: { $0.id == id }) else { throw Self.validationError("快照已不存在") }
  try update { state in
   if snapshot.includesCleanupRules { state.cleanupRules = snapshot.cleanupRules }
   state.desktopRules = snapshot.desktopRules
  }
 }
}
