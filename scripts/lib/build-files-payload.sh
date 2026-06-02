#!/usr/bin/env bash
# Nova build-files-payload.sh — review_pass 파일 바인딩 페이로드 생성 (v5.53.0+)
#
# review_pass 이벤트의 files[] 페이로드 [{path, content_sha256}] 를 생성한다.
# 게이트(hooks/pre-commit-reminder.sh)가 "리뷰가 현재 staged 파일을 커버하는가"를 검증하는
# 단일 진실원의 emitter 측. 게이트와 동일 소스(blob = `git show <ref>:<path>`)로 sha256을
# 계산해 리뷰 시점과 커밋 시점의 해시가 일치하게 한다.
#
# 사용법:
#   bash scripts/lib/build-files-payload.sh            # staged 파일 (git diff --cached) — /nova:review·check·run
#   bash scripts/lib/build-files-payload.sh --staged   # 동일(명시)
#   bash scripts/lib/build-files-payload.sh --head      # HEAD 커밋 파일 — release.sh (커밋 후 호출)
# 출력(stdout): JSON 배열 [{"path":...,"content_sha256":...}], 산출 불가 시 []
#
# 사용 예 (review_pass 발행):
#   FILES_JSON=$(bash "$ROOT/scripts/lib/build-files-payload.sh")
#   bash "$ROOT/hooks/record-event.sh" review_pass \
#     "$(jq -cn --argjson files "$FILES_JSON" '{verdict:"PASS",scope:"fast",files:$files}')"

set -u

# 의존성 없으면 빈 배열 (safe-default — emitter를 마비시키지 않음)
if ! command -v jq >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v shasum >/dev/null 2>&1; then
  echo "[]"
  exit 0
fi

MODE="staged"
case "${1:-}" in
  --head) MODE="head" ;;
  --staged|"") MODE="staged" ;;
esac

# 파일 목록 + blob 참조 prefix 결정
REF_PREFIX=":"            # staged blob
LIST_CMD_OUT=""
if [ "$MODE" = "head" ]; then
  REF_PREFIX="HEAD:"
  LIST_CMD_OUT=$(git -c core.quotepath=false show --name-only --format= HEAD 2>/dev/null | grep -v '^$' || true)
else
  LIST_CMD_OUT=$(git -c core.quotepath=false diff --cached --name-only 2>/dev/null || true)
fi

OUT="[]"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  sha=$(git show "${REF_PREFIX}${f}" 2>/dev/null | shasum -a 256 2>/dev/null | awk '{print $1}')
  [ -n "$sha" ] || continue
  OUT=$(printf '%s' "$OUT" | jq -c --arg p "$f" --arg s "$sha" '. + [{path:$p, content_sha256:$s}]' 2>/dev/null || printf '%s' "$OUT")
done <<EOF
$LIST_CMD_OUT
EOF

printf '%s\n' "$OUT"
