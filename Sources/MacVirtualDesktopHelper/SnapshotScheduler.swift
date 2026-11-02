import Foundation

/// Owned for the entire application lifetime, independent of visible windows.
final class SnapshotScheduler {
 private let store: RuleStore
 private let secondsPerMinute: TimeInterval
 private let schedule: (Timer) -> Void
 private var timer: Timer?
 var captured: (() -> Void)?
 var failed: ((Error) -> Void)?
 init(store: RuleStore, secondsPerMinute: TimeInterval = 60, schedule: @escaping (Timer) -> Void = { RunLoop.main.add($0, forMode: .common) }) {
  self.store = store; self.secondsPerMinute = secondsPerMinute; self.schedule = schedule
 }
 func reload() {
  timer?.invalidate(); timer = nil
  let settings = store.state.snapshotSettings ?? SnapshotSettings()
  guard settings.enabled else { return }
  let interval = TimeInterval(settings.intervalMinutes) * secondsPerMinute
  let timer = Timer(fire: Date().addingTimeInterval(interval), interval: interval, repeats: true) { [weak self] _ in
   guard let self else { return }
   do {
    let current = self.store.state.snapshotSettings ?? SnapshotSettings()
    guard current.enabled else { return }
    try self.store.capture(name: "自动快照 " + DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium), automatic: true, maximumAutomatic: current.maximumCount)
    self.captured?()
   } catch { self.failed?(error) }
  }
  timer.tolerance = 1
  schedule(timer)
  self.timer = timer
 }
 deinit { timer?.invalidate() }
}
