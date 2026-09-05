import Foundation

public enum PeaksFileError: LocalizedError {
    case badMagic
    case unsupportedVersion(Int)
    case truncated

    public var errorDescription: String? {
        switch self {
        case .badMagic:
            "Il file dei peaks non è nel formato atteso."
        case .unsupportedVersion(let version):
            "Versione \(version) del formato peaks non supportata."
        case .truncated:
            "Il file dei peaks è troncato."
        }
    }
}

/// Serializzazione della cache della waveform.
///
/// Formato binario, little endian, tutto in un file solo per traccia:
///
/// ```
///  offset  campo
///   0      magic "CRPK"            4 byte
///   4      version                 UInt16
///   6      levelCount              UInt16
///   8      channelCount            UInt16
///  10      riservato               UInt16 + UInt32
///  16      sampleRate              Float64
///  24      frameCount              UInt64
///  32      tabella dei livelli     levelCount × (binSize UInt32, binCount UInt32, offset UInt64)
///   …      dati                    binCount × 5 byte per livello
/// ```
///
/// Cinque byte per bin: `min`, `max`, `low`, `mid`, `high`. Su un brano di 5:45 sono circa
/// 1,6 MB in tutto.
public enum PeaksFile {
    public static let version: UInt16 = 1
    public static let bytesPerBin = 5

    static let magic: [UInt8] = Array("CRPK".utf8)
    static let headerSize = 32
    static let levelEntrySize = 16

    // MARK: - Quantizzazione

    /// −1…1 → 0…255, con lo zero esatto a 128.
    static func encodeSigned(_ value: Float) -> UInt8 {
        let clamped = min(1, max(-1, value.isFinite ? value : 0))
        return UInt8(clamping: Int((clamped * 127).rounded()) + 128)
    }

    static func decodeSigned(_ byte: UInt8) -> Float {
        (Float(byte) - 128) / 127
    }

    /// 0…1 → 0…255 con compressione a radice quadrata.
    ///
    /// Lineare sprecherebbe quasi tutta la scala: l'RMS di banda della musica sta fra 0,02 e 0,3,
    /// cioè fra i valori 5 e 76 di 255. Con la radice lo stesso intervallo occupa da 36 a 140, e
    /// il rapporto fra le bande — che è ciò che determina il colore — resta leggibile anche nei
    /// passaggi piano.
    static func encodeUnit(_ value: Float) -> UInt8 {
        let clamped = min(1, max(0, value.isFinite ? value : 0))
        return UInt8(clamping: Int((clamped.squareRoot() * 255).rounded()))
    }

    static func decodeUnit(_ byte: UInt8) -> Float {
        let unit = Float(byte) / 255
        return unit * unit
    }

    // MARK: - Scrittura

    public static func encode(_ peaks: Peaks) -> Data {
        var data = Data()
        data.reserveCapacity(
            headerSize + peaks.levels.count * levelEntrySize
                + peaks.levels.reduce(0) { $0 + $1.count * bytesPerBin }
        )

        data.append(contentsOf: magic)
        append(version, to: &data)
        append(UInt16(peaks.levels.count), to: &data)
        append(UInt16(clamping: peaks.channelCount), to: &data)
        append(UInt16(0), to: &data)
        append(UInt32(0), to: &data)
        append(peaks.sampleRate.bitPattern, to: &data)
        append(UInt64(max(0, peaks.frameCount)), to: &data)

        var offset = UInt64(headerSize + peaks.levels.count * levelEntrySize)
        for level in peaks.levels {
            append(UInt32(level.binSize), to: &data)
            append(UInt32(level.count), to: &data)
            append(offset, to: &data)
            offset += UInt64(level.count * bytesPerBin)
        }

        for level in peaks.levels {
            var payload = [UInt8]()
            payload.reserveCapacity(level.count * bytesPerBin)
            for bin in level.bins {
                payload.append(encodeSigned(bin.minimum))
                payload.append(encodeSigned(bin.maximum))
                payload.append(encodeUnit(bin.low))
                payload.append(encodeUnit(bin.mid))
                payload.append(encodeUnit(bin.high))
            }
            data.append(contentsOf: payload)
        }
        return data
    }

    public static func write(_ peaks: Peaks, to url: URL) throws {
        try encode(peaks).write(to: url, options: .atomic)
    }

    // MARK: - Lettura

    public static func decode(_ data: Data) throws -> Peaks {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else { throw PeaksFileError.truncated }
        guard Array(bytes[0..<4]) == magic else { throw PeaksFileError.badMagic }

        let fileVersion = readUInt16(bytes, 4)
        guard fileVersion == version else {
            throw PeaksFileError.unsupportedVersion(Int(fileVersion))
        }

        let levelCount = Int(readUInt16(bytes, 6))
        let channelCount = Int(readUInt16(bytes, 8))
        let sampleRate = Double(bitPattern: readUInt64(bytes, 16))
        let frameCount = Int(readUInt64(bytes, 24))

        guard bytes.count >= headerSize + levelCount * levelEntrySize else {
            throw PeaksFileError.truncated
        }

        var levels = [PeaksLevel]()
        levels.reserveCapacity(levelCount)

        for index in 0..<levelCount {
            let entry = headerSize + index * levelEntrySize
            let binSize = Int(readUInt32(bytes, entry))
            let binCount = Int(readUInt32(bytes, entry + 4))
            let offset = Int(readUInt64(bytes, entry + 8))

            guard binSize > 0, binCount >= 0,
                  offset >= 0, offset + binCount * bytesPerBin <= bytes.count
            else { throw PeaksFileError.truncated }

            var bins = [PeakBin]()
            bins.reserveCapacity(binCount)
            for bin in 0..<binCount {
                let base = offset + bin * bytesPerBin
                bins.append(
                    PeakBin(
                        minimum: decodeSigned(bytes[base]),
                        maximum: decodeSigned(bytes[base + 1]),
                        low: decodeUnit(bytes[base + 2]),
                        mid: decodeUnit(bytes[base + 3]),
                        high: decodeUnit(bytes[base + 4])
                    )
                )
            }
            levels.append(PeaksLevel(binSize: binSize, bins: bins))
        }

        return Peaks(
            sampleRate: sampleRate,
            frameCount: frameCount,
            channelCount: channelCount,
            levels: levels
        )
    }

    public static func read(from url: URL) throws -> Peaks {
        try decode(Data(contentsOf: url))
    }

    // MARK: - Interi little endian

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in 0..<4 { value |= UInt32(bytes[offset + index]) << (8 * index) }
        return value
    }

    private static func readUInt64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(bytes[offset + index]) << (8 * index) }
        return value
    }
}
