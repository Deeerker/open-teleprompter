import SwiftUI

/// The script box that sits right under the camera, so your eyes stay close to the lens.
struct PrompterOverlay: View {
    @Bindable var prompter: Prompter
    let isRecording: Bool
    let height: CGFloat
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            textBox
            if !isRecording {
                controls
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }

    private var isEmpty: Bool {
        prompter.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var textBox: some View {
        TimelineView(.animation(paused: !prompter.isPlaying)) { context in
            Text(isEmpty ? "Toca aquí para escribir tu texto." : prompter.text)
                .font(.system(size: prompter.fontSize, weight: .semibold))
                .lineSpacing(prompter.fontSize * 0.15)
                .foregroundStyle(isEmpty ? .white.opacity(0.6) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight in
                    // Let the last lines scroll up to the top of the box.
                    let maxOffset = max(0, Double(textHeight) - prompter.fontSize * 2)
                    if prompter.maxOffset != maxOffset {
                        prompter.maxOffset = maxOffset
                    }
                }
                .offset(y: -prompter.offset(at: context.date))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .background(.black.opacity(0.5), in: .rect(cornerRadius: 18))
        .overlay(alignment: .bottomTrailing) {
            if isRecording && !prompter.isPlaying {
                Label("En pausa", systemImage: "pause.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.yellow, in: .capsule)
                    .padding(10)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if isRecording {
                prompter.togglePlayback()
            } else {
                onEdit()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { prompter.drag(translation: $0.translation.height) }
                .onEnded { _ in prompter.endDrag() }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(isRecording ? "Toca para pausar o seguir" : "Toca para editar el texto")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .accessibilityLabel("Editar texto")

            divider

            Button { prompter.changeFontSize(by: -4) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .disabled(prompter.fontSize <= Prompter.fontSizeRange.lowerBound)
            .accessibilityLabel("Letra más chica")

            Button { prompter.changeFontSize(by: 4) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .disabled(prompter.fontSize >= Prompter.fontSizeRange.upperBound)
            .accessibilityLabel("Letra más grande")

            divider

            Image(systemName: "tortoise.fill")
                .font(.caption)
                .accessibilityHidden(true)
            Slider(value: $prompter.speed, in: Prompter.speedRange)
                .accessibilityLabel("Velocidad")
            Image(systemName: "hare.fill")
                .font(.caption)
                .accessibilityHidden(true)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .tint(.yellow)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5), in: .capsule)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 1, height: 20)
    }
}
