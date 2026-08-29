import AVFoundation
import SwiftUI
import UIKit

public struct VideoPlayerView: UIViewRepresentable {
    public enum Gravity: Sendable {
        case fit
        case fill

        fileprivate var avGravity: AVLayerVideoGravity {
            switch self {
            case .fit: .resizeAspect
            case .fill: .resizeAspectFill
            }
        }
    }

    public let player: AVPlayer
    public let gravity: Gravity

    public init(player: AVPlayer, gravity: Gravity = .fit) {
        self.player = player
        self.gravity = gravity
    }

    public func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity.avGravity
        return view
    }

    public func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        uiView.playerLayer.videoGravity = gravity.avGravity
    }
}

public final class PlayerLayerView: UIView {
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            preconditionFailure("PlayerLayerView must be backed by AVPlayerLayer")
        }
        return layer
    }
}
