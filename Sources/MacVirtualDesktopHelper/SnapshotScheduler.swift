import Foundation

/// Owned for the entire application lifetime, independent of visible windows.
final class SnapshotScheduler {
 private let store: RuleStore
 private let secondsPerMinute: TimeInterval
 private var timer: Timer?
 var captured: (() -> Void)?
 var failed: ((Error) -> Void)?
 init(store: RuleStore, secondsPerMinute: TimeInterval = 60) { self.store = store; self.secondsPerMinute = secondsPerMinute }
 func reload() {
  timer?.invalidate(); timer = nil
  let settings = store.state.snapshotSettings ?? SnapshotSettings()
  guard settings.enabled else { return }
  let timer = Timer(timeInterval: TimeInterval(settings.intervalMinutes) * secondsPerMinute, repeats: true) { [weak self] _ in
   guard let self else { return }
   do {
    let current = self.store.state.snapshotSettings ?? SnapshotSettings()
    guard current.enabled else { return }
    try self.store.capture(name: "自动快照 " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium), automatic: true, maximumAutomatic: current.maximumCount)
    self.captured?()
   } catch { self.failed?(error) }
  }
  timer.tolerance = 1
  RunLoop.main.add(timer, forMode: .common)
  self.timer = timer
 }
 deinit { timer?.invalidate() }
}
