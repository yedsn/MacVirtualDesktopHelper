import AppKit

final class TextDocumentController: NSWindowController {
 private let text = NSTextView()
 init(title: String) {
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
  window.title = title; window.isReleasedWhenClosed = false
  window.minSize = NSSize(width: 480, height: 300)
  super.init(window: window)
  let scroll = NSScrollView(frame: window.contentView!.bounds)
  scroll.autoresizingMask = [.width, .height]
  scroll.hasVerticalScroller = true
  text.isEditable = false; text.isRichText = false
  text.isVerticallyResizable = true; text.isHorizontallyResizable = false
  text.autoresizingMask = [.width]
  text.textContainer?.widthTracksTextView = true
  text.textContainerInset = NSSize(width: 16, height: 16)
  text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
  text.setAccessibilityLabel(title)
  scroll.documentView = text
  window.contentView?.addSubview(scroll)
 }
 required init?(coder: NSCoder) { fatalError() }
 func show(contents: String) {
  text.string = contents
  if window?.isVisible != true { window?.center() }
  showWindow(nil)
  NSApp.activate(ignoringOtherApps: true)
  text.scrollRangeToVisible(NSRange(location: 0, length: 0))
 }
}
