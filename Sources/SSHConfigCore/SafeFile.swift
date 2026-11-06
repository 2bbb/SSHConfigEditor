import Foundation
import Darwin

public struct FileSnapshot: Sendable {
    public let url: URL
    public let target: URL
    public var original: Data?
    public let permissions: Int

    public static func load(_ url: URL) throws -> (FileSnapshot, String) {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: target.path) else {
            return (FileSnapshot(url: url, target: target, original: nil, permissions: 0o600), "")
        }
        let attributes = try fm.attributesOfItem(atPath: target.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ConfigError("通常ファイルではありません: \(url.path)") }
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 2 * 1024 * 1024 else { throw ConfigError("2 MBを超えるファイルは開けません。") }
        let data = try Data(contentsOf: target)
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw ConfigError("UTF-8のテキストではありません: \(url.lastPathComponent)") }
        guard !text.contains("PRIVATE KEY-----") else { throw ConfigError("秘密鍵ファイルは開きません。") }
        return (FileSnapshot(url: url, target: target, original: data,
                             permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600), text)
    }

    public func verifyUnchanged() throws {
        guard url.resolvingSymlinksInPath().standardizedFileURL == target else {
            throw ConfigError("リンク先が変更されています: \(url.path)")
        }
        let current: Data?
        if FileManager.default.fileExists(atPath: target.path) {
            current = try Data(contentsOf: target)
        } else { current = nil }
        guard current == original else {
            throw ConfigError("外部で変更されています: \(url.path)\n原文をコピーして退避するか、再読み込み後に編集し直してください。")
        }
    }

    /// Atomic replacement of one file; backups deliberately live outside any SSH Include glob.
    @discardableResult
    public mutating func save(_ text: String, backupRoot: URL) throws -> URL? {
        try verifyUnchanged()
        let fm = FileManager.default
        let data = Data(text.utf8)
        var backup: URL?
        if let original {
            let directory = backupRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Do not inherit a permissive pre-existing backup root.
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backupRoot.path)
            let destination = directory.appendingPathComponent("config")
            let backupFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard backupFD >= 0 else { throw ConfigError("バックアップを作成できません。") }
            let handle = FileHandle(fileDescriptor: backupFD, closeOnDealloc: true)
            try handle.write(contentsOf: original)
            try handle.synchronize()
            try handle.close()
            let metadata = try JSONSerialization.data(withJSONObject: [
                "source": url.path, "target": target.path,
                "created": ISO8601DateFormatter().string(from: Date()), "permissions": String(permissions, radix: 8)
            ], options: [.prettyPrinted, .sortedKeys])
            try metadata.write(to: directory.appendingPathComponent("source.json"))
            backup = destination
        }
        let parent = target.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        // mkstemp starts at 0600; a newly written secret is never briefly world-readable.
        var template = Array(parent.appendingPathComponent(".ssh-config-edit-XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw ConfigError("一時ファイルを作成できません: \(String(cString: strerror(errno)))") }
        let temporary = String(decoding: template.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        defer { close(fd); unlink(temporary) }
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(fd, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if result < 0 && errno == EINTR { continue }
                guard result > 0 else { throw ConfigError("設定の書き込みに失敗しました。") }
                written += result
            }
        }
        guard fchmod(fd, mode_t(permissions & 0o777)) == 0, fsync(fd) == 0 else {
            throw ConfigError("設定の保存準備に失敗しました。")
        }
        try verifyUnchanged()
        guard rename(temporary, target.path) == 0 else { throw ConfigError("設定を置き換えられません: \(String(cString: strerror(errno)))") }
        original = data
        return backup
    }
}
