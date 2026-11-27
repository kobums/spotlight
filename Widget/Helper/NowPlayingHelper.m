// 시스템의 "지금 재생 중"(메뉴 막대·제어 센터에 나오는 것)을 읽어 표준 출력으로 내보내는 도우미.
//
// 그 정보는 비공개 프레임워크 MediaRemote에 있고, macOS 15.4부터는 애플이 정한 프로그램만 읽을 수 있다.
// 시스템에 들어 있는 /usr/bin/perl이 그 가운데 하나라, 앱이 perl을 띄워 이 라이브러리를 불러오게 한다
// (NowPlaying/System/SystemNowPlaying.swift). 공개된 길이 아니므로 macOS가 바뀌면 언제든 멈출 수 있고,
// 그때는 앱이 음악 앱만 보여 주던 원래 동작으로 돌아간다.
//
// 주고받는 것은 한 줄에 JSON 하나.
//   내보냄: {"type":"ready"}
//          {"type":"state","bundle":…,"key":…,"playing":…,"title":…,"artist":…,"album":…,"duration":…,"elapsed":…,"timestamp":…,"rate":…}
//          {"type":"state"}                       재생 중인 앱이 없음 (또는 내보낼 수 없는 값이 섞였음)
//          {"type":"artwork","key":…,"data":…}    앨범 아트 (base64). 같은 곡의 그림이 바뀌면 다시 내보낸다
//          {"type":"error","message":…}
//   받음:   playPause | next | previous | seek <초>
//
// 비공개 클래스·메서드는 있는지 확인하고 부른다. 없으면 그 정보만 빠진다.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>

static Class requestClass;
static Boolean (*sendCommand)(unsigned int, NSDictionary *);
static void (*setElapsedTime)(double);
static NSString *lastLine;
/// 지금 곡을 가리는 열쇠.
static NSString *currentKey;
/// 아트를 이미 내보낸 곡과 그 그림. 같은 곡의 그림이 바뀌었는지 볼 때 쓴다.
static NSString *artworkKey;
static NSData *artworkData;
/// 마지막으로 아트를 요청한 때(`uptime()`. 시계를 고쳐도 달라지지 않는다).
static NSTimeInterval artworkRequestedAt;
static BOOL artworkRequestIsRunning;
/// 그림을 아직 받지 못한 곡에 다시 물어본 횟수와, 다음에 다시 물어볼 때까지 둘 간격.
static int artworkMissAttempts;
static NSTimeInterval artworkRetryInterval;

static const NSUInteger maxArtworkBytes = 8 * 1024 * 1024;
/// 그림이 없는(또는 너무 커서 쓸 수 없는) 곡도 많다. 간격을 늘려 가며(1.5초에서 60초까지) 이만큼만 다시 물어본다.
/// 곡이 바뀐 직후의 요청 세 번(바로, 1.5초 뒤, 4초 뒤)은 따로라, 한 곡에 많아야 열한 번이다.
static const int maxArtworkMissAttempts = 8;
static const NSTimeInterval firstArtworkRetryInterval = 1.5;
static const NSTimeInterval maxArtworkRetryInterval = 60;
/// 제목·아티스트·앨범의 길이 한도(UTF-16 단위). 웹 페이지가 정한 제목도 이 길로 들어온다.
static const NSUInteger maxTextLength = 300;
static const NSUInteger maxBundleLength = 255;

static void emit(NSDictionary *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

/// 객체를 돌려주는 인자 없는 메서드를 부른다. 없으면 nil.
static id call(id target, const char *name) {
    SEL selector = sel_registerName(name);
    if (!target || ![target respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

/// 문자열이면 `limit`(UTF-16 단위)까지만 잘라 돌려준다. 문자열이 아니면 nil.
///
/// 짝이 맞지 않는 서로게이트(반쪽짜리 글자)는 U+FFFD로 바꾼다. 그대로 두면 JSON으로 만들 수 없어
/// 상태 줄을 내보내지 못하고, 위젯에는 앞 곡이 남는다. 다른 앱이나 웹 페이지가 정한 글자라 깨져 있을 수 있다.
static NSString *text(id value, NSUInteger limit) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *string = value;
    NSUInteger length = MIN(string.length, limit);
    if (length == 0) return @"";
    unichar *characters = malloc(length * sizeof(unichar));
    if (!characters) return @"";
    [string getCharacters:characters range:NSMakeRange(0, length)];
    // 자른 자리에 짝의 앞쪽만 남았으면 뺀다.
    if (length < string.length && CFStringIsSurrogateHighCharacter(characters[length - 1])) length -= 1;
    BOOL changed = length != string.length;
    for (NSUInteger index = 0; index < length; index++) {
        if (CFStringIsSurrogateHighCharacter(characters[index])
            && index + 1 < length && CFStringIsSurrogateLowCharacter(characters[index + 1])) {
            index += 1;  // 짝이 맞는 한 글자
        } else if (CFStringIsSurrogateHighCharacter(characters[index]) || CFStringIsSurrogateLowCharacter(characters[index])) {
            characters[index] = 0xFFFD;
            changed = YES;
        }
    }
    NSString *result = changed ? [NSString stringWithCharacters:characters length:length] : string;
    free(characters);
    return result;
}

/// 켜진 뒤 깨어 있던 시간(초).
static NSTimeInterval uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

/// 지금 곡의 아트를 요청한다. 곡에 아직 아트가 없거나 앞서 내보낸 것과 다르면 내보낸다.
/// - Returns: 요청을 실제로 보냈는지.
static BOOL requestArtwork(void) {
    @autoreleasepool {
        NSString *key = currentKey;
        if (!key) return NO;
        NSTimeInterval now = uptime();
        // 답이 오지 않는 요청에 영영 막히지 않게, 오래된 요청은 끝난 것으로 본다.
        if (artworkRequestIsRunning && now - artworkRequestedAt < 10) return NO;
        SEL selector = sel_registerName("requestNowPlayingItemArtworkOnQueue:completion:");
        id request = [[requestClass alloc] init];
        if (![request respondsToSelector:selector]) return NO;
        artworkRequestIsRunning = YES;
        artworkRequestedAt = now;
        void (^completion)(id, id) = ^(id artwork, id error) {
            @autoreleasepool {
                artworkRequestIsRunning = NO;
                if (![key isEqualToString:currentKey]) {
                    // 기다리는 사이 곡이 바뀌었다. 새 곡의 요청은 이 요청에 막혀 있었으므로 지금 한다.
                    requestArtwork();
                    return;
                }
                NSData *data = call(artwork, "imageData");
                // 너무 큰 그림은 없는 것으로 친다. 곡이 막 바뀐 때의 앞 곡 그림일 수도, 곧 다른 그림으로 바뀔 수도 있어
                // 그 곡을 영영 제쳐 두지는 않는다. 다시 묻는 횟수는 그림이 없을 때와 같은 규칙으로 묶인다.
                if (![data isKindOfClass:NSData.class] || data.length == 0 || data.length > maxArtworkBytes) return;
                if ([key isEqualToString:artworkKey] && [data isEqualToData:artworkData]) return;
                artworkKey = key;
                artworkData = [data copy];
                emit(@{@"type": @"artwork", @"key": key, @"data": [data base64EncodedStringWithOptions:0]});
            }
        };
        ((void (*)(id, SEL, id, id))objc_msgSend)(request, selector, dispatch_get_main_queue(), completion);
        return YES;
    }
}

/// JSON 한 줄로 만든다. 만들 수 없으면 nil.
static NSString *serialized(NSDictionary *message) {
    @try {
        NSData *data = [NSJSONSerialization dataWithJSONObject:message options:NSJSONWritingSortedKeys error:nil];
        return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

/// - Parameter fromNotification: 시스템 알림을 받아 부른 것인지(아니면 주기 확인).
static void publish(BOOL fromNotification) {
    @autoreleasepool {
    NSDictionary *info = call(call(requestClass, "localNowPlayingItem"), "nowPlayingInfo");
    if (![info isKindOfClass:NSDictionary.class]) info = nil;
    id client = call(call(requestClass, "localNowPlayingPlayerPath"), "client");
    // 브라우저처럼 재생을 보조 프로세스가 맡는 앱은 부모 앱의 이름으로 알린다.
    NSString *bundle = text(call(client, "parentApplicationBundleIdentifier"), maxBundleLength)
        ?: text(call(client, "bundleIdentifier"), maxBundleLength);
    NSString *title = text(info[@"kMRMediaRemoteNowPlayingInfoTitle"], maxTextLength) ?: @"";
    NSString *artist = text(info[@"kMRMediaRemoteNowPlayingInfoArtist"], maxTextLength) ?: @"";
    NSString *album = text(info[@"kMRMediaRemoteNowPlayingInfoAlbum"], maxTextLength) ?: @"";

    NSMutableDictionary *state = [@{@"type": @"state"} mutableCopy];
    NSString *key = nil;
    if (bundle.length > 0 && (title.length > 0 || artist.length > 0)) {
        NSNumber *duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
        NSNumber *elapsed = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
        NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        SEL isPlaying = sel_registerName("localIsPlaying");
        BOOL playing = [requestClass respondsToSelector:isPlaying] && ((BOOL (*)(id, SEL))objc_msgSend)(requestClass, isPlaying);
        // 일시 정지 직후에는 "재생 중"이 조금 늦게 꺼진다. 속도가 0이면 멈춘 것이다.
        if ([rate isKindOfClass:NSNumber.class] && rate.doubleValue == 0) playing = NO;

        key = [@[bundle, title, artist, album] componentsJoinedByString:@"\x1f"];
        state[@"bundle"] = bundle;
        state[@"key"] = key;
        state[@"playing"] = @(playing);
        state[@"title"] = title;
        state[@"artist"] = artist;
        state[@"album"] = album;
        if ([duration isKindOfClass:NSNumber.class] && isfinite(duration.doubleValue)) state[@"duration"] = duration;
        if ([elapsed isKindOfClass:NSNumber.class] && isfinite(elapsed.doubleValue)) state[@"elapsed"] = elapsed;
        if ([timestamp isKindOfClass:NSDate.class] && isfinite(timestamp.timeIntervalSince1970)) {
            state[@"timestamp"] = @(timestamp.timeIntervalSince1970);
        }
        // 배속 재생(1.5배 등)이면 진행 막대가 그 속도로 흘러야 한다.
        if (playing && [rate isKindOfClass:NSNumber.class] && isfinite(rate.doubleValue) && rate.doubleValue > 0) {
            state[@"rate"] = rate;
        }
    }

    NSString *line = serialized(state);
    if (!line) {
        // 내보낼 수 없는 값이 섞였다. 아무것도 내보내지 않으면 위젯에 앞 곡이 남으므로 "재생 중인 것 없음"을 알린다.
        state = [@{@"type": @"state"} mutableCopy];
        key = nil;
        line = serialized(state);
    }
    if (line && ![line isEqualToString:lastLine]) {
        lastLine = line;
        emit(state);
    }

    if (!key) {
        currentKey = nil;
    } else if (![key isEqualToString:currentKey]) {
        currentKey = key;
        artworkMissAttempts = 0;
        artworkRetryInterval = firstArtworkRetryInterval;
        requestArtwork();
        // 곡이 막 바뀐 때에는 그림이 늦게 준비되거나 앞 곡의 그림이 잠깐 남아 있기도 해서, 조금 뒤에 다시 본다.
        for (NSNumber *delay in @[@1.5, @4.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if ([key isEqualToString:currentKey]) requestArtwork();
            });
        }
    } else {
        NSTimeInterval sinceRequest = uptime() - artworkRequestedAt;
        if ([key isEqualToString:artworkKey]) {
            // 그림이 있다: 정보가 바뀔 때 가끔 그림도 바뀌었는지 본다(라디오처럼 제목은 그대로인데 그림만 바뀌는 경우).
            if (fromNotification && sinceRequest >= 10) requestArtwork();
        } else if (artworkMissAttempts < maxArtworkMissAttempts && sinceRequest >= artworkRetryInterval) {
            // 그림이 아직 없다: 늦게 준비되는 것일 수 있어 다시 물어보되, 간격을 늘려 가며 몇 번만 한다.
            // 정보를 자주 알리는 앱(웹 영상 등)에서 재생 내내 요청이 나가지 않게 한다.
            if (requestArtwork()) {
                artworkMissAttempts += 1;
                artworkRetryInterval = MIN(artworkRetryInterval * 2, maxArtworkRetryInterval);
            }
        }
    }
    }
}

static void handleCommand(NSString *command) {
    @autoreleasepool {
        if ([command hasPrefix:@"seek "]) {
            double seconds = [command substringFromIndex:5].doubleValue;
            if (setElapsedTime && isfinite(seconds) && seconds >= 0) setElapsedTime(seconds);
            return;
        }
        // MediaRemote의 명령 번호: 2 재생/일시 정지, 4 다음 곡, 5 이전 곡
        NSNumber *code = @{@"playPause": @2, @"next": @4, @"previous": @5}[command];
        if (code && sendCommand) sendCommand(code.unsignedIntValue, nil);
    }
}

/// perl이 이 라이브러리를 다 불러온 뒤에 부른다. 돌아오지 않는다.
__attribute__((visibility("default")))
void nowplaying_helper_main(void *unused1, void *unused2) {
    @autoreleasepool {
        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        requestClass = NSClassFromString(@"MRNowPlayingRequest");
        if (!framework || !requestClass || ![requestClass respondsToSelector:sel_registerName("localNowPlayingItem")]) {
            emit(@{@"type": @"error", @"message": @"MediaRemote를 쓸 수 없음"});
            exit(2);
        }
        sendCommand = dlsym(framework, "MRMediaRemoteSendCommand");
        setElapsedTime = dlsym(framework, "MRMediaRemoteSetElapsedTime");

        void (*registerForNotifications)(dispatch_queue_t) = dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (registerForNotifications) registerForNotifications(dispatch_get_main_queue());
        for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                                 @"kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification"]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                        usingBlock:^(NSNotification *notification) { publish(YES); }];
        }
        // 알림을 놓쳤을 때를 대비해 가끔 다시 본다. 달라진 것이 없으면 아무것도 내보내지 않는다.
        [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(NSTimer *timer) { publish(NO); }];

        // 앱이 보내는 명령을 읽는다. 앱이 끝나 입력이 닫히면 같이 끝난다.
        [NSThread detachNewThreadWithBlock:^{
            char buffer[64];
            while (fgets(buffer, sizeof buffer, stdin)) {
                @autoreleasepool {
                    NSString *command = [[NSString stringWithUTF8String:buffer]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (command) dispatch_async(dispatch_get_main_queue(), ^{ handleCommand(command); });
                }
            }
            exit(0);
        }];

        emit(@{@"type": @"ready"});
        publish(YES);
    }
    CFRunLoopRun();
    exit(0);
}
