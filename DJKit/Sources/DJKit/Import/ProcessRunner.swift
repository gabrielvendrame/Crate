import Foundation

public struct ProcessResult: Sendable {
    public let standardOutput: String
    public let standardError: String
    public let terminationStatus: Int32

    public var didSucceed: Bool { terminationStatus == 0 }
}

public enum ProcessRunnerError: LocalizedError {
    case launchFailed(executable: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let reason):
            "Impossibile avviare \(executable): \(reason)"
        }
    }
}

/// Esecuzione di un binario sidecar con lettura dell'output riga per riga.
///
/// Lo standard output passa da una pipe, così il progresso di yt-dlp arriva mentre scarica; lo
/// standard error va invece su un file temporaneo. Leggere due pipe in parallelo richiederebbe di
/// far attraversare a `FileHandle` un confine di isolamento — cosa che Swift 6 non ammette — e
/// leggerle in sequenza rischierebbe lo stallo quando una delle due riempie il buffer del kernel.
public enum ProcessRunner {

    public static func run(
        executable: URL,
        arguments: [String],
        onOutputLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorURL = FileManager.default.temporaryDirectory
            .appending(path: "crate-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardError = errorHandle
        defer { try? FileManager.default.removeItem(at: errorURL) }

        // Registrato prima di `run()`: se il processo finisse subito, lo stato è comunque
        // conservato dallo stream.
        let exitStatus = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }

        do {
            try process.run()
        } catch {
            try? errorHandle.close()
            throw ProcessRunnerError.launchFailed(
                executable: executable.lastPathComponent,
                reason: error.localizedDescription
            )
        }

        var output = ""
        for try await line in outputPipe.fileHandleForReading.bytes.lines {
            output += line
            output += "\n"
            onOutputLine?(line)
        }

        var status: Int32 = -1
        for await value in exitStatus {
            status = value
        }

        try? errorHandle.close()
        let errorText = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""

        return ProcessResult(
            standardOutput: output,
            standardError: errorText,
            terminationStatus: status
        )
    }
}
