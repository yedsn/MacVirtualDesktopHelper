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
  let scheduler = SnapshotScheduler(store: store, secondsPerMinute: 0.2)
  scheduler.reload()
  RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  precondition(store.state.snapshots.map(\.id) == [manualID])
  try store.update { $0.snapshotSettings = SnapshotSettings(enabled: true, intervalMinutes: 1, maximumCount: 2) }
  scheduler.reload()
  precondition(store.state.snapshots.map(\.id) == [manualID])
  RunLoop.main.run(until: Date().addingTimeInterval(0.12))
  precondition(store.state.snapshots.map(\.id) == [manualID])
  scheduler.reload()
  RunLoop.main.run(until: Date().addingTimeInterval(0.12))
  precondition(store.state.snapshots.map(\.id) == [manualID])
  RunLoop.main.run(until: Date().addingTimeInterval(0.65))
  precondition(store.state.snapshots.filter(\.automatic).count == 2)
  precondition(store.state.snapshots.contains { $0.id == manualID })
  try store.update { $0.snapshotSettings?.enabled = false }
  scheduler.reload()
  let ids = store.state.snapshots.map(\.id)
  RunLoop.main.run(until: Date().addingTimeInterval(0.4))
  precondition(store.state.snapshots.map(\.id) == ids)
  let blockedURL = directory.appendingPathComponent("blocked")
  let retryStore = try RuleStore(url: blockedURL.appendingPathComponent("state.json"))
  try retryStore.update { $0.snapshotSettings = SnapshotSettings(enabled: true, intervalMinutes: 1, maximumCount: 2) }
  try FileManager.default.removeItem(at: blockedURL)
  try Data("blocked".utf8).write(to: blockedURL)
  let retryScheduler = SnapshotScheduler(store: retryStore, secondsPerMinute: 0.1)
  var failures = 0
  var captures = 0
  retryScheduler.failed = { _ in failures += 1 }
  retryScheduler.captured = { captures += 1 }
  retryScheduler.reload()
  RunLoop.main.run(until: Date().addingTimeInterval(0.35))
  precondition(failures > 0 && captures == 0 && retryStore.state.snapshots.isEmpty)
  try FileManager.default.removeItem(at: blockedURL)
  RunLoop.main.run(until: Date().addingTimeInterval(0.35))
  precondition(captures > 0 && !retryStore.state.snapshots.isEmpty)
  print("PASS: manual snapshot survives scheduled rotation; persistence failure reports without mutation and next interval retries")
  print("PASS: disabled default, full initial delay, reload resets delay, capture without UI, retention and stop")
 }
}
