import AppKit

@main struct WindowReviewTests {
 static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
 static func interact(_ body: @escaping (NSWindow, NSTableView, [NSButton]) -> Void) {
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
   guard let window = NSApp.modalWindow, let root = window.contentView else { preconditionFailure("Missing review modal") }
   let views = descendants(root)
   guard let table = views.compactMap({ $0 as? NSTableView }).first else { preconditionFailure("Missing review table") }
   body(window, table, views.compactMap { $0 as? NSButton })
  }
 }
 static func main() {
  _ = NSApplication.shared
  let windows = (1...3).map { DesktopWindow(id: UInt32($0), ownerName: "Temporary", title: "Window " + String($0), bundleID: "test.review", pid: 1, spaceID: 1, displayUUID: "display", isOnScreen: true, isSticky: false, icon: nil) }
  let review = WindowReview()
  interact { _, table, buttons in
   precondition(table.numberOfRows == 3 && table.tableColumns.count == 3)
   table.selectRowIndexes(IndexSet([0,2]), byExtendingSelection: false)
   buttons.first { $0.title == "从列表移除" }!.performClick(nil)
   precondition(table.numberOfRows == 1)
   buttons.first { $0.title == "执行" }!.performClick(nil)
  }
  let accepted = review.confirm(title: "临时预览测试", windows: windows, action: "执行", details: [1:"A",2:"B",3:"C"])
  precondition(accepted?.map { $0.id } == [2])
  interact { _, table, buttons in
   precondition(table.numberOfRows == 3 && table.tableColumns.count == 2)
   precondition(table.selectedRowIndexes.isEmpty)
   table.window!.makeFirstResponder(table)
   let selectAll = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: table.window!.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
   precondition(table.performKeyEquivalent(with: selectAll))
   precondition(table.selectedRowIndexes.count == 3)
   let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: table.window!.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
   table.keyDown(with: delete)
   precondition(table.numberOfRows == 0)
   precondition(buttons.first { $0.title == "执行" }!.isEnabled == false)
   buttons.first { $0.title == "取消" }!.performClick(nil)
  }
  precondition(review.confirm(title: "临时预览测试", windows: windows, action: "执行") == nil)
  print("PASS: modal preview exclusion, accepted IDs, Delete, empty confirmation disabled and reusable columns/selection")
 }
}
