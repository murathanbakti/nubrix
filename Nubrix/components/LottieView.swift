//
//  LottieView.swift
//  Nubrix
//
//  Created by Alexander on 2025-11-14.
//

import SwiftUI
import Lottie
import ObjectiveC

final class LottieHostView: NSView {
    let animationView = LottieAnimationView(configuration: LottieConfiguration(renderingEngine: .coreAnimation))
    var wantsPlayback = true { didSet { syncPlayback() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
            animationView.topAnchor.constraint(equalTo: topAnchor),
            animationView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncPlayback()
    }

    func syncPlayback() {
        guard animationView.animation != nil else { return }
        if wantsPlayback && window != nil {
            if !animationView.isAnimationPlaying {
                animationView.play()
            }
        } else if animationView.isAnimationPlaying {
            animationView.pause()
        }
    }
}

struct LottieView: NSViewRepresentable {
    let url: URL
    let speed: Double
    let loopMode: LottieLoopMode
    var isPlaying: Bool = true

    private static var associatedURLKey: UInt8 = 0

    func makeNSView(context: Context) -> LottieHostView {
        let host = LottieHostView()
        host.wantsPlayback = isPlaying
        return host
    }

    func updateNSView(_ host: LottieHostView, context: Context) {
        let animationView = host.animationView
        host.wantsPlayback = isPlaying
        let lastURL = objc_getAssociatedObject(animationView, &Self.associatedURLKey) as? URL
        if lastURL != url {
            objc_setAssociatedObject(animationView, &Self.associatedURLKey, url, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            let loopMode = loopMode
            let speed = speed
            LottieAnimation.loadedFrom(url: url) { [weak host] animation in
                guard let host, objc_getAssociatedObject(host.animationView, &Self.associatedURLKey) as? URL == url else { return }
                host.animationView.animation = animation
                host.animationView.loopMode = loopMode
                host.animationView.animationSpeed = CGFloat(speed)
                host.syncPlayback()
            }
        } else {
            animationView.loopMode = loopMode
            animationView.animationSpeed = CGFloat(speed)
            host.syncPlayback()
        }
    }

    static func dismantleNSView(_ host: LottieHostView, coordinator: ()) {
        host.wantsPlayback = false
        host.animationView.stop()
    }
}
