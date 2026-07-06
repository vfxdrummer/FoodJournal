import SwiftUI

/// A brief "moment of delight" shown when a scan finishes having found new visits — a confetti
/// burst with the count popping in. Tap or wait to dismiss.
struct ScanCelebrationView: View {
    let count: Int
    let onDismiss: () -> Void

    @State private var pop = false
    @State private var shownCount = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ConfettiView()

            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                Text("\(shownCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: Double(shownCount)))
                    .foregroundStyle(Color("BrandGreen"))
                Text(count == 1 ? "new visit added" : "new visits added")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.quaternary, lineWidth: 0.5))
            .scaleEffect(pop ? 1 : 0.7)
            .opacity(pop ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true }
            withAnimation(.easeOut(duration: 0.9)) { shownCount = count }
        }
    }
}

/// A lightweight one-shot confetti burst. Each piece's motion is randomized once so it doesn't
/// change on re-render.
private struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let dx: CGFloat
        let dy: CGFloat
        let rotation: Double
        let color: Color
        let delay: Double
        let duration: Double
        let size: CGSize
    }

    @State private var pieces: [Piece]
    @State private var burst = false

    init() {
        let palette: [Color] = [.orange, .yellow, .green, .mint, .pink, .purple, Color("AccentColor"), Color("BrandGreen")]
        _pieces = State(initialValue: (0..<70).map { _ in
            Piece(
                dx: .random(in: -170...170),
                dy: .random(in: 240...580),
                rotation: .random(in: -360...360),
                color: palette.randomElement()!,
                delay: .random(in: 0...0.18),
                duration: .random(in: 1.2...2.2),
                size: CGSize(width: .random(in: 6...10), height: .random(in: 10...16))
            )
        })
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                Rectangle()
                    .fill(piece.color)
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotationEffect(.degrees(burst ? piece.rotation : 0))
                    .offset(x: burst ? piece.dx : 0, y: burst ? piece.dy : -40)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: piece.duration).delay(piece.delay), value: burst)
            }
        }
        .allowsHitTesting(false)
        .onAppear { burst = true }
    }
}
