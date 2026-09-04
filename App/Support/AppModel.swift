import AppKit
import Foundation
import GRDB
import Observation
import DJKit

/// Cosa è selezionato nella barra laterale.
enum SidebarSelection: Hashable {
    case library
    case playlist(String)
}

/// Stato condiviso dell'applicazione: database aperto, repository, coda di import e le liste che
/// alimentano la UI.
///
/// Le liste si aggiornano da sole tramite `ValueObservation`: nessuna vista deve ricaricare a mano
/// dopo una scrittura.
@MainActor
@Observable
final class AppModel {
    private(set) var paths: LibraryPaths?
    private(set) var database: AppDatabase?
    private(set) var tracks: TrackRepository?
    private(set) var playlists: PlaylistRepository?
    private(set) var importQueue: ImportQueue?

    /// Se l'apertura della libreria fallisce lo diciamo, invece di mostrare un'app vuota e muta.
    private(set) var startupError: String?
    /// Errori recuperabili durante l'uso (foto illeggibile, salvataggio fallito).
    var transientError: String?

    var trackList: [Track] = []
    var playlistList: [Playlist] = []
    var selection: SidebarSelection? = .library
    var selectedTrackIDs: Set<String> = []
    var isImportSheetPresented = false
    var isInspectorPresented = true

    private var observers: [AnyDatabaseCancellable] = []

    init() {
        do {
            let paths = try LibraryPaths.standard()
            try paths.createDirectories()
            try paths.clearScratch()
            let database = try AppDatabase.open(at: paths.databaseURL)
            let trackRepository = TrackRepository(database: database)
            let locator = ToolLocator(paths: paths)

            self.paths = paths
            self.database = database
            self.tracks = trackRepository
            self.playlists = PlaylistRepository(database: database)
            self.importQueue = ImportQueue(
                runner: YtDlpRunner(locator: locator),
                converter: AudioConverter(locator: locator),
                repository: trackRepository,
                paths: paths
            )
            startObserving(database: database)
        } catch {
            startupError = String(describing: error)
        }
    }

    private func startObserving(database: AppDatabase) {
        guard let tracks, let playlists else { return }

        observers.append(
            tracks.observeAllTracks().start(
                in: database.reader,
                onError: { [weak self] error in self?.transientError = String(describing: error) },
                onChange: { [weak self] value in self?.trackList = value }
            )
        )
        observers.append(
            playlists.observeAllPlaylists().start(
                in: database.reader,
                onError: { [weak self] error in self?.transientError = String(describing: error) },
                onChange: { [weak self] value in self?.playlistList = value }
            )
        )
    }

    // MARK: - Selezione

    var selectedPlaylist: Playlist? {
        guard case .playlist(let id) = selection else { return nil }
        return playlistList.first { $0.id == id }
    }

    /// L'ispettore lavora su una traccia sola: con selezione multipla non mostra nulla.
    var selectedTrack: Track? {
        guard selectedTrackIDs.count == 1, let id = selectedTrackIDs.first else { return nil }
        return trackList.first { $0.id == id }
    }

    // MARK: - Tracce

    func save(track: Track) {
        guard let tracks else { return }
        Task {
            do { try await tracks.save(track) }
            catch { transientError = "Salvataggio non riuscito: \(error.localizedDescription)" }
        }
    }

    /// Elimina la traccia e i file che le appartengono. I cue point spariscono a cascata dal
    /// database; audio, peaks e foto vanno rimossi a mano perché stanno sul disco.
    func deleteTrack(_ track: Track) {
        guard let tracks, let paths else { return }
        let filesToRemove = [
            track.audioFilename.map { paths.audioURL(filename: $0) },
            track.peaksFilename.map { paths.peaksURL(filename: $0) },
            track.labelImageAFilename.map { paths.artworkURL(filename: $0) },
            track.labelImageBFilename.map { paths.artworkURL(filename: $0) },
        ].compactMap(\.self)

        Task {
            do {
                try await tracks.deleteTrack(id: track.id)
                selectedTrackIDs.remove(track.id)
                for url in filesToRemove {
                    try? FileManager.default.removeItem(at: url)
                }
            } catch {
                transientError = "Eliminazione non riuscita: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Foto delle etichette

    func setLabelImage(contentsOf url: URL, side: VinylSide, for track: Track) {
        guard let paths else { return }
        applyLabelImage(side: side, for: track) {
            try ArtworkStore.save(contentsOf: url, trackID: track.id, side: side, paths: paths)
        }
    }

    func setLabelImageFromPasteboard(side: VinylSide, for track: Track) {
        guard let paths else { return }
        guard let image = ArtworkStore.imageFromPasteboard() else {
            transientError = "Negli appunti non c'è un'immagine."
            return
        }
        applyLabelImage(side: side, for: track) {
            try ArtworkStore.save(image: image, trackID: track.id, side: side, paths: paths)
        }
    }

    func removeLabelImage(side: VinylSide, for track: Track) {
        guard let paths else { return }
        let existing = side == .a ? track.labelImageAFilename : track.labelImageBFilename
        if let existing { ArtworkStore.remove(filename: existing, paths: paths) }

        var updated = track
        switch side {
        case .a: updated.labelImageAFilename = nil
        case .b: updated.labelImageBFilename = nil
        }
        save(track: updated)
    }

    private func applyLabelImage(
        side: VinylSide,
        for track: Track,
        write: () throws -> String
    ) {
        do {
            let filename = try write()
            var updated = track
            switch side {
            case .a: updated.labelImageAFilename = filename
            case .b: updated.labelImageBFilename = filename
            }
            save(track: updated)
        } catch {
            transientError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Scalette

    func createPlaylist() {
        guard let playlists else { return }
        Task {
            do {
                let playlist = try await playlists.createPlaylist(name: "Nuova scaletta")
                selection = .playlist(playlist.id)
            } catch {
                transientError = "Creazione non riuscita: \(error.localizedDescription)"
            }
        }
    }

    func deletePlaylist(id: String) {
        guard let playlists else { return }
        Task {
            try? await playlists.deletePlaylist(id: id)
            if selection == .playlist(id) { selection = .library }
        }
    }

    func rename(playlist: Playlist, to name: String) {
        guard let playlists else { return }
        var updated = playlist
        updated.name = name
        Task { try? await playlists.save(updated) }
    }
}
