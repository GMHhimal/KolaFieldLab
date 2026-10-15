//
//  ZoomableImageView.swift
//  KolaCare
//
//  Pinch-to-zoom, drag-to-pan and double-tap-to-zoom image viewer with an
//  optional lesion-map overlay. Demonstrates simultaneous gesture composition.
//

import SwiftUI

struct ZoomableImageView: View {
    let image: UIImage
    var overlay: CGImage?
    var showsOverlay: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    if let overlay, showsOverlay {
                        Image(decorative: overlay, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .transition(.opacity)
                            .blendMode(.normal)
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .gesture(magnification.simultaneously(with: drag))
                .onTapGesture(count: 2) { toggleZoom() }
                .animation(.easeInOut(duration: 0.25), value: showsOverlay)
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(Text("Leaf photo"))
        .accessibilityHint(Text("Double-tap to zoom. Pinch to zoom further."))
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: Text("Zoom")) { toggleZoom() }
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 1), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { resetPosition() }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
            if scale > 1 {
                scale = 1; lastScale = 1
                offset = .zero; lastOffset = .zero
            } else {
                scale = 2.5; lastScale = 2.5
            }
        }
    }

    private func resetPosition() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            scale = 1; lastScale = 1
            offset = .zero; lastOffset = .zero
        }
    }
}
