import Foundation

enum ApplicationLog {
 static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MacVirtualDesktopHelper/application.log")
 static func write(_ message: String) {
  do {
   try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
   let line = ISO8601DateFormatter().string(from: Date()) + " " + message + "\n"
   guard let data = line.data(using: .utf8) else { return }
   if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url) }
   else {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd(); try handle.write(contentsOf: data)
   }
  } catch { NSLog("Log write failed: %@", error.localizedDescription) }
 }
}
