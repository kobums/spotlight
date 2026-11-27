import AppIntents
import SwiftUI
import WidgetKit

enum CardSize {
    case small, medium, large
}

/// 글자·버튼 색. 앨범 아트 배경 위에서는 흰색, 시스템이 배경을 걷어 낸 모드(틴트·투명·바탕화면 흐림)에서는 시스템 색.
struct CardPalette {
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var fill: Color
    /// 진행 막대의 빈 부분.
    var track: Color

    static let onBackdrop = CardPalette(
        primary: .white,
        secondary: .white.opacity(0.74),
        tertiary: .white.opacity(0.52),
        fill: .white.opacity(0.18),
        track: .white.opacity(0.24)
    )
    static let system = CardPalette(
        primary: .primary,
        secondary: .secondary,
        tertiary: .secondary.opacity(0.75),
        fill: .primary.opacity(0.12),
        track: .primary.opacity(0.16)
    )
}

extension EnvironmentValues {
    /// 진행 막대를 시간에 따라 흘리지 않고 한 시점의 모습으로 그린다. 위젯 밖에서 그림으로 뽑을 때 쓴다.
    @Entry var freezesProgress = false
}

/// 위젯 내용. 크기별 배치만 다르고 재료는 같다.
struct NowPlayingCard: View {
    let snapshot: NowPlayingSnapshot?
    let artwork: NSImage?
    let size: CardSize
    /// 멈춘 화면에서 재생 위치를 계산할 기준 시각.
    var date = Date()
    var palette = CardPalette.onBackdrop

    var body: some View {
        if let snapshot, snapshot.hasTrack {
            switch size {
            case .small:
                SmallCard(snapshot: snapshot, artwork: artwork, date: date, palette: palette)
            case .medium:
                MediumCard(snapshot: snapshot, artwork: artwork, date: date, palette: palette)
            case .large:
                LargeCard(snapshot: snapshot, artwork: artwork, date: date, palette: palette)
            }
        } else {
            EmptyCard(size: size, palette: palette)
        }
    }
}

// MARK: - 크기별 배치

private struct SmallCard: View {
    let snapshot: NowPlayingSnapshot
    let artwork: NSImage?
    let date: Date
    let palette: CardPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ArtworkTile(image: artwork, cornerRadius: 8, palette: palette)
                    .frame(width: 56, height: 56)
                Spacer(minLength: 0)
                Button(intent: PlayPauseIntent()) {
                    Image(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.primary)
                        .frame(width: 28, height: 28)
                        .background(palette.fill, in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(snapshot.isPlaying ? "일시 정지" : "재생")
            }
            Spacer(minLength: 6)
            Text(snapshot.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(2)
                .widgetAccentable()
            Text(snapshot.artist)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .padding(.top, 1)
            PlaybackProgress(snapshot: snapshot, date: date, palette: palette, showsTimes: false)
                .padding(.top, 8)
        }
    }
}

private struct MediumCard: View {
    let snapshot: NowPlayingSnapshot
    let artwork: NSImage?
    let date: Date
    let palette: CardPalette

    var body: some View {
        HStack(spacing: 14) {
            ArtworkTile(image: artwork, cornerRadius: 10, palette: palette)
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(snapshot.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
                if !snapshot.album.isEmpty {
                    Text(snapshot.album)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                        .padding(.top, 1)
                }
                Spacer(minLength: 4)
                PlaybackProgress(snapshot: snapshot, date: date, palette: palette, showsTimes: true)
                TransportControls(isPlaying: snapshot.isPlaying, palette: palette)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
    }
}

private struct LargeCard: View {
    let snapshot: NowPlayingSnapshot
    let artwork: NSImage?
    let date: Date
    let palette: CardPalette

    var body: some View {
        VStack(spacing: 0) {
            // 남는 높이만큼 정사각형으로 키운다.
            ArtworkTile(image: artwork, cornerRadius: 12, palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 아트를 크게 쓰려고 버튼은 제목 옆에 둔다.
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text(snapshot.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                TransportControls(isPlaying: snapshot.isPlaying, palette: palette)
            }
            .padding(.top, 12)
            PlaybackProgress(snapshot: snapshot, date: date, palette: palette, showsTimes: true)
                .padding(.top, 10)
        }
    }
}

private struct EmptyCard: View {
    let size: CardSize
    let palette: CardPalette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note")
                .font(.system(size: size == .small ? 26 : 32, weight: .medium))
                .foregroundStyle(palette.tertiary)
                .padding(.bottom, 2)
            Text("재생 중이 아님")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.secondary)
            if size != .small {
                Text("음악 앱에서 재생을 시작하면 여기에 나타납니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 재료

struct ArtworkTile: View {
    let image: NSImage?
    let cornerRadius: CGFloat
    let palette: CardPalette

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        // 틴트·투명 모드에서도 앨범 아트는 제 색으로.
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                } else {
                    GeometryReader { proxy in
                        ZStack {
                            palette.fill
                            Image(systemName: "music.note")
                                .font(.system(size: proxy.size.width * 0.42, weight: .medium))
                                .foregroundStyle(palette.tertiary)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
    }
}

/// 진행 막대와 시간. 재생 중에는 위젯을 새로 그리지 않아도 시스템이 알아서 흘려 준다.
private struct PlaybackProgress: View {
    let snapshot: NowPlayingSnapshot
    let date: Date
    let palette: CardPalette
    let showsTimes: Bool

    var body: some View {
        if snapshot.duration > 0 {
            VStack(spacing: 6) {
                ProgressBar(snapshot: snapshot, date: date, palette: palette)
                    .overlay { SeekTargets(trackToken: snapshot.trackToken) }
                if showsTimes {
                    times
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.tertiary)
                }
            }
        }
    }

    @ViewBuilder private var times: some View {
        HStack(spacing: 8) {
            if let interval = snapshot.playbackInterval, snapshot.isNormalSpeed {
                Text(timerInterval: interval, countsDown: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("-\(Text(timerInterval: interval, countsDown: true))")
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if snapshot.isPlaying, !snapshot.isNormalSpeed {
                // 배속 재생: 시스템의 시간 글자는 실제 시간으로만 흘러 곡의 시간과 어긋난다.
                // 막대는 맞는 속도로 흐르므로, 글자는 속도와 전체 길이만 보여 준다.
                Text(String(format: "%g×", (snapshot.rate * 100).rounded() / 100))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatPlaybackTime(snapshot.duration))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                let position = snapshot.position(at: date)
                Text(formatPlaybackTime(position))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("-" + formatPlaybackTime(snapshot.duration - position))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// 진행 막대.
///
/// 시스템 막대(`ProgressView`)를 그대로 보여 주지 않고 바탕과 채움을 직접 그린다.
/// 맥의 시스템 막대는 바탕이 불투명한 회색이라, 색을 버리고 불투명도만 남기는 단색 모드
/// (바탕화면 위젯이 창 뒤에서 흐려질 때)에서는 채움과 바탕이 한 덩어리가 되어 늘 꽉 찬 것처럼 보인다.
private struct ProgressBar: View {
    let snapshot: NowPlayingSnapshot
    let date: Date
    let palette: CardPalette

    @Environment(\.freezesProgress) private var freezesProgress

    var body: some View {
        Capsule()
            .fill(palette.track)
            .overlay {
                if let interval = snapshot.playbackInterval, !freezesProgress {
                    // 시간에 따라 스스로 움직이는 것은 시스템 막대뿐이라, 그것을 "어디까지 찼는지" 알려 주는 가리개로 쓴다.
                    Rectangle()
                        .fill(palette.primary)
                        .mask { TimerFillMask(interval: interval) }
                } else {
                    Rectangle()
                        .fill(palette.primary)
                        .scaleEffect(x: fraction, anchor: .leading)
                }
            }
            .clipShape(.capsule)
            .frame(height: 4)
            // 가리개로 쓰는 시스템 막대가 화면 읽기에 잡히지 않게 한다. 위치는 아래 시간 글자가 알려 준다.
            .accessibilityHidden(true)
    }

    private var fraction: Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(max(snapshot.position(at: date) / snapshot.duration, 0), 1)
    }
}

/// 진행 막대 위에 깔아 두는 보이지 않는 버튼들. 누른 칸의 위치로 재생 위치를 옮긴다.
///
/// 위젯은 끌기를 받지 못하고 버튼만 누를 수 있어, 막대를 여러 칸으로 나눠 칸마다 버튼을 둔다.
private struct SeekTargets: View {
    /// 한 칸의 너비(pt)가 이쯤 되도록 칸 수를 정한다.
    private static let targetWidth: CGFloat = 14
    /// 막대는 얇아서 누르기 어렵다. 위아래로 넓힌 높이(pt).
    private static let height: CGFloat = 22

    /// 지금 그리고 있는 곡. 누르는 사이 곡이 바뀌었으면 앱이 요청을 버리도록 함께 보낸다.
    let trackToken: String

    var body: some View {
        GeometryReader { proxy in
            let count = max(Int((proxy.size.width / Self.targetWidth).rounded()), 4)
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    // 칸의 가운데 위치로 옮긴다.
                    Button(intent: SeekIntent(fraction: (Double(index) + 0.5) / Double(count), track: trackToken)) {
                        Color.clear.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: Self.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        // 칸마다 읽히면 화면 읽기에 방해만 된다. 재생 제어는 아래 버튼으로 한다.
        .accessibilityHidden(true)
    }
}

/// `interval` 동안 왼쪽부터 차오르는 가리개. 찬 곳은 불투명하고 나머지는 투명하다.
///
/// 흰색으로 채운 시스템 막대에서 검은색으로 채운 같은 막대를 빼면(차이 혼합) 바탕은 서로 지워지고 채움만 흰색으로 남는다.
/// 그 밝기를 불투명도로 바꾼다. 시스템 막대의 바탕이 무슨 색이든 상관없다.
private struct TimerFillMask: View {
    let interval: ClosedRange<Date>

    var body: some View {
        ZStack {
            Color.black
            bar.tint(.white)
            bar.tint(.black)
                // 바탕과 채움을 한 장으로 합친 다음에 빼야 한다. 그러지 않으면 겹마다 따로 빠져 채움이 흐려진다.
                .compositingGroup()
                .blendMode(.difference)
        }
        .compositingGroup()
        .luminanceToAlpha()
        // 시스템 막대의 굵기와 상관없이 우리 막대를 다 덮게 세로로 늘린다.
        .scaleEffect(y: 3)
    }

    private var bar: some View {
        ProgressView(timerInterval: interval, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .labelsHidden()
    }
}

private struct TransportControls: View {
    let isPlaying: Bool
    let palette: CardPalette

    var body: some View {
        HStack(spacing: 4) {
            button(PreviousTrackIntent(), symbol: "backward.fill", label: "이전 곡", size: 15)
            button(PlayPauseIntent(), symbol: isPlaying ? "pause.fill" : "play.fill",
                   label: isPlaying ? "일시 정지" : "재생", size: 21)
            button(NextTrackIntent(), symbol: "forward.fill", label: "다음 곡", size: 15)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.primary)
    }

    private func button(_ intent: some AppIntent, symbol: String, label: String, size: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 40, height: 32)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }
}

/// 위젯 배경. 앱이 앨범 아트를 미리 흐리고 어둡게 만들어 둔 그림을 깐다.
struct CardBackdrop: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.10)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            // 글자가 놓이는 아래쪽을 조금 더 눌러 준다.
            LinearGradient(
                colors: [.black.opacity(0), .black.opacity(0.2)],
                startPoint: .center, endPoint: .bottom
            )
        }
    }
}
