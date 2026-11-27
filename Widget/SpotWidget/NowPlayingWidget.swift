import OSLog
import SwiftUI
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot?
    let artwork: NSImage?
    let backdrop: NSImage?
}

struct NowPlayingProvider: TimelineProvider {
    private let log = Logger(subsystem: "com.gowoobro.spot.nowplaying", category: "widget")

    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: .sample, artwork: nil, backdrop: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        log.info("스냅숏 \(context.family.description, privacy: .public) \(Int(context.displaySize.width))×\(Int(context.displaySize.height)) 미리 보기 \(context.isPreview)")
        let entry = currentEntry()
        if context.isPreview, entry.snapshot?.hasTrack != true {
            // 위젯 갤러리에서는 빈 화면 대신 예시를 보여 준다.
            completion(placeholder(in: context))
        } else {
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // 놓인 위젯이 있다고 Spot에 알린다. Spot은 위젯이 있을 때만 재생 상태를 따라간다.
        WidgetPresence.announce()
        let now = Date()
        let entry = currentEntry(at: now)
        log.info("타임라인 \(context.family.description, privacy: .public) \(Int(context.displaySize.width))×\(Int(context.displaySize.height)): \(entry.snapshot?.title ?? "-", privacy: .private) [\(entry.snapshot?.state.rawValue ?? "없음", privacy: .public)] 아트 \(entry.artwork != nil)")

        // 곡이 바뀌거나 멈추면 앱이 위젯을 새로 고친다. 다만 앱의 요청이 늦거나 앱이 꺼져 있을 때를 대비해,
        // 곡이 끝날 시각에 "끝에서 멈춘 모습"을 걸어 두고 그때 상태 파일을 한 번 더 읽는다.
        if let snapshot = entry.snapshot, let interval = snapshot.playbackInterval {
            let end = interval.upperBound.addingTimeInterval(2)
            if end > now {
                let ended = NowPlayingEntry(date: end, snapshot: snapshot.endedCopy,
                                            artwork: entry.artwork, backdrop: entry.backdrop)
                completion(Timeline(entries: [entry, ended], policy: .atEnd))
            } else {
                // 끝날 시각이 이미 지났는데 새 상태가 없다: 앱이 꺼져 있다.
                let ended = NowPlayingEntry(date: now, snapshot: snapshot.endedCopy,
                                            artwork: entry.artwork, backdrop: entry.backdrop)
                completion(Timeline(entries: [ended], policy: .never))
            }
        } else {
            completion(Timeline(entries: [entry], policy: .never))
        }
    }

    private func currentEntry(at date: Date = .now) -> NowPlayingEntry {
        var snapshot = SharedStore.load()
        #if DEBUG
        if let override = DebugState.load() { snapshot = override }
        #endif
        return NowPlayingEntry(
            date: date,
            snapshot: snapshot,
            artwork: image(named: snapshot?.artworkFile),
            backdrop: image(named: snapshot?.backdropFile)
        )
    }

    private func image(named name: String?) -> NSImage? {
        guard let url = SharedStore.fileURL(name) else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        NowPlayingCard(
            snapshot: entry.snapshot,
            artwork: entry.artwork,
            size: cardSize,
            date: entry.date,
            palette: showsBackground ? .onBackdrop : .system
        )
        .containerBackground(for: .widget) {
            CardBackdrop(image: entry.snapshot?.hasTrack == true ? entry.backdrop : nil)
        }
        .widgetURL(DeepLink.openMusic)
    }

    private var cardSize: CardSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        default: .large
        }
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nowPlaying, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("지금 재생 중")
        .description("음악 앱이나 다른 앱에서 재생 중인 곡을 보여 줍니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview("작게", as: .systemSmall) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: .sample, artwork: nil, backdrop: nil)
    NowPlayingEntry(date: .now, snapshot: nil, artwork: nil, backdrop: nil)
}

#Preview("중간", as: .systemMedium) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: .sample, artwork: nil, backdrop: nil)
}

#Preview("크게", as: .systemLarge) {
    NowPlayingWidget()
} timeline: {
    NowPlayingEntry(date: .now, snapshot: .sample, artwork: nil, backdrop: nil)
}
