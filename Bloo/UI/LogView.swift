import Foundation
import SwiftUI

struct LogView: View {
    @Bindable var store: LogStorage
    @Binding var showLog: Bool
    @Binding var logHeight: CGFloat
    let maxHeight: CGFloat

    static let minHeight: CGFloat = 120

    @State private var originalHeight: CGFloat?

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                if let originalHeight {
                    logHeight = min(max(Self.minHeight, originalHeight - value.translation.height), maxHeight)
                } else {
                    originalHeight = logHeight
                }
            }
            .onEnded { _ in
                originalHeight = nil
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation {
                        showLog = false
                    }
                } label: {
                    Image(systemName: "xmark.square")
                }

                Button {
                    store.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Clear the log (⌘K)")

                Spacer()
                FilterField(filter: $store.filter)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.tertiary)
            }
            .background()
            .gesture(resizeGesture)
            .overlay(alignment: .top) {
                dragHandle
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.filteredMessages) { message in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                message.icon
                                    .bold()
                                    .frame(width: 28)
                                    .foregroundStyle(.accent)

                                Text(message.displayText)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, 4)

                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .transition(.move(edge: .bottom))
    }

    private var dragHandle: some View {
        Color.clear
            .frame(height: 10)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
            .gesture(resizeGesture)
        #if os(macOS)
            .pointerStyle(.frameResize(position: .top))
        #endif
    }
}
