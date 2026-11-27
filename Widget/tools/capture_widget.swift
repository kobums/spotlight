// 바탕화면·알림 센터에 올려 둔 "지금 재생 중" 위젯을 화면에 보이는 그대로 PNG로 찍는다.
//
//   swift Widget/tools/capture_widget.swift <출력 폴더>
//
// 위젯은 알림 센터 프로세스의 창으로 그려진다. 그 창을 위젯 표시 이름으로 찾아 screencapture로 찍는다.
// 다른 창에 가려 있거나 다른 데스크탑에 있어도 찍힌다. 창 이름을 읽으려면 터미널에
// "화면 및 시스템 오디오 녹음" 권한이 있어야 한다.
import AppKit
import CoreGraphics

/// 위젯 표시 이름 (NowPlayingWidget의 configurationDisplayName과 같아야 한다).
let widgetName = "지금 재생 중"

guard CommandLine.arguments.count > 1 else {
    print("사용법: swift Widget/tools/capture_widget.swift <출력 폴더>")
    exit(1)
}
guard CGPreflightScreenCaptureAccess() else {
    print("터미널에 화면 기록 권한이 없습니다 (시스템 설정 › 개인정보 보호 및 보안 › 화면 및 시스템 오디오 녹음).")
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
var count = 0
for window in windows {
    guard window[kCGWindowName as String] as? String == widgetName,
          let pid = window[kCGWindowOwnerPID as String] as? pid_t,
          NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.notificationcenterui",
          let id = window[kCGWindowNumber as String] as? Int else { continue }
    count += 1
    let url = output.appendingPathComponent("widget-\(count).png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(id), url.path]
    try capture.run()
    capture.waitUntilExit()
    print(url.path)
}
if count == 0 {
    print("위젯 창을 찾지 못했습니다. 위젯을 바탕화면이나 알림 센터에 추가했는지 확인하세요.")
    exit(1)
}
