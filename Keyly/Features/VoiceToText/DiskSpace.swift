import Foundation

/// Free space check before downloading the model.
///
/// Without it a large download fails AT THE END: the user waits several minutes, sees progress
/// reach the end and gets a write error. The space is known up front — so it must be reported
/// up front.
enum DiskSpace {

    /// Space needed to download the Parakeet v3 model. This is NOT its size on disk: an archive
    /// is downloaded and intermediate files sit next to it, so requiring exactly the final size
    /// means failing during unpacking.
    ///
    /// This number has been wrong before: first "~480 MB" in the texts vs. 1.3 GB here, then
    /// "~900 MB" — measured on a folder that also held a copy from an older package version.
    /// The truth: one model = 469 MiB. Hence the rule — the size shown on screen is MEASURED
    /// (`LocalTranscriber.downloadedBytes()`), and this constant is only needed before download.
    /// 500 MB comes from measuring the real folder (469 MiB). It used to be 1.3 GB (the sum of two
    /// folders), and the app demanded 1.8 GB free for a half-gigabyte model: users with enough
    /// space were refused the download.
    static let modelBytes: Int64 = 500_000_000

    /// Headroom beyond the model. Unpacking and compilation need room for intermediate files,
    /// and the system on a full disk becomes unpredictable long before zero.
    static let headroomBytes: Int64 = 500_000_000

    enum Verdict: Equatable {
        case enough
        /// Not enough. Carries BOTH numbers: required and available — "free up space" without a
        /// number doesn't tell the user how much to clear.
        case notEnough(requiredBytes: Int64, availableBytes: Int64)
        /// Couldn't ask the system. The download is NOT blocked: refusing because we couldn't
        /// measure is worse than letting the user try.
        case unknown
    }

    static func check(availableBytes: Int64?) -> Verdict {
        guard let availableBytes else { return .unknown }
        let required = modelBytes + headroomBytes
        return availableBytes >= required ? .enough
                                          : .notEnough(requiredBytes: required,
                                                       availableBytes: availableBytes)
    }

    /// Free space where the package puts the model — in the Application Support folder.
    static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Human-readable size. Gigabytes with one decimal: "1.3 GB" is readable, "1300000000" isn't.
    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
