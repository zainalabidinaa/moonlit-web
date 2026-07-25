import SwiftUI
import MoonlitCore

// MARK: - Color Palette (warm tones only — no blue)

private enum MorphPalette {
    static let peach  = Color(red: 1.00, green: 0.55, blue: 0.42)
    static let coral  = Color(red: 0.95, green: 0.38, blue: 0.30)
    static let amber  = Color(red: 1.00, green: 0.73, blue: 0.30)
    static let cream  = Color(red: 0.96, green: 0.92, blue: 0.88)
    static let glowA  = Color(red: 1.00, green: 0.55, blue: 0.42)
    static let glowB  = Color(red: 1.00, green: 0.73, blue: 0.30)
}

// MARK: - Main View

struct MacLetteringMorph: View {
    @State private var phase: MorphPhase = .initial
    private let morphDuration: Double = 2.0

    var body: some View {
        ZStack {
            ambientGlows
            ambientParticles
            crescentAccent
            letteringRow
        }
        .frame(width: 800, height: 600)
        .background(MoonlitTheme.background)
        .onAppear(perform: startMorphTimeline)
    }

    // MARK: - Ambient Glows

    private var ambientGlows: some View {
        ZStack {
            glowLayer(color: MorphPalette.glowA,
                      size: CGSize(width: 420, height: 180),
                      blur: 68,
                      opacity: phase == .breathing ? 0.55 : 0.30)
                .offset(x: phases.isFormed ? 0 : -30,
                        y: phases.isFormed ? 0 : 20)
                .scaleEffect(phases.isFormed ? 1.05 : 0.92)
                .animation(.easeInOut(duration: morphDuration).delay(0.10), value: phase)

            glowLayer(color: MorphPalette.glowB,
                      size: CGSize(width: 340, height: 140),
                      blur: 56,
                      opacity: phase == .breathing ? 0.35 : 0.18)
                .offset(x: phases.isFormed ? 0 : 25,
                        y: phases.isFormed ? 0 : -15)
                .scaleEffect(phases.isFormed ? 0.97 : 1.04)
                .animation(.easeInOut(duration: morphDuration).delay(0.25), value: phase)
        }
        .allowsHitTesting(false)
    }

    private var phases: MorphPhases {
        MorphPhases(isFormed: phase == .formed || phase == .breathing)
    }

    private func glowLayer(color: Color, size: CGSize, blur: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.40), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(size.width, size.height) * 0.55
                )
            )
            .frame(width: size.width, height: size.height)
            .blur(radius: blur)
    }

    // MARK: - Ambient Particles

    private var ambientParticles: some View {
        ZStack {
            particle(x: 180, y: 140, size: 5, color: MorphPalette.amber, delay: 0.0)
            particle(x: 620, y: 380, size: 3, color: MorphPalette.peach,  delay: 0.4)
            particle(x: 150, y: 280, size: 4, color: MorphPalette.cream,  delay: 0.2)
            particle(x: 660, y: 160, size: 3, color: MorphPalette.coral,  delay: 0.6)
            particle(x: 280, y: 440, size: 2, color: MorphPalette.amber,  delay: 0.3)
            particle(x: 540, y: 200, size: 4, color: MorphPalette.glowA,  delay: 0.5)
        }
        .allowsHitTesting(false)
    }

    private func particle(x: CGFloat, y: CGFloat, size: CGFloat, color: Color, delay: Double) -> some View {
        let isActive = phase == .breathing
        return Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(isActive ? 0.55 : 0.15)
            .scaleEffect(isActive ? 1.0 : 0.4)
            .offset(x: isActive ? 0 : x * 0.024 * (x > 400 ? -1 : 1),
                    y: isActive ? 0 : y * 0.024 * (y > 300 ? -1 : 1))
            .animation(.easeInOut(duration: 1.6).delay(delay + 1.2), value: phase)
    }

    // MARK: - Crescent Accent

    private var crescentAccent: some View {
        Circle()
            .fill(MorphPalette.peach.opacity(0.12))
            .frame(width: 48, height: 48)
            .overlay(
                Circle()
                    .fill(MorphPalette.coral.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .blur(radius: 4)
            )
            .blur(radius: 3)
            .opacity(phase == .breathing ? 0.40 : 0.0)
            .offset(x: -300, y: 160)
            .animation(.easeInOut(duration: 1.2).delay(2.4), value: phase)
            .allowsHitTesting(false)
    }

    // MARK: - Lettering Row

    private var letteringRow: some View {
        HStack(spacing: 12) {
            LetterM(phase: phases)
            LetterO(phase: phases, index: 0)
            LetterO(phase: phases, index: 1)
            LetterN(phase: phases)
            LetterL(phase: phases)
            LetterI(phase: phases)
            LetterT(phase: phases)
        }
        .opacity(phase == .initial ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.5), value: phase)
    }

    // MARK: - Timeline

    private func startMorphTimeline() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: morphDuration)) {
                phase = .formed
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + morphDuration + 0.3) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    phase = .breathing
                }
            }
        }
    }
}

// MARK: - Phase Model

private enum MorphPhase: Equatable {
    case initial
    case formed
    case breathing
}

private struct MorphPhases: Equatable {
    let isFormed: Bool
}

// MARK: - Letter Piece

private struct LetterPieceView: View {
    let piece: LetterPieceDef
    let isFormed: Bool

    var body: some View {
        RoundedRectangle(
            cornerRadius: isFormed ? piece.finalCornerRadius : piece.scatteredCornerRadius,
            style: .continuous
        )
        .fill(isFormed ? piece.color : piece.scatteredColor)
        .frame(width: piece.size.width, height: piece.size.height)
        .rotationEffect(isFormed ? piece.finalRotation : piece.scatteredRotation)
        .scaleEffect(isFormed ? piece.finalScale : piece.scatteredScale)
        .offset(x: isFormed ? piece.finalOffset.x : piece.scatteredOffset.x,
                y: isFormed ? piece.finalOffset.y : piece.scatteredOffset.y)
        .opacity(isFormed ? 1.0 : piece.scatteredOpacity)
        .animation(.easeInOut(duration: 1.8).delay(piece.delay), value: isFormed)
    }
}

private struct LetterPieceDef {
    let size: CGSize
    let color: Color
    let scatteredColor: Color

    let finalOffset: CGPoint
    let scatteredOffset: CGPoint
    let finalRotation: Angle
    let scatteredRotation: Angle
    let finalScale: CGSize
    let scatteredScale: CGSize
    let finalCornerRadius: CGFloat
    let scatteredCornerRadius: CGFloat
    let scatteredOpacity: Double
    let delay: Double
}

// MARK: - Letter M

private struct LetterM: View {
    let phase: MorphPhases
    private static let t: CGFloat = 14
    private static let h: CGFloat = 116

    private let pieces: [LetterPieceDef] = [
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.peach, scatteredColor: MorphPalette.amber,
              finalOffset: CGPoint(x: -34, y: 0), scatteredOffset: CGPoint(x: -70, y: 45),
              finalRotation: .zero, scatteredRotation: .degrees(42),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.28, height: 0.28),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.18, delay: 0.00),
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.peach, scatteredColor: MorphPalette.coral,
              finalOffset: CGPoint(x: 34, y: 0), scatteredOffset: CGPoint(x: 65, y: -45),
              finalRotation: .zero, scatteredRotation: .degrees(-38),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.25, height: 0.25),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.15, delay: 0.06),
        .init(size: CGSize(width: t, height: 68),
              color: MorphPalette.amber, scatteredColor: MorphPalette.coral,
              finalOffset: CGPoint(x: -24, y: -24), scatteredOffset: CGPoint(x: -60, y: -70),
              finalRotation: .degrees(-26), scatteredRotation: .degrees(55),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.30, height: 0.30),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: 0.10),
        .init(size: CGSize(width: t, height: 68),
              color: MorphPalette.coral, scatteredColor: MorphPalette.amber,
              finalOffset: CGPoint(x: 24, y: -24), scatteredOffset: CGPoint(x: 55, y: -60),
              finalRotation: .degrees(26), scatteredRotation: .degrees(-48),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.26, height: 0.26),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.14, delay: 0.14),
        .init(size: CGSize(width: t, height: 58),
              color: MorphPalette.peach, scatteredColor: MorphPalette.coral,
              finalOffset: CGPoint(x: 0, y: 10), scatteredOffset: CGPoint(x: 0, y: 60),
              finalRotation: .zero, scatteredRotation: .degrees(20),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.22, height: 0.22),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.10, delay: 0.18),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                LetterPieceView(piece: p, isFormed: phase.isFormed)
            }
        }
        .frame(width: 82, height: Self.h)
    }
}

// MARK: - Letter O

private struct LetterO: View {
    let phase: MorphPhases
    let index: Int

    private static let t: CGFloat = 14
    private static let ow: CGFloat = 72
    private static let oh: CGFloat = 116
    private static let iw: CGFloat = ow - Self.t * 2
    private static let ih: CGFloat = oh - Self.t * 2

    private var pieces: [LetterPieceDef] {
        let base: Double = index == 0 ? 0.20 : 0.46
        let os: [CGPoint] = index == 0
            ? [CGPoint(x: 0, y: -65), CGPoint(x: 60, y: 0),  CGPoint(x: 0, y: 65),  CGPoint(x: -60, y: 0)]
            : [CGPoint(x: 30, y: -55), CGPoint(x: 55, y: 20), CGPoint(x: -15, y: 55), CGPoint(x: -55, y: -10)]
        let colors: [Color] = index == 0
            ? [MorphPalette.amber, MorphPalette.coral, MorphPalette.peach, MorphPalette.coral]
            : [MorphPalette.peach, MorphPalette.amber, MorphPalette.coral, MorphPalette.amber]

        let t = Self.t

        return [
            .init(size: CGSize(width: Self.iw, height: t),
                  color: MorphPalette.peach, scatteredColor: colors[0],
                  finalOffset: CGPoint(x: 0, y: -(Self.oh / 2 - t / 2)),
                  scatteredOffset: os[0],
                  finalRotation: .zero, scatteredRotation: .zero,
                  finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.28, height: 0.28),
                  finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: base),
            .init(size: CGSize(width: t, height: Self.ih),
                  color: MorphPalette.peach, scatteredColor: colors[1],
                  finalOffset: CGPoint(x: Self.ow / 2 - t / 2, y: 0),
                  scatteredOffset: os[1],
                  finalRotation: .zero, scatteredRotation: .zero,
                  finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.25, height: 0.25),
                  finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: base + 0.04),
            .init(size: CGSize(width: Self.iw, height: t),
                  color: MorphPalette.peach, scatteredColor: colors[2],
                  finalOffset: CGPoint(x: 0, y: Self.oh / 2 - t / 2),
                  scatteredOffset: os[2],
                  finalRotation: .zero, scatteredRotation: .zero,
                  finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.28, height: 0.28),
                  finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: base + 0.08),
            .init(size: CGSize(width: t, height: Self.ih),
                  color: MorphPalette.peach, scatteredColor: colors[3],
                  finalOffset: CGPoint(x: -(Self.ow / 2 - t / 2), y: 0),
                  scatteredOffset: os[3],
                  finalRotation: .zero, scatteredRotation: .zero,
                  finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.25, height: 0.25),
                  finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: base + 0.02),
        ]
    }

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                LetterPieceView(piece: p, isFormed: phase.isFormed)
            }
        }
        .frame(width: Self.ow, height: Self.oh)
    }
}

// MARK: - Letter N

private struct LetterN: View {
    let phase: MorphPhases
    private static let t: CGFloat = 14
    private static let h: CGFloat = 116
    private static let w: CGFloat = 68

    private let pieces: [LetterPieceDef] = [
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.peach, scatteredColor: MorphPalette.coral,
              finalOffset: CGPoint(x: -27, y: 0), scatteredOffset: CGPoint(x: -65, y: -40),
              finalRotation: .zero, scatteredRotation: .degrees(-25),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.28, height: 0.28),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: 0.30),
        .init(size: CGSize(width: t, height: h * 0.82),
              color: MorphPalette.coral, scatteredColor: MorphPalette.amber,
              finalOffset: CGPoint(x: -3, y: 8), scatteredOffset: CGPoint(x: 0, y: 60),
              finalRotation: .degrees(27), scatteredRotation: .degrees(42),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.22, height: 0.22),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.10, delay: 0.34),
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.amber, scatteredColor: MorphPalette.peach,
              finalOffset: CGPoint(x: 27, y: 0), scatteredOffset: CGPoint(x: 60, y: -35),
              finalRotation: .zero, scatteredRotation: .degrees(20),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.26, height: 0.26),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: 0.38),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                LetterPieceView(piece: p, isFormed: phase.isFormed)
            }
        }
        .frame(width: Self.w, height: Self.h)
    }
}

// MARK: - Letter L

private struct LetterL: View {
    let phase: MorphPhases
    private static let t: CGFloat = 14
    private static let h: CGFloat = 116
    private static let w: CGFloat = 48

    private let pieces: [LetterPieceDef] = [
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.peach, scatteredColor: MorphPalette.coral,
              finalOffset: CGPoint(x: -17, y: 0), scatteredOffset: CGPoint(x: -50, y: 45),
              finalRotation: .zero, scatteredRotation: .degrees(28),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.28, height: 0.28),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.12, delay: 0.42),
        .init(size: CGSize(width: w, height: t),
              color: MorphPalette.amber, scatteredColor: MorphPalette.amber,
              finalOffset: CGPoint(x: 0, y: h / 2 - t / 2),
              scatteredOffset: CGPoint(x: 30, y: 55),
              finalRotation: .zero, scatteredRotation: .degrees(-35),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.24, height: 0.24),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.10, delay: 0.46),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                LetterPieceView(piece: p, isFormed: phase.isFormed)
            }
        }
        .frame(width: Self.w, height: Self.h)
    }
}

// MARK: - Letter I

private struct LetterI: View {
    let phase: MorphPhases
    private static let t: CGFloat = 14
    private static let h: CGFloat = 116

    private let pieces: [LetterPieceDef] = [
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.coral, scatteredColor: MorphPalette.coral,
              finalOffset: .zero, scatteredOffset: CGPoint(x: -5, y: 55),
              finalRotation: .zero, scatteredRotation: .degrees(12),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.18, height: 0.18),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.08, delay: 0.50),
        .init(size: CGSize(width: t + 4, height: t + 4),
              color: MorphPalette.amber, scatteredColor: MorphPalette.amber,
              finalOffset: CGPoint(x: 0, y: -(h / 2 + 10)),
              scatteredOffset: CGPoint(x: 0, y: -70),
              finalRotation: .zero, scatteredRotation: .zero,
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.0, height: 0.0),
              finalCornerRadius: 12, scatteredCornerRadius: 12, scatteredOpacity: 0.0, delay: 0.52),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                LetterPieceView(piece: p, isFormed: phase.isFormed)
            }
        }
        .frame(width: 18, height: Self.h)
    }
}

// MARK: - Letter T

private struct LetterT: View {
    let phase: MorphPhases
    private static let t: CGFloat = 14
    private static let h: CGFloat = 116
    private static let w: CGFloat = 60

    private let pieces: [LetterPieceDef] = [
        .init(size: CGSize(width: w, height: t),
              color: MorphPalette.peach, scatteredColor: MorphPalette.amber,
              finalOffset: CGPoint(x: 0, y: -(h / 2 - t / 2)),
              scatteredOffset: CGPoint(x: 0, y: -65),
              finalRotation: .zero, scatteredRotation: .zero,
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.25, height: 0.25),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.10, delay: 0.56),
        .init(size: CGSize(width: t, height: h),
              color: MorphPalette.coral, scatteredColor: MorphPalette.coral,
              finalOffset: CGPoint(x: 0, y: 0), scatteredOffset: CGPoint(x: 0, y: 50),
              finalRotation: .zero, scatteredRotation: .degrees(8),
              finalScale: CGSize(width: 1, height: 1), scatteredScale: CGSize(width: 0.20, height: 0.20),
              finalCornerRadius: 7, scatteredCornerRadius: 38, scatteredOpacity: 0.08, delay: 0.60),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                LetterPieceView(piece: p, isFormed: phase.isFormed)
            }
        }
        .frame(width: Self.w, height: Self.h)
    }
}
