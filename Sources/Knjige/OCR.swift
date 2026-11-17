import Foundation
import AppKit
import Vision
import PDFKit

/// Распознавание текста со скриншотов и PDF средствами macOS (Vision), без интернета.
enum OCR {
    enum OCRError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Не удалось открыть файл как картинку или PDF." }
    }

    static func recognize(url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw OCRError.unreadable }
            // Если в PDF есть текстовый слой (выписки банков обычно с ним) — берём его.
            let text = doc.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 { return text }
            // Скан без текста — распознаём страницы как картинки.
            var parts: [String] = []
            for i in 0..<min(doc.pageCount, 10) {
                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let scale: CGFloat = 2000 / max(bounds.width, 1)
                let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    parts.append(try await recognize(cgImage: cg))
                }
            }
            return parts.joined(separator: "\n")
        }
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw OCRError.unreadable }
        return try await recognize(cgImage: cg)
    }

    static func recognize(cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "ru-RU"]
            if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return OCR.joinIntoLines(observations)
        }.value
    }

    /// Собирает кусочки текста в строки по вертикали, чтобы «Amount» и «5 100,00 EUR» из одной строки таблицы
    /// оказались рядом — так проще найти валюту рядом с суммой.
    static func joinIntoLines(_ observations: [VNRecognizedTextObservation]) -> String {
        struct Piece { let text: String; let midY: CGFloat; let minX: CGFloat; let height: CGFloat }
        let pieces = observations.compactMap { obs -> Piece? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let box = obs.boundingBox
            return Piece(text: text, midY: box.midY, minX: box.minX, height: box.height)
        }
        .sorted { $0.midY > $1.midY }

        var rows: [[Piece]] = []
        for piece in pieces {
            if let last = rows.last, let ref = last.first, abs(ref.midY - piece.midY) < max(ref.height, piece.height) * 0.6 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows
            .map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: "   ") }
            .joined(separator: "\n")
    }
}
