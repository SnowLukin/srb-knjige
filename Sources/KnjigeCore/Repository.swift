import Foundation

/// Хранит данные в ~/Library/Application Support/Knjige: data.json + папка files с вложениями.
/// Перед каждой записью делается резервная копия предыдущей версии.
public final class Repository: @unchecked Sendable {
    public let baseURL: URL
    public var dataURL: URL { baseURL.appendingPathComponent("data.json") }
    public var filesURL: URL { baseURL.appendingPathComponent("files", isDirectory: true) }
    public var backupsURL: URL { baseURL.appendingPathComponent("backups", isDirectory: true) }

    public init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.baseURL = support.appendingPathComponent("Knjige", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.baseURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: dataURL.path) else { return AppData() }
        let raw = try Data(contentsOf: dataURL)
        do {
            return try Self.decoder.decode(AppData.self, from: raw)
        } catch {
            // Сохраняем нечитаемый файл отдельно, чтобы следующая запись его не затёрла.
            let stamp = Int(Date().timeIntervalSince1970)
            try? raw.write(to: backupsURL.appendingPathComponent("unreadable-\(stamp).json"))
            throw error
        }
    }

    public func save(_ data: AppData) throws {
        let encoded = try Self.encoder.encode(data)
        if FileManager.default.fileExists(atPath: dataURL.path) {
            backupCurrent()
        }
        try encoded.write(to: dataURL, options: .atomic)
    }

    /// Одна резервная копия в день, хранится 30 последних.
    private func backupCurrent() {
        let name = "data-\(Dates.iso(Date())).json"
        let target = backupsURL.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.copyItem(at: dataURL, to: target)
        }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: backupsURL.path).filter({ $0.hasPrefix("data-") }).sorted(),
           files.count > 30 {
            for old in files.prefix(files.count - 30) {
                try? fm.removeItem(at: backupsURL.appendingPathComponent(old))
            }
        }
    }

    /// Копирует файл внутрь хранилища приложения.
    public func importFile(from source: URL) throws -> Attachment {
        let ext = source.pathExtension.isEmpty ? "" : ".\(source.pathExtension.lowercased())"
        let id = UUID()
        let stored = "\(id.uuidString)\(ext)"
        let target = filesURL.appendingPathComponent(stored)
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: target)
        var attachment = Attachment(storedFileName: stored, originalName: source.lastPathComponent)
        attachment.id = id
        return attachment
    }

    public func url(for attachment: Attachment) -> URL {
        filesURL.appendingPathComponent(attachment.storedFileName)
    }

    public func deleteFile(_ attachment: Attachment) {
        try? FileManager.default.removeItem(at: url(for: attachment))
    }

    /// Экспорт всех данных одним файлом (для переноса на другой Мак).
    public func exportBackup(_ data: AppData, to url: URL) throws {
        try Self.encoder.encode(data).write(to: url, options: .atomic)
    }

    public func importBackup(from url: URL) throws -> AppData {
        try Self.decoder.decode(AppData.self, from: Data(contentsOf: url))
    }
}
