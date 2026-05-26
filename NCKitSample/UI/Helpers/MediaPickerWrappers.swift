import AVFoundation
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// PHPicker wrapper for selecting videos from the photo library.
/// Uses `.current` representation so 4K / HDR originals are exported when possible.
struct PhotoPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    var onFailure: ((String) -> Void)?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        if #available(iOS 15.0, *) {
            // `.compatible` transcodes down; `.current` keeps full resolution (4K, etc.).
            config.preferredAssetRepresentationMode = .current
        }
        VideoImportLogger.info(
            "Photo picker opened (filter=videos, representation=current, selectionLimit=1)"
        )
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onFailure: onFailure)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (URL) -> Void
        let onFailure: ((String) -> Void)?

        init(onPick: @escaping (URL) -> Void, onFailure: ((String) -> Void)?) {
            self.onPick = onPick
            self.onFailure = onFailure
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else {
                VideoImportLogger.info("Photo picker cancelled (no selection)")
                return
            }

            let assetId = result.assetIdentifier ?? "nil"
            VideoImportLogger.info("Photo picker selection assetIdentifier=\(assetId)")

            let provider = result.itemProvider
            let typeIds = Self.videoTypeIdentifiers(for: provider)
            guard let typeId = typeIds.first else {
                let registered = provider.registeredTypeIdentifiers.joined(separator: ", ")
                let msg = "Selected item is not a supported video type. Registered: [\(registered)]"
                VideoImportLogger.error(msg)
                deliverFailure(msg)
                return
            }

            VideoImportLogger.info("Loading file representation typeId=\(typeId) …")

            provider.loadFileRepresentation(forTypeIdentifier: typeId) { [weak self] url, error in
                guard let self else { return }

                if let error {
                    let msg = "Failed to load video from Photos: \(error.localizedDescription)"
                    VideoImportLogger.error(msg)
                    self.deliverFailure(msg)
                    return
                }

                guard let url else {
                    let msg = "Photos returned no file URL (item may still be downloading from iCloud)."
                    VideoImportLogger.error(msg)
                    self.deliverFailure(msg)
                    return
                }

                VideoImportLogger.fileSummary(url: url, label: "Photos ephemeral export")

                do {
                    let dest = try Self.copyToTemporaryVideo(from: url)
                    VideoImportLogger.fileSummary(url: dest, label: "Copied to temp for processing")
                    DispatchQueue.main.async {
                        self.onPick(dest)
                    }
                } catch {
                    let msg = "Could not copy video to temp: \(error.localizedDescription)"
                    VideoImportLogger.error(msg)
                    self.deliverFailure(msg)
                }
            }
        }

        private func deliverFailure(_ message: String) {
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?(message)
            }
        }

        /// Prefer types common for iPhone 4K (HEVC in .mov).
        private static func videoTypeIdentifiers(for provider: NSItemProvider) -> [String] {
            let candidates: [UTType] = [
                .movie,
                .quickTimeMovie,
                .mpeg4Movie,
                .video
            ]
            return candidates
                .map(\.identifier)
                .filter { provider.hasItemConformingToTypeIdentifier($0) }
        }

        private static func copyToTemporaryVideo(from source: URL) throws -> URL {
            let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("import_\(UUID().uuidString).\(ext)")

            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        }
    }
}

/// Document picker wrapper for selecting videos from Files.
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    var onFailure: ((String) -> Void)?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .video, .avi]
        VideoImportLogger.info("Document picker opened types=\(types.map(\.identifier))")
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onFailure: onFailure)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onFailure: ((String) -> Void)?

        init(onPick: @escaping (URL) -> Void, onFailure: ((String) -> Void)?) {
            self.onPick = onPick
            self.onFailure = onFailure
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            VideoImportLogger.info("Document picker cancelled")
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                VideoImportLogger.warning("Document picker returned no URL")
                return
            }
            VideoImportLogger.fileSummary(url: url, label: "Document picker selection")
            onPick(url)
        }
    }
}

// MARK: - Logging (shared by video import flow)

enum VideoImportLogger {
    private static let log = Logger(subsystem: "com.nckit.sample", category: "VideoImport")

    static func info(_ message: String) {
        log.info("\(message, privacy: .public)")
        #if DEBUG
        print("[VideoImport] \(message)")
        #endif
    }

    static func warning(_ message: String) {
        log.warning("\(message, privacy: .public)")
        #if DEBUG
        print("[VideoImport] ⚠️ \(message)")
        #endif
    }

    static func error(_ message: String) {
        log.error("\(message, privacy: .public)")
        #if DEBUG
        print("[VideoImport] ❌ \(message)")
        #endif
    }

    static func fileSummary(url: URL, label: String) {
        let path = url.path
        var sizeMB = "unknown"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let bytes = attrs[.size] as? Int64 {
            sizeMB = String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
        info("\(label): path=\(path) size=\(sizeMB)")
    }

    static func assetSummary(_ asset: AVURLAsset, label: String) async {
        do {
            let duration = try await asset.load(.duration).seconds
            var videoLine = "no video track"
            if let v = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await v.load(.naturalSize)
                let fps = try await v.load(.nominalFrameRate)
                videoLine = String(
                    format: "%.0f×%.0f @ %.1f fps",
                    size.width, size.height, fps
                )
            }
            let audioCount = (try await asset.loadTracks(withMediaType: .audio)).count
            info("\(label): duration=\(String(format: "%.1f", duration))s video=[\(videoLine)] audioTracks=\(audioCount)")
        } catch {
            warning("\(label): could not inspect asset — \(error.localizedDescription)")
        }
    }
}
