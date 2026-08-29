import PhotosUI
import SwiftUI

/// Camera-roll entry point for the import and trim flow.
public struct ImportTrimView: View {
    private let onAnalyze: (ImportedVideo, TrimSelection, SwingContextInput) -> Void

    @StateObject private var importModel: VideoImportModel
    @State private var pickerItem: PhotosPickerItem?

    public init(
        onAnalyze: @escaping (ImportedVideo, TrimSelection, SwingContextInput) -> Void
    ) {
        self.onAnalyze = onAnalyze
        self._importModel = StateObject(wrappedValue: VideoImportModel())
    }

    public var body: some View {
        Group {
            if let video = importModel.importedVideo {
                TrimSwingView(
                    video: video,
                    onAnalyze: onAnalyze,
                    onChooseAnother: chooseAnotherVideo
                )
            } else {
                pickerContent
            }
        }
        .background(Color(red: 0.045, green: 0.055, blue: 0.06).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            importModel.importVideo(from: newItem)
        }
        .onChange(of: importModel.phase) { _, phase in
            if case .failed = phase {
                // Let the user pick the same asset again after it finishes
                // downloading in Photos.
                pickerItem = nil
            }
        }
    }

    private var pickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("SwingLab")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
                    Text("See the move.\nOwn the fix.")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                        .foregroundStyle(Color(red: 0.97, green: 0.94, blue: 0.86))
                    Text("Choose one swing video. You’ll trim the exact swing before analysis starts.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                importCard

                VStack(alignment: .leading, spacing: 14) {
                    Label("Portrait or landscape video", systemImage: "rectangle.on.rectangle")
                    Label("Face-on or down-the-line camera", systemImage: "video")
                    Label("Your original stays in Photos", systemImage: "lock.shield")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 22)
            .padding(.top, 36)
            .padding(.bottom, 32)
        }
    }

    private var importCard: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color(red: 1, green: 0.42, blue: 0.34).opacity(0.16))
                    .frame(width: 72, height: 72)
                Image(systemName: importModel.isLoading ? "icloud.and.arrow.down" : "play.rectangle.on.rectangle")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.34))
            }

            switch importModel.phase {
            case .idle:
                Text("Import a swing")
                    .font(.title3.weight(.bold))
                Text("Pick a video from your camera roll. SwingLab makes a private working copy for analysis.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))

                pickerButton(title: "Choose from Photos", systemImage: "photo.on.rectangle")

            case .loading:
                Text("Loading full-quality video…")
                    .font(.title3.weight(.bold))
                Text("If this video is in iCloud, the download can take a moment. Keep SwingLab open.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(red: 1, green: 0.42, blue: 0.34))
                Button("Cancel") {
                    importModel.cancelImport()
                    pickerItem = nil
                }
                .foregroundStyle(.white.opacity(0.8))

            case let .failed(failure):
                Text(failure.title)
                    .font(.title3.weight(.bold))
                Text(failure.message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                Text(failure.recoverySuggestion)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.5))
                pickerButton(title: "Try another video", systemImage: "arrow.clockwise")

            case .ready:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func pickerButton(title: String, systemImage: String) -> some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .videos,
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        ) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color(red: 1, green: 0.42, blue: 0.34),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
        .accessibilityHint("Opens your photo library with videos only")
    }

    private func chooseAnotherVideo() {
        importModel.reset(removeImportedFile: true)
        pickerItem = nil
    }
}
