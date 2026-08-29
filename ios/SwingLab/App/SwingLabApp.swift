import AVFoundation
import SwiftData
import SwiftUI
@main
struct SwingLabApp: App {
    private let modelContainer: ModelContainer?

    init() {
        modelContainer = SwingPersistence.makeLaunchContainer()
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                RootTabView()
                    .modelContainer(modelContainer)
                    .preferredColorScheme(.dark)
                    .task {
                        #if DEBUG
                        await DeviceAnalysisHarness.shared.runIfRequested()
                        #endif
                    }
            } else {
                ContentUnavailableView(
                    "Replay Caddie Can't Start",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Storage is unavailable. Restart the app or free device storage, then try again.")
                )
                .preferredColorScheme(.dark)
            }
        }
    }
}

#if DEBUG
/// Runs physical-device analysis against videos copied into the app's private
/// Documents/DeveloperInput directory. It is activated only by the explicit
/// `--analyze-developer-input` launch argument and does not compile into Release.
private actor DeviceAnalysisHarness {
    static let shared = DeviceAnalysisHarness()

    private var didRun = false

    func runIfRequested() async {
        guard !didRun,
              ProcessInfo.processInfo.arguments.contains("--analyze-developer-input") else {
            return
        }
        didRun = true

        let report = await makeReport()
        do {
            let data = try JSONEncoder.deviceHarness.encode(report)
            try data.write(to: Self.outputURL, options: .atomic)
            print("DEVICE_ANALYSIS_COMPLETE \(Self.outputURL.path)")
        } catch {
            print("DEVICE_ANALYSIS_REPORT_FAILED \(error.localizedDescription)")
        }
    }

    private func makeReport() async -> DeviceAnalysisHarnessReport {
        let inputURLs: [URL]
        do {
            inputURLs = try FileManager.default.contentsOfDirectory(
                at: Self.inputDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return DeviceAnalysisHarnessReport(
                generatedAt: Date(),
                videos: [],
                harnessError: error.localizedDescription
            )
        }

        var videoReports: [DeviceVideoAnalysisReport] = []
        for inputURL in inputURLs {
            videoReports.append(await analyze(inputURL))
        }
        return DeviceAnalysisHarnessReport(
            generatedAt: Date(),
            videos: videoReports,
            harnessError: inputURLs.isEmpty ? "No developer input videos were found." : nil
        )
    }

    private func analyze(_ inputURL: URL) async -> DeviceVideoAnalysisReport {
        do {
            let video = try await ImportedVideoValidator.validate(
                storedFileURL: inputURL,
                displayName: inputURL.lastPathComponent
            )
            let discoveryProgress = SwingAnalysisProgress()
            let discoveryPoseTrack = try await VideoPoseExtractor().extract(
                videoURL: video.fileURL,
                selectedRange: CMTimeRange(start: .zero, duration: video.duration),
                sampleRate: VideoSwingDiscoveryService.defaultSampleRate,
                minimumJointConfidence: 0.25,
                orientationOverride: nil,
                progress: discoveryProgress
            )
            let automaticCandidates = try SwingClipDetector.detect(
                in: discoveryPoseTrack,
                assetDuration: video.durationSeconds,
                minimumConfidence: 0.30
            )
            .map(SwingDiscoveryCandidate.init)
            let candidates: [(candidate: SwingDiscoveryCandidate, source: String)]
            if automaticCandidates.isEmpty {
                candidates = Self.knownValidationWindows(for: inputURL.lastPathComponent)
                    .map { ($0, "known validation window") }
            } else {
                candidates = automaticCandidates.map { ($0, "automatic detector") }
            }
            var clipReports: [DeviceClipAnalysisReport] = []
            for (candidate, source) in candidates {
                let range = CMTimeRange(
                    start: CMTime(seconds: candidate.startSeconds, preferredTimescale: 60_000),
                    duration: CMTime(
                        seconds: candidate.durationSeconds,
                        preferredTimescale: 60_000
                    )
                )
                do {
                    let analysis = try await SwingAnalysisPipeline().analyze(
                        videoURL: video.fileURL,
                        range: range,
                        context: SwingAnalysisContext(
                            cameraView: .downTheLine,
                            handedness: .right,
                            club: .driver,
                            sampleRate: 15,
                            minimumJointConfidence: 0.30
                        )
                    )
                    clipReports.append(DeviceClipAnalysisReport(
                        candidate: DeviceSwingCandidate(candidate, source: source),
                        analysis: analysis,
                        error: nil
                    ))
                } catch {
                    clipReports.append(DeviceClipAnalysisReport(
                        candidate: DeviceSwingCandidate(candidate, source: source),
                        analysis: nil,
                        error: error.localizedDescription
                    ))
                }
            }
            return DeviceVideoAnalysisReport(
                filename: inputURL.lastPathComponent,
                durationSeconds: video.durationSeconds,
                clips: clipReports,
                automaticClipCount: automaticCandidates.count,
                discoveryPoseTrack: discoveryPoseTrack,
                discoveryError: nil
            )
        } catch {
            return DeviceVideoAnalysisReport(
                filename: inputURL.lastPathComponent,
                durationSeconds: nil,
                clips: [],
                automaticClipCount: 0,
                discoveryPoseTrack: nil,
                discoveryError: error.localizedDescription
            )
        }
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var inputDirectory: URL {
        documentsDirectory.appendingPathComponent("DeveloperInput", isDirectory: true)
    }

    private static var outputURL: URL {
        documentsDirectory.appendingPathComponent("DeviceAnalysisReport.json")
    }

    /// Independent windows from the earlier desktop audit let the physical
    /// device validate pose extraction and critique generation even while an
    /// automatic-detector regression is being diagnosed.
    private static func knownValidationWindows(
        for filename: String
    ) -> [SwingDiscoveryCandidate] {
        let ranges: [(Double, Double)]
        switch filename.uppercased() {
        case "IMG_7801.MOV":
            ranges = [(35.55, 39.45), (87.05, 90.80)]
        case "IMG_7802.MOV":
            ranges = [(24.45, 28.18), (65.75, 69.56)]
        default:
            ranges = []
        }
        return ranges.map { start, end in
            SwingDiscoveryCandidate(
                id: start,
                startSeconds: start,
                endSeconds: end,
                confidence: 1
            )
        }
    }
}

private struct DeviceAnalysisHarnessReport: Codable, Sendable {
    let generatedAt: Date
    let videos: [DeviceVideoAnalysisReport]
    let harnessError: String?
}

private struct DeviceVideoAnalysisReport: Codable, Sendable {
    let filename: String
    let durationSeconds: Double?
    let clips: [DeviceClipAnalysisReport]
    let automaticClipCount: Int
    let discoveryPoseTrack: PoseTrack?
    let discoveryError: String?
}

private struct DeviceClipAnalysisReport: Codable, Sendable {
    let candidate: DeviceSwingCandidate
    let analysis: SwingAnalysisResult?
    let error: String?
}

private struct DeviceSwingCandidate: Codable, Sendable {
    let startSeconds: Double
    let endSeconds: Double
    let confidence: Double
    let source: String

    init(_ candidate: SwingDiscoveryCandidate, source: String) {
        startSeconds = candidate.startSeconds
        endSeconds = candidate.endSeconds
        confidence = candidate.confidence
        self.source = source
    }
}

private extension JSONEncoder {
    static var deviceHarness: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
#endif
