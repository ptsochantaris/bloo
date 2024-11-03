import SwiftUI

private struct DimensionPreferenceKey: SwiftUI.PreferenceKey {
    static let defaultValue = CGFloat.zero
    static func reduce(value _: inout CGFloat, nextValue _: () -> CGFloat) {}
}

@MainActor
private struct TrackingHeightModifier: ViewModifier {
    let coordinateSpace: CoordinateSpace
    @Binding var height: CGFloat
    let animateSizing: Bool

    @State private var lastHeight: CGFloat = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader {
                    Color.clear
                        .preference(key: DimensionPreferenceKey.self, value: $0.frame(in: coordinateSpace).height.rounded(.up))
                        .onPreferenceChange(DimensionPreferenceKey.self) { newHeight in
                            Task { @MainActor in
                                if height == newHeight {
                                    return
                                }

                                let previousHeight = lastHeight
                                lastHeight = height

                                if previousHeight == newHeight {
                                    print("Warning: Detected bounced frame value while tracking, new: (\(newHeight) old: \(height)). Possible layout loop, ignoring.")
                                    return
                                }

                                if animateSizing {
                                    withAnimation {
                                        height = newHeight
                                    }
                                } else {
                                    height = newHeight
                                }
                            }
                        }
                }
            }
    }
}

@MainActor
private struct TrackingWidthModifier: ViewModifier {
    let coordinateSpace: CoordinateSpace
    @Binding var width: CGFloat
    let animateSizing: Bool

    @State private var lastWidth: CGFloat = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader {
                    Color.clear
                        .preference(key: DimensionPreferenceKey.self, value: $0.frame(in: coordinateSpace).width.rounded(.up))
                        .onPreferenceChange(DimensionPreferenceKey.self) { newWidth in
                            Task { @MainActor in
                                if width == newWidth {
                                    return
                                }

                                let previousHeight = lastWidth
                                lastWidth = width

                                if previousHeight == newWidth {
                                    print("Warning: Detected bounced frame value while tracking, new: (\(newWidth) old: \(width)). Possible layout loop, ignoring.")
                                    return
                                }

                                if animateSizing {
                                    withAnimation {
                                        width = newWidth
                                    }
                                } else {
                                    width = newWidth
                                }
                            }
                        }
                }
            }
    }
}

extension View {
    func trackingHeight(to height: Binding<CGFloat>, animateSizing: Bool = false) -> some View {
        modifier(TrackingHeightModifier(coordinateSpace: .local, height: height, animateSizing: animateSizing))
    }

    func trackingWidth(to width: Binding<CGFloat>, animateSizing: Bool = false) -> some View {
        modifier(TrackingWidthModifier(coordinateSpace: .local, width: width, animateSizing: animateSizing))
    }
}
