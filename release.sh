#!/bin/bash
# 새 버전 배포: 태그 → 빌드 → GitHub Release → Homebrew tap 갱신
#   사용법: ./release.sh 1.0.1
set -euo pipefail
cd "$(dirname "$0")"

REPO="CheonWoong-Park/WinNote_for_Mac"
TAP="CheonWoong-Park/homebrew-tap"
CASK="Casks/winnote.rb"

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "사용법: ./release.sh <버전>   (예: ./release.sh 1.0.1)"
  exit 1
fi
TAG="v$VERSION"

# 1) 사전 확인
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "main 브랜치에서 실행하세요."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "커밋하지 않은 변경 사항이 있습니다."; exit 1; }
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "$TAG 태그가 이미 있습니다."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh auth login 이 필요합니다."; exit 1; }

# 2) 태그 후 빌드 (build.sh가 태그에서 버전을 읽어 zip 이름을 정함)
git tag "$TAG"
trap 'echo "실패: 로컬 태그 $TAG 를 지웁니다."; git tag -d "$TAG" >/dev/null 2>&1 || true' ERR
./build.sh release
ZIP="build/notepad-$VERSION.zip"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

# 3) 푸시와 GitHub Release
git push -q origin main
git push -q origin "$TAG"
trap - ERR
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "notepad $VERSION" --generate-notes

# 4) Homebrew tap의 cask 갱신
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh repo clone "$TAP" "$TMP/tap" -- -q
sed -i '' -E \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
  "$TMP/tap/$CASK"
git -C "$TMP/tap" add "$CASK"
git -C "$TMP/tap" commit -q -m "winnote $VERSION"
git -C "$TMP/tap" push -q origin main

echo ""
echo "배포 완료: notepad $VERSION"
echo "  릴리스: https://github.com/$REPO/releases/tag/$TAG"
echo "  업데이트: brew update && brew upgrade --cask winnote"
