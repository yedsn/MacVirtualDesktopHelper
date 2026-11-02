import Foundation

@main struct SnapshotSchedulerTests {
 static func main() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try RuleStore(url: directory.appendingPathComponent("state.json"))
  let defaults = SnapshotSettings()
  precondition(!defaults.enabled && defaults.intervalMinutes == 30 && defaults.maximumCount == 3)
  try store.capture(name: "manual")
  let manualID = store.state.snapshots[0].id
  var timers: [Timer] = []
  let scheduler = SnapshotScheduler(store: store, schedule: { timers.append($0) })
  scheduler.reload()
  precondition(timers.isEmpty)
  try store.update { $0.snapshotSettings = SnapshotSettings(enabled: true, intervalMinutes: 1, maximumCount: 2) }
  let beforeReload = Date()
  scheduler.reload()
  let firstTimer = timers[0]
  precondition(firstTimer.timeInterval == 60)
  precondition(firstTimer.fireDate >= beforeReload.addingTimeInterval(60))
  precondition(store.state.snapshots.map(\.id) == [manualID])
  let beforeSecondReload = Date()
  scheduler.reload()
  precondition(!firstTimer.isValid && timers.count == 2)
  let activeTimer = timers[1]
  precondition(activeTimer.fireDate >= beforeSecondReload.addingTimeInterval(60))
  precondition(store.state.snapshots.map(\.id) == [manualID])
  for _ in 0..<4 { activeTimer.fire() }
  precondition(store.state.snapshots.filter(\.automatic).count == 2)
  precondition(store.state.snapshots.contains { $0.id == manualID })
  try store.update { $0.snapshotSettings?.enabled = false }
  scheduler.reload()
  precondition(!activeTimer.isValid && timers.count == 2)
  let ids = store.state.snapshots.map(\.id)
  activeTimer.fire()
  precondition(store.state.snapshots.map(\.id) == ids)
  let blockedURL = directory.appendingPathComponent("blocked")
  let retryStore = try RuleStore(url: blockedURL.appendingPathComponent("state.json"))
  try retryStore.update { $0.snapshotSettings = SnapshotSettings(enabled: true, intervalMinutes: 1, maximumCount: 2) }
  try FileManager.default.removeItem(at: blockedURL)
  try Data("blocked".utf8).write(to: blockedURL)
  var retryTimer: Timer?
  let retryScheduler = SnapshotScheduler(store: retryStore, schedule: { retryTimer = $0 })
  var failures = 0
  var captures = 0
  retryScheduler.failed = { _ in failures += 1 }
  retryScheduler.captured = { captures += 1 }
  retryScheduler.reload()
  retryTimer!.fire()
  precondition(failures > 0 && captures == 0 && retryStore.state.snapshots.isEmpty)
  try FileManager.default.removeItem(at: blockedURL)
  retryTimer!.fire()
  precondition(captures > 0 && !retryStore.state.snapshots.isEmpty)
  print("PASS: manual snapshot survives scheduled rotation; persistence failure reports without mutation and next interval retries")
  print("PASS: disabled default, full initial delay, reload resets delay, capture without UI, retention and stop")
 }
}
