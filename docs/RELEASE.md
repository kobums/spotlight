# 릴리스 & 배포 (Homebrew)

Spot 을 서명·공증해 GitHub 릴리스로 게시하고 `brew install --cask kobums/tap/spot` 으로
설치되게 하는 절차. 버전의 단일 출처는 저장소 루트의 `VERSION` 파일이다.

```
brew tap kobums/tap
brew install --cask spot
```

---

## 최초 1회 준비 (Apple 쪽)

### 1. Developer ID Application 인증서 발급

App Store 밖에서 배포하고 공증하려면 `Developer ID Application` 인증서가 필요하다
(`Apple Development` 인증서로는 다른 맥에서 Gatekeeper가 차단한다).

> Xcode → **Settings** → **Accounts** → 계정 선택 → **Manage Certificates…**
> → 좌하단 **+** → **Developer ID Application** → Done

발급 확인:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. 공증 자격증명 등록 (App Store Connect API 키)

이미 보유한 `AuthKey_XXXX.p8` 를 재사용한다. Issuer ID 는
App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
상단에 표시되는 UUID.

```bash
xcrun notarytool store-credentials spot-notary \
  --key ~/Downloads/AuthKey_XXXX.p8 \
  --key-id XXXX \
  --issuer <issuer-uuid>
```

`spot-notary` 프로파일이 keychain 에 저장되어 이후 로컬 릴리스에서 재사용된다.

---

## make 단축 명령

`make` 또는 `make help` 로 전체 목록을 본다.

| 명령 | 동작 |
|---|---|
| `make release` | 서명·공증 빌드 → `dist/Spot-<version>.zip` (게시 없음) |
| `make publish` | 위 + GitHub 릴리스 + tap cask 갱신 (로컬 전체 게시) |
| `make release-ci V=0.2.0` | `VERSION` 갱신·커밋·태그 push → GitHub Actions 자동 릴리스 |

## 로컬 릴리스

```bash
# 1. 버전 올리기
echo "0.2.0" > VERSION

# 2. 빌드 → 서명 → 공증 → staple → zip (dist/Spot-<version>.zip + sha256)
./scripts/release.sh          # = make release

# 3. 게시까지 (git 태그 + GitHub 릴리스 + cask 갱신)
TAP_DIR=~/develop/homebrew-tap ./scripts/release.sh --publish   # = make publish
```

`--publish` 없이 실행하면 `dist/` 에 결과물만 만들고 sha256 을 출력한다.
`spctl -a -vvv -t install build/Spot.app` 로 공증 통과를 검증할 수 있다.

---

## GitHub Actions 자동 릴리스

`v*` 태그를 push 하면 `.github/workflows/release.yml` 이 빌드·서명·공증·게시·cask 갱신을
모두 수행한다.

```bash
echo "0.2.0" > VERSION
git commit -am "release: 0.2.0"
git tag v0.2.0
git push origin main --tags
```

### 필요한 저장소 Secrets

| Secret | 값 |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | 인증서를 .p12 로 내보낸 뒤 `base64 -i cert.p12` |
| `DEVELOPER_ID_CERT_PASSWORD` | .p12 내보내기 암호 |
| `KEYCHAIN_PASSWORD` | CI 임시 keychain 암호 (임의 값) |
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8` |
| `ASC_KEY_ID` | 키 ID (`AuthKey_XXXX` 의 XXXX) |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID (UUID) |
| `TAP_REPO_TOKEN` | `kobums/homebrew-tap` push 권한 PAT (repo 스코프) |

`.p12` 내보내기: **키체인 접근** → 로그인 → 내 인증서 → `Developer ID Application` 을
개인 키와 함께 선택 → 우클릭 **2개 항목 내보내기…** → `.p12` 저장.

---

## Homebrew tap 저장소 (최초 1회)

cask 는 별도 저장소 `kobums/homebrew-tap` 에 둔다 (`brew install kobums/tap/spot` 규칙).

```bash
gh repo create kobums/homebrew-tap --public \
  --description "Homebrew tap for kobums apps"
git clone https://github.com/kobums/homebrew-tap ~/develop/homebrew-tap
mkdir -p ~/develop/homebrew-tap/Casks
# 첫 릴리스 후 release.sh --publish 또는 CI 가 Casks/spot.rb 를 채운다.
```

이후 릴리스마다 cask 의 `version`/`sha256`/`url` 은 `scripts/update-cask.sh` 가 자동 갱신한다.
