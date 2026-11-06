import Foundation

public struct HostMoveResult: Sendable {
    public let source: String
    public let destination: String
    public let insertedBlockID: Int

    public init(source: String, blockID: Int, destination: String, beforeBlockID: Int? = nil) throws {
        let sourceDoc = ConfigDocument(source), destinationDoc = ConfigDocument(destination)
        guard let block = sourceDoc.blocks.first(where: { $0.id == blockID }), block.kind == "host" else {
            throw ConfigError("Only Host blocks can be moved.")
        }
        var sourceRows = sourceDoc.lines
        var start = block.start, end = block.end
        func isComment(_ row: String) -> Bool { row.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        // Contiguous leading comments travel with their Host. Comments introducing
        // the following Host/Match remain with that next block.
        while start > 0 && isComment(sourceRows[start - 1]) { start -= 1 }
        if end < sourceRows.count {
            while end > block.start + 1 && isComment(sourceRows[end - 1]) { end -= 1 }
        }
        var chunk = Array(sourceRows[start..<end])
        while chunk.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { chunk.removeLast() }
        sourceRows.removeSubrange(start..<end)
        let newline = destinationDoc.newline
        let movedText = chunk.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }.joined(separator: newline) + newline
        var result: String
        let insertionLine: Int
        if let beforeBlockID {
            guard let target = destinationDoc.blocks.first(where: { $0.id == beforeBlockID }), target.kind != "global" else {
                throw ConfigError("The insertion point has changed. Drag the Host again.")
            }
            let rows = destinationDoc.lines
            var position = target.start
            while position > 0 && isComment(rows[position - 1]) { position -= 1 }
            let prefix = rows[..<position].joined(separator: "\n")
            let suffix = rows[position...].joined(separator: "\n")
            result = prefix.isEmpty ? "" : prefix + "\n"
            insertionLine = ConfigDocument(result).lines.count - 1
            result += movedText + newline + suffix
        } else {
            result = destination
            if !result.isEmpty && !result.hasSuffix("\n") { result += newline }
            if !result.isEmpty && !result.hasSuffix(newline + newline) { result += newline }
            insertionLine = ConfigDocument(result).lines.count - 1
            result += movedText
        }
        self.source = sourceRows.joined(separator: "\n")
        self.destination = result
        self.insertedBlockID = ConfigDocument(result).blocks.first { $0.kind == "host" && $0.start >= insertionLine }!.id
    }
}
