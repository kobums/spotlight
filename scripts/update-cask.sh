#!/bin/bash
# Homebrew cask 파일을 버전·sha256 으로 재생성한다.
# 사용: ./scripts/update-cask.sh <출력경로> <version> <sha256>
# release.sh --publish 가 자동 호출하며, tap 저장소 갱신용으로 단독 실행도 가능하다.
set -euo pipefail

OUT="$1"; VERSION="$2"; SHA="$3"

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<CASK
cask "spot" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/kobums/spotlight/releases/download/v#{version}/Spot-#{version}.zip"
  name "Spot"
  desc "Launcher and keyboard-driven screen access app"
  homepage "https://github.com/kobums/spotlight"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Spot.app"

  zap trash: [
    "~/Library/Application Support/Spot",
    "~/Library/Preferences/com.gowoobro.spot.plist",
  ]
end
CASK

echo "cask 작성: $OUT (version $VERSION)"
