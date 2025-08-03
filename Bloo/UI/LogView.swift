import Foundation
import SwiftUI

struct LogView: View {
    @Bindable var store: LogStorage
    @Binding var showLog: Bool
    @Binding var logHeight: CGFloat

    @State private var originalHeight: CGFloat?

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
            .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .onChanged { value in
                    if let originalHeight {
                        logHeight = originalHeight - value.translation.height
                    } else {
                        originalHeight = logHeight
                    }
                }
                .onEnded { _ in
                    originalHeight = nil
                }
            )

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
}
