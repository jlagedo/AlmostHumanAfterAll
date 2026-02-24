import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.ficino", category: "HistoryStore")

// MARK: - HistoryEntry (@Model, internal)

@Model
final class HistoryEntry {
    var entryID: UUID
    var trackName: String
    var artist: String
    var album: String
    var genre: String
    var commentary: String
    var timestamp: Date
    var appleMusicURLString: String?
    var persistentID: String
    var isFavorited: Bool
    var isScrobbled: Bool = false
    var thumbnailData: Data?

    init(from record: CommentaryRecord) {
        self.entryID = record.id
        self.trackName = record.trackName
        self.artist = record.artist
        self.album = record.album
        self.genre = record.genre
        self.commentary = record.commentary
        self.timestamp = record.timestamp
        self.appleMusicURLString = record.appleMusicURL?.absoluteString
        self.persistentID = record.persistentID
        self.isFavorited = record.isFavorited
        self.isScrobbled = record.isScrobbled
        self.thumbnailData = record.thumbnailData
    }

    func toRecord() -> CommentaryRecord {
        CommentaryRecord(
            id: entryID,
            trackName: trackName,
            artist: artist,
            album: album,
            genre: genre,
            commentary: commentary,
            timestamp: timestamp,
            appleMusicURL: appleMusicURLString.flatMap { URL(string: $0) },
            persistentID: persistentID,
            isFavorited: isFavorited,
            isScrobbled: isScrobbled,
            thumbnailData: thumbnailData
        )
    }
}

// MARK: - HistoryStore (public actor)

public actor HistoryStore: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer

    private let capacity: Int
    public nonisolated let updates: AsyncStream<[CommentaryRecord]>
    private nonisolated let continuation: AsyncStream<[CommentaryRecord]>.Continuation

    public var modelContext: ModelContext {
        modelExecutor.modelContext
    }

    public init(capacity: Int = 200) throws {
        self.capacity = capacity
        let (stream, continuation) = AsyncStream.makeStream(of: [CommentaryRecord].self)
        self.updates = stream
        self.continuation = continuation

        let schema = Schema([HistoryEntry.self])

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDir = appSupport.appendingPathComponent("Ficino", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("history.store")

        let config = ModelConfiguration(
            "FicinoHistory",
            schema: schema,
            url: storeURL
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        self.modelContainer = container

        let context = ModelContext(container)
        context.autosaveEnabled = true
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    private func emitUpdate() {
        continuation.yield(getAll())
    }

    // MARK: - Public API

    public func save(_ record: CommentaryRecord) {
        let entry = HistoryEntry(from: record)
        modelContext.insert(entry)

        do {
            var countDescriptor = FetchDescriptor<HistoryEntry>()
            countDescriptor.propertiesToFetch = [\.entryID]
            let count = try modelContext.fetchCount(countDescriptor)

            if count > capacity {
                let excess = count - capacity
                var oldestDescriptor = FetchDescriptor<HistoryEntry>(
                    predicate: #Predicate { $0.isFavorited == false },
                    sortBy: [SortDescriptor(\.timestamp, order: .forward)]
                )
                oldestDescriptor.fetchLimit = excess
                let toDelete = try modelContext.fetch(oldestDescriptor)
                for item in toDelete {
                    modelContext.delete(item)
                }
            }
        } catch {
            logger.error("Capacity enforcement failed: \(error.localizedDescription)")
        }

        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save history entry: \(error.localizedDescription)")
        }
        emitUpdate()
    }

    public func getAll() -> [CommentaryRecord] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map { $0.toRecord() }
        } catch {
            return []
        }
    }

    public func getRecord(id: UUID) -> CommentaryRecord? {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.entryID == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try modelContext.fetch(descriptor).first?.toRecord()
        } catch {
            return nil
        }
    }

    public func search(query: String) -> [CommentaryRecord] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate {
                $0.trackName.localizedStandardContains(query) ||
                $0.artist.localizedStandardContains(query) ||
                $0.album.localizedStandardContains(query) ||
                $0.commentary.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map { $0.toRecord() }
        } catch {
            return []
        }
    }

    public func favorites() -> [CommentaryRecord] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.isFavorited == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor).map { $0.toRecord() }
        } catch {
            return []
        }
    }

    public func toggleFavorite(id: UUID) -> Bool? {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.entryID == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard let entry = try modelContext.fetch(descriptor).first else { return nil }
            entry.isFavorited.toggle()
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save favorite toggle: \(error.localizedDescription)")
            }
            emitUpdate()
            return entry.isFavorited
        } catch {
            return nil
        }
    }

    public func delete(id: UUID) {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.entryID == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard let entry = try modelContext.fetch(descriptor).first else { return }
            modelContext.delete(entry)
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save after delete: \(error.localizedDescription)")
            }
            emitUpdate()
        } catch {
            logger.error("Failed to fetch entry for deletion: \(error.localizedDescription)")
        }
    }

    public func syncLovedTracks(_ lovedKeys: Set<String>) {
        let descriptor = FetchDescriptor<HistoryEntry>()
        do {
            let entries = try modelContext.fetch(descriptor)
            var changed = false
            for entry in entries {
                let key = "\(entry.artist.lowercased())\t\(entry.trackName.lowercased())"
                let isLoved = lovedKeys.contains(key)
                if entry.isFavorited != isLoved {
                    entry.isFavorited = isLoved
                    changed = true
                    logger.debug("Sync: \(isLoved ? "loved" : "unloved") \"\(entry.trackName)\" by \(entry.artist)")
                }
            }
            if changed {
                try modelContext.save()
                emitUpdate()
                logger.info("Synced loved tracks with Last.fm")
            } else {
                logger.debug("Loved tracks already in sync")
            }
        } catch {
            logger.error("Failed to sync loved tracks: \(error.localizedDescription)")
        }
    }

    public func markScrobbled(id: UUID) {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.entryID == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard let entry = try modelContext.fetch(descriptor).first else { return }
            entry.isScrobbled = true
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save scrobble status: \(error.localizedDescription)")
            }
            emitUpdate()
        } catch {
            logger.error("Failed to fetch entry for scrobble update: \(error.localizedDescription)")
        }
    }

    public func updateThumbnail(id: UUID, data: Data) {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.entryID == id }
        )
        descriptor.fetchLimit = 1
        do {
            guard let entry = try modelContext.fetch(descriptor).first else { return }
            entry.thumbnailData = data
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save thumbnail update: \(error.localizedDescription)")
            }
            emitUpdate()
        } catch {
            logger.error("Failed to fetch entry for thumbnail update: \(error.localizedDescription)")
        }
    }
}
