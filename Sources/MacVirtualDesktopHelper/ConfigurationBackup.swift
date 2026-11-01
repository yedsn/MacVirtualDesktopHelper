import Foundation

struct ConfigurationBackup: Codable {
 var format = "MacVirtualDesktopHelper"
 var version = 1
 var exportedAt = Date()
 var state: RuleState
}

enum ConfigurationBackupService {
 static func export(store: RuleStore, to url: URL) throws {
  let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(ConfigurationBackup(state: store.state)).write(to: url, options: .atomic)
 }
 static func preview(from url: URL) throws -> ConfigurationBackup {
  let data = try Data(contentsOf: url)
  let backup: ConfigurationBackup
  do { backup = try JSONDecoder().decode(ConfigurationBackup.self, from: data) }
  catch {
   throw NSError(domain: "MacVirtualDesktopHelper.Backup", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取有效的 Mac 配置备份，文件可能损坏或格式不兼容。Windows 备份的应用身份不能直接映射到 Mac。未修改本地数据。".localized, NSUnderlyingErrorKey: error])
  }
  guard backup.format == "MacVirtualDesktopHelper", backup.version == 1 else {
   throw NSError(domain: "MacVirtualDesktopHelper.Backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "不支持的配置备份格式或版本。".localized])
  }
  try RuleStore.validate(backup.state)
  return backup
 }
 static func restore(_ backup: ConfigurationBackup, store: RuleStore) throws {
  guard backup.format == "MacVirtualDesktopHelper", backup.version == 1 else {
   throw NSError(domain: "MacVirtualDesktopHelper.Backup", code: 2, userInfo: [NSLocalizedDescriptionKey: "不支持的配置备份格式或版本，未修改本地数据。".localized])
  }
  try store.update { $0 = backup.state }
 }
}
