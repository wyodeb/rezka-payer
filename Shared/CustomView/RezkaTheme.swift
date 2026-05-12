//
//  RezkaTheme.swift
//  rezka-player
//

import SwiftUI

enum RezkaTheme {
    static let cardCorner: CGFloat = 28
    static let chipCorner: CGFloat = 24
    static let buttonCorner: CGFloat = 20
}

enum RezkaPalette {
    static let background = Color(red: 0.06, green: 0.06, blue: 0.07)        // almost-black neutral charcoal
    static let surface = Color.white.opacity(0.10)                            // dark glass surface
    static let surfaceStrong = Color.white.opacity(0.18)
    static let surfaceStroke = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.70)
    static let tertiaryText = Color.white.opacity(0.45)
    static let onLight = Color.black                                          // text on white focus state
}

struct RezkaBackground: View {
    var body: some View {
        ZStack {
            RezkaPalette.background

            // very subtle vignette to add depth without color shift
            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: .top,
                startRadius: 50,
                endRadius: 900
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard: ViewModifier {
    var corner: CGFloat = RezkaTheme.cardCorner

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
    }
}

extension View {
    func glassCard(corner: CGFloat = RezkaTheme.cardCorner) -> some View {
        modifier(GlassCard(corner: corner))
    }
}

struct PillChip: View {
    let icon: String?
    let title: String
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
            }
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct PillButtonStyle: ButtonStyle {
    var isSelected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(isSelected: isSelected, configuration: configuration)
    }

    private struct PillBody: View {
        let isSelected: Bool
        let configuration: PillButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .foregroundStyle(foregroundColor)
                .background(
                    Capsule(style: .continuous)
                        .fill(backgroundStyle)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .scaleEffect(scale)
                .shadow(color: shadowColor, radius: isFocused ? 16 : 0, x: 0, y: isFocused ? 8 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.96 }
            if isFocused { return 1.04 }
            return 1.0
        }

        private var foregroundColor: Color {
            if isFocused || isSelected { return RezkaPalette.onLight }
            return RezkaPalette.primaryText
        }

        private var backgroundStyle: AnyShapeStyle {
            if isFocused || isSelected { return AnyShapeStyle(Color.white) }
            return AnyShapeStyle(RezkaPalette.surface)
        }

        private var strokeColor: Color {
            if isFocused || isSelected { return .clear }
            return RezkaPalette.surfaceStroke
        }

        private var shadowColor: Color {
            isFocused ? Color.black.opacity(0.55) : .clear
        }
    }
}

struct RezkaProgress: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Focus ring

private struct FocusRing: ViewModifier {
    let isFocused: Bool
    var inset: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(isFocused ? 0.85 : 0), lineWidth: 3)
                    .padding(-inset)
                    .animation(.easeOut(duration: 0.18), value: isFocused)
            )
    }
}

// MARK: - Play CTA

struct PlayActionButton: View {
    var title: String = "Play"
    var systemImage: String = "play.fill"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.bold))
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(PlayActionButtonStyle())
    }
}

private struct PlayActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlayBody(configuration: configuration)
    }

    struct PlayBody: View {
        let configuration: PlayActionButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .foregroundStyle(RezkaPalette.onLight)
                .background(
                    Capsule(style: .continuous).fill(Color.white)
                )
                .modifier(FocusRing(isFocused: isFocused))
                .scaleEffect(scale)
                .shadow(color: Color.black.opacity(isFocused ? 0.50 : 0.25), radius: isFocused ? 18 : 8, x: 0, y: isFocused ? 10 : 5)
                .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.96 }
            if isFocused { return 1.06 }
            return 1.0
        }
    }
}

// MARK: - Metadata chip

struct MetadataChip: View {
    let icon: String
    let caption: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipContent(icon: icon, caption: caption, value: value)
        }
        .buttonStyle(MetadataChipStyle())
    }

    private struct ChipContent: View {
        let icon: String
        let caption: String
        let value: String
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                Text(value)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .opacity(isFocused ? 0.85 : 0.55)
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(caption): \(value)")
        }
    }
}

private struct MetadataChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MetaBody(configuration: configuration)
    }

    struct MetaBody: View {
        let configuration: MetadataChipStyle.Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(foregroundColor)
                .background(
                    Capsule(style: .continuous).fill(backgroundStyle)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
                .modifier(FocusRing(isFocused: isFocused, inset: 5))
                .scaleEffect(scale)
                .shadow(color: shadowColor, radius: isFocused ? 14 : 0, x: 0, y: isFocused ? 8 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.97 }
            if isFocused { return 1.05 }
            return 1.0
        }

        private var foregroundColor: Color {
            isFocused ? RezkaPalette.onLight : RezkaPalette.primaryText
        }

        private var backgroundStyle: AnyShapeStyle {
            if isFocused { return AnyShapeStyle(Color.white) }
            return AnyShapeStyle(RezkaPalette.surface)
        }

        private var strokeColor: Color {
            isFocused ? .clear : RezkaPalette.surfaceStroke
        }

        private var shadowColor: Color {
            isFocused ? Color.black.opacity(0.55) : .clear
        }
    }
}
