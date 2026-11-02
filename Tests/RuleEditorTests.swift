import AppKit

@main struct RuleEditorTests {
 static func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }
 static func main() throws {
  _ = NSApplication.shared
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try RuleStore(url: directory.appendingPathComponent("state.json"))
  let space = DesktopSpace(id: 42, uuid: "target", displayUUID: "display", displayIndex: 0, index: 2, displayCount: 1, isCurrent: true)
  let editor = RuleEditor(store: store, desktopMode: true, spaces: { [space] })
  editor.showWindow(nil)
  let controls = views(editor.window!.contentView!)
  func interact(_ title: String) {
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    let modal = views(NSApp.modalWindow!.contentView!)
    let fields = modal.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    precondition(fields.count == 3)
    fields[0].stringValue = "test.editor"
    fields[1].stringValue = "/Applications/Test.app"
    fields[2].stringValue = title
    modal.compactMap { $0 as? NSButton }.first { $0.title == "标题使用正则表达式" }!.state = .on
    modal.compactMap { $0 as? NSButton }.first { $0.title == "保存" }!.performClick(nil)
   }
  }
  interact("[")
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
   precondition(store.state.desktopRules.isEmpty, "Invalid regex changed rule state")
   let errorButtons = views(NSApp.modalWindow!.contentView!).compactMap { $0 as? NSButton }
   errorButtons.first { $0.isEnabled }!.performClick(nil)
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    let modal = views(NSApp.modalWindow!.contentView!)
    let fields = modal.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    precondition(fields.count == 3 && fields[2].stringValue == "[")
    precondition(fields[0].stringValue == "test.editor" && fields[1].stringValue == "/Applications/Test.app")
    fields[2].stringValue = "^Document.*$"
    modal.compactMap { $0 as? NSButton }.first { $0.title == "保存" }!.performClick(nil)
   }
  }
  controls.compactMap { $0 as? NSButton }.first { $0.title == "新增" }!.performClick(nil)
  precondition(store.state.desktopRules.count == 1)
  let original = store.state.desktopRules[0]
  precondition(original.titleIsRegex && original.targetSpaceUUID == "target" && original.targetIndex == 2)
  let table = controls.compactMap { $0 as? NSTableView }.first!
  table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
  interact("^Changed.*$")
  controls.compactMap { $0 as? NSButton }.first { $0.title == "编辑" }!.performClick(nil)
  let edited = try RuleStore(url: directory.appendingPathComponent("state.json")).state.desktopRules[0]
  precondition(edited.id == original.id && edited.title == "^Changed.*$" && edited.titleIsRegex)
  precondition(edited.targetSpaceUUID == original.targetSpaceUUID && edited.applicationPath == original.applicationPath)
  let savedDirectory = directory.appendingPathExtension("preserved")
  try FileManager.default.moveItem(at: directory, to: savedDirectory)
  defer { try? FileManager.default.removeItem(at: savedDirectory) }
  try Data("block parent directory".utf8).write(to: directory)
  interact("^Retry.*$")
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
   precondition(store.state.desktopRules[0].title == "^Changed.*$", "Failed write changed memory")
   let preserved = try! RuleStore(url: savedDirectory.appendingPathComponent("state.json"))
   precondition(preserved.state.desktopRules[0].title == "^Changed.*$")
   try! FileManager.default.removeItem(at: directory)
   try! FileManager.default.moveItem(at: savedDirectory, to: directory)
   views(NSApp.modalWindow!.contentView!).compactMap { $0 as? NSButton }.first { $0.isEnabled }!.performClick(nil)
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    let modal = views(NSApp.modalWindow!.contentView!)
    let fields = modal.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
    precondition(fields[2].stringValue == "^Retry.*$")
    modal.compactMap { $0 as? NSButton }.first { $0.title == "保存" }!.performClick(nil)
   }
  }
  controls.compactMap { $0 as? NSButton }.first { $0.title == "编辑" }!.performClick(nil)
  let retried = try RuleStore(url: directory.appendingPathComponent("state.json"))
  precondition(retried.state.desktopRules[0].title == "^Retry.*$")
  precondition(retried.state.desktopRules[0].id == original.id)
  let persisted = try Data(contentsOf: directory.appendingPathComponent("state.json"))
  func deleteResponse(_ title: String) {
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    let buttons = views(NSApp.modalWindow!.contentView!).compactMap { $0 as? NSButton }
    buttons.first { $0.title == title }!.performClick(nil)
   }
  }
  deleteResponse("取消")
  controls.compactMap { $0 as? NSButton }.first { $0.title == "删除" }!.performClick(nil)
  precondition(store.state.desktopRules.count == 1)
  let afterCancel = try Data(contentsOf: directory.appendingPathComponent("state.json"))
  precondition(afterCancel == persisted)
  deleteResponse("删除")
  controls.compactMap { $0 as? NSButton }.first { $0.title == "删除" }!.performClick(nil)
  precondition(store.state.desktopRules.isEmpty)
  let afterDelete = try RuleStore(url: directory.appendingPathComponent("state.json"))
  precondition(afterDelete.state.desktopRules.isEmpty)
  precondition(controls.compactMap { $0 as? NSButton }.filter { ["删除", "编辑"].contains($0.title) }.allSatisfy { !$0.isEnabled })
  editor.close()
  var available = [space]
  let topologyEditor = RuleEditor(store: store, desktopMode: true, spaces: { available })
  topologyEditor.showWindow(nil)
  let topologyControls = views(topologyEditor.window!.contentView!)
  let beforeTopology = try Data(contentsOf: store.url)
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
   let modal = views(NSApp.modalWindow!.contentView!)
   let fields = modal.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
   fields[0].stringValue = "test.topology"
   fields[2].stringValue = "Temporary target"
   available = []
   modal.compactMap { $0 as? NSButton }.first { $0.title == "保存" }!.performClick(nil)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
   precondition(store.state.desktopRules.isEmpty)
   let errorViews = views(NSApp.modalWindow!.contentView!)
   precondition(errorViews.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "所选目标桌面已不存在" })
   errorViews.compactMap { $0 as? NSButton }.first { $0.isEnabled }!.performClick(nil)
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    let modal = views(NSApp.modalWindow!.contentView!)
    precondition(modal.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Temporary target" })
    modal.compactMap { $0 as? NSButton }.first { $0.title == "取消" }!.performClick(nil)
   }
  }
  topologyControls.compactMap { $0 as? NSButton }.first { $0.title == "新增" }!.performClick(nil)
  let afterTopology = try Data(contentsOf: store.url)
  precondition(beforeTopology == afterTopology)
  topologyEditor.close()
  let literalTitle = #"报告 [草稿] (v1.2) {副本} + ? * ^ $ | / C:\work\file 👩‍💻"#
  let escapedTitle = #"报告 \[草稿] \(v1\.2\) \{副本\} \+ \? \* \^ \$ \| \/ C:\\work\\file 👩‍💻"#
  for desktopMode in [true, false] {
   let rule = WindowRule(bundleID: "test.toggle", applicationPath: "/Applications/Test.app", title: literalTitle, targetSpaceUUID: space.uuid, targetDisplayUUID: space.displayUUID, targetIndex: space.index)
   try store.update { state in
    if desktopMode { state.desktopRules = [rule] }
    else { state.cleanupRules = [rule] }
   }
   let toggleEditor = RuleEditor(store: store, desktopMode: desktopMode, spaces: { [space] })
   toggleEditor.showWindow(nil)
   let toggleControls = views(toggleEditor.window!.contentView!)
   toggleControls.compactMap { $0 as? NSTableView }.first!.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
   func editToggling(_ verify: @escaping (NSTextField, NSButton) -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
     let modal = views(NSApp.modalWindow!.contentView!)
     let fields = modal.compactMap { $0 as? NSTextField }.filter { $0.isEditable }
     let checkbox = modal.compactMap { $0 as? NSButton }.first { $0.title == "标题使用正则表达式" }!
     verify(fields[2], checkbox)
     modal.compactMap { $0 as? NSButton }.first { $0.title == "保存" }!.performClick(nil)
    }
    toggleControls.compactMap { $0 as? NSButton }.first { $0.title == "编辑" }!.performClick(nil)
   }
   editToggling { title, checkbox in
    precondition(title.stringValue == literalTitle && checkbox.state == .off)
    for _ in 0..<3 {
     checkbox.performClick(nil)
     precondition(title.stringValue == escapedTitle && checkbox.state == .on)
     let pattern = try! NSRegularExpression(pattern: title.stringValue)
     let fullRange = NSRange(literalTitle.startIndex..., in: literalTitle)
     precondition(pattern.firstMatch(in: literalTitle, range: fullRange)?.range == fullRange)
     checkbox.performClick(nil)
     precondition(title.stringValue == literalTitle && checkbox.state == .off)
    }
    checkbox.performClick(nil)
   }
   var saved = try RuleStore(url: store.url).state
   precondition((desktopMode ? saved.desktopRules : saved.cleanupRules)[0].title == escapedTitle)
   editToggling { title, checkbox in
    precondition(title.stringValue == escapedTitle && checkbox.state == .on)
    checkbox.performClick(nil)
    precondition(title.stringValue == literalTitle && checkbox.state == .off)
    // Preserve regex-specific escapes and a trailing slash when removing literal escapes.
    checkbox.performClick(nil)
    title.stringValue = #"^Report\d+\w*\.txt$\"#
    checkbox.performClick(nil)
    precondition(title.stringValue == #"^Report\d+\w*.txt$\"#)
    title.stringValue = literalTitle
   }
   saved = try RuleStore(url: store.url).state
   let restored = (desktopMode ? saved.desktopRules : saved.cleanupRules)[0]
   precondition(restored.id == rule.id && restored.title == literalTitle && !restored.titleIsRegex)
   precondition(restored.bundleID == rule.bundleID && restored.applicationPath == rule.applicationPath)
   precondition(restored.targetSpaceUUID == rule.targetSpaceUUID && restored.targetDisplayUUID == rule.targetDisplayUUID && restored.targetIndex == rule.targetIndex)
   toggleEditor.close()
  }
  print("PASS: both rule editors escape titles on checkbox clicks, restore on repeated toggles and after reload, and persist both modes")
  print("PASS: disappearing target blocks save, retains input and cancellation preserves disk")
  print("PASS: rule editor invalid-regex retry retains input; add/edit preserve fields; cancel/delete persist correctly")
 }
}
