#!/usr/bin/env bash
# Nova setup.sh — 사용자 프로젝트 부트스트랩 / v3 업그레이드 (Sprint 1-C)
#
# 모드:
#   bash scripts/setup.sh                      # 신규 부트스트랩 / 부분 업그레이드 (auto)
#   bash scripts/setup.sh --upgrade            # 기존 .nova/를 v3로 동기화 (idempotent)
#   bash scripts/setup.sh --dry-run            # 변경 사항만 출력
#
# 보장:
#   - idempotent: 두 번 실행해도 동일 상태 (git diff exit 0)
#   - 사용자 데이터 보존: 기존 work-items/*.json·README.md·index.json 절대 덮어쓰기 X
#   - .gitignore 패턴은 marker 블록으로만 관리 (수동 편집 영역 보존)
#
# 환경변수:
#   NOVA_PLUGIN_PATH       : 템플릿 source. 미지정 시 스크립트 dirname/.. 추정
#   NOVA_REGISTRY_ROOT     : 타겟. 미지정 시 CWD
#   NOVA_DRY_RUN=1         : --dry-run과 동일

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
NOVA_PLUGIN_PATH="${NOVA_PLUGIN_PATH:-${NOVA_PLUGIN_ROOT:-$(dirname "$SCRIPT_DIR")}}"
REGISTRY_ROOT="${NOVA_REGISTRY_ROOT:-$PWD}"

UPGRADE=0
DRY_RUN="${NOVA_DRY_RUN:-0}"
while [ $# -gt 0 ]; do
  case "$1" in
    --upgrade) UPGRADE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      cat <<'USAGE'
Nova setup — 사용자 프로젝트 v3 work-item registry 부트스트랩

사용:
  bash scripts/setup.sh                      신규 부트스트랩 / 부분 업그레이드 자동 감지
  bash scripts/setup.sh --upgrade            기존 .nova/ idempotent 동기화 (명시적)
  bash scripts/setup.sh --dry-run            변경 사항만 출력
USAGE
      exit 0
      ;;
    *) echo "[setup] ERR: 알 수 없는 옵션 '$1'" >&2; exit 2 ;;
  esac
  shift
done

WI_DIR="$REGISTRY_ROOT/.nova/work-items"
SCHEMA_DIR="$REGISTRY_ROOT/.nova/schema"
README_FILE="$REGISTRY_ROOT/.nova/README.md"
INDEX_FILE="$WI_DIR/index.json"
GITIGNORE="$REGISTRY_ROOT/.gitignore"

TEMPLATE_SCHEMA_DIR="$NOVA_PLUGIN_PATH/docs/templates/schema"
TEMPLATE_README="$NOVA_PLUGIN_PATH/docs/templates/nova-readme.md"

GITIGNORE_MARK_BEGIN="# === Nova v3 registry (managed by /nova:setup) — start ==="
GITIGNORE_MARK_END="# === Nova v3 registry — end ==="

log()  { echo "[setup] $*"; }
warn() { echo "[setup] WARN: $*" >&2; }
err()  { echo "[setup] ERR: $*" >&2; }

if [ "$DRY_RUN" = "1" ]; then log "DRY-RUN — 파일 시스템에 쓰지 않음"; fi

# ── pre-flight ──
if [ ! -d "$TEMPLATE_SCHEMA_DIR" ]; then
  err "템플릿 schema 미존재: $TEMPLATE_SCHEMA_DIR — NOVA_PLUGIN_PATH 확인"
  exit 2
fi
if [ ! -f "$TEMPLATE_README" ]; then
  err "템플릿 README 미존재: $TEMPLATE_README"
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  err "jq 미설치. 'brew install jq' 또는 패키지 매니저로 설치하세요."
  exit 2
fi

dry() {
  # dry $*  — DRY_RUN=1이면 미리보기만, 아니면 실행
  if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] $*"
    return 0
  fi
  eval "$@"
}

# ── 1. 디렉토리 ──
log "1) .nova/ 디렉토리 구조"
for d in .nova .nova/work-items .nova/schema .nova/local .nova/tmp; do
  if [ ! -d "$REGISTRY_ROOT/$d" ]; then
    dry "mkdir -p \"$REGISTRY_ROOT/$d\""
    echo "   + $d"
  fi
done

# ── 2. schema 동기화 (덮어쓰기 OK — plugin 관리 파일) ──
log "2) schema 동기화"
for src in "$TEMPLATE_SCHEMA_DIR"/*.schema.json; do
  [ -f "$src" ] || continue
  name=$(basename "$src")
  dest="$SCHEMA_DIR/$name"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    echo "   = $name (unchanged)"
  else
    dry "cp \"$src\" \"$dest\""
    echo "   + $name (synced)"
  fi
done

# ── 3. README (덮어쓰기 X — 사용자 수정 보존) ──
log "3) .nova/README.md"
if [ -f "$README_FILE" ]; then
  echo "   = README.md (existing, 보존)"
else
  dry "cp \"$TEMPLATE_README\" \"$README_FILE\""
  echo "   + README.md (created)"
fi

# ── 4. index.json ──
log "4) index.json 매니페스트"
if [ -f "$INDEX_FILE" ]; then
  if jq empty "$INDEX_FILE" 2>/dev/null && jq -e 'has("schema_version") and has("next_seq") and has("work_items")' "$INDEX_FILE" >/dev/null 2>&1; then
    echo "   = index.json (유효, 보존)"
  else
    warn "기존 index.json invalid — 백업 후 재생성: $(basename "$INDEX_FILE").invalid.bak"
    dry "mv \"$INDEX_FILE\" \"$INDEX_FILE.invalid.bak\""
    dry "jq -n '{schema_version:\"3.0\", next_seq:1, work_items:[], generated_at:(now | todate)}' > \"$INDEX_FILE\""
    echo "   + index.json (re-created)"
  fi
else
  dry "jq -n '{schema_version:\"3.0\", next_seq:1, work_items:[], generated_at:(now | todate)}' > \"$INDEX_FILE\""
  echo "   + index.json (created, next_seq=1)"
fi

# ── 5. .gitignore marker 블록 ──
log "5) .gitignore Nova marker 블록"

# 새 블록을 임시 파일에 작성 (BSD awk 호환)
new_block=$(mktemp -t nova-setup-XXXX)
cat > "$new_block" <<EOF
$GITIGNORE_MARK_BEGIN
.nova/*
!.nova/work-items/
!.nova/work-items/**
!.nova/schema/
!.nova/schema/**
!.nova/README.md
.nova/work-items/.lock/
.nova/events.jsonl
.nova/local/
.nova/tmp/
$GITIGNORE_MARK_END
EOF

if [ ! -f "$GITIGNORE" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] create $GITIGNORE with Nova marker block"
  else
    touch "$GITIGNORE"
  fi
fi

if [ -f "$GITIGNORE" ] && grep -qF "$GITIGNORE_MARK_BEGIN" "$GITIGNORE" 2>/dev/null; then
  # 기존 블록 추출
  cur_block=$(mktemp -t nova-setup-cur-XXXX)
  awk -v b="$GITIGNORE_MARK_BEGIN" -v e="$GITIGNORE_MARK_END" '
    $0==b{f=1} f{print} $0==e{f=0}
  ' "$GITIGNORE" > "$cur_block"
  if cmp -s "$cur_block" "$new_block"; then
    echo "   = Nova marker 블록 (unchanged)"
  else
    if [ "$DRY_RUN" = "1" ]; then
      echo "   [dry-run] replace Nova marker block in $GITIGNORE"
      echo "   --- 변경 diff ---"
      diff -u "$cur_block" "$new_block" | sed 's/^/     /' | head -30
    else
      tmp=$(mktemp -t nova-setup-tmp-XXXX)
      awk -v b="$GITIGNORE_MARK_BEGIN" -v e="$GITIGNORE_MARK_END" -v nbf="$new_block" '
        BEGIN {
          while ((getline line < nbf) > 0) new_content = new_content (new_content ? "\n" : "") line
          close(nbf)
        }
        $0==b { print new_content; skip=1; next }
        $0==e && skip { skip=0; next }
        !skip { print }
      ' "$GITIGNORE" > "$tmp"
      mv "$tmp" "$GITIGNORE"
      echo "   + Nova marker 블록 (synced)"
    fi
  fi
  rm -f "$cur_block"
else
  if [ "$DRY_RUN" = "1" ]; then
    echo "   [dry-run] append Nova marker block to $GITIGNORE"
  else
    {
      [ -s "$GITIGNORE" ] && echo ""
      echo "# Nova v3 work-item registry"
      cat "$new_block"
    } >> "$GITIGNORE"
    echo "   + Nova marker 블록 (appended)"
  fi
fi
rm -f "$new_block"

# ── 6. NOVA-STATE.md 안내만 ──
log "6) NOVA-STATE.md"
STATE_FILE="$REGISTRY_ROOT/NOVA-STATE.md"
if [ -f "$STATE_FILE" ]; then
  if grep -qF "<!-- nova:registry-rendered:start -->" "$STATE_FILE"; then
    echo "   = NOVA-STATE.md (v3 marker 존재)"
  else
    warn "   ! NOVA-STATE.md에 v3 marker 부재. '/nova:migrate-state --target=v3' 권장"
  fi
else
  warn "   ! NOVA-STATE.md 부재. '/nova:next' 또는 템플릿으로 생성하세요."
fi

echo ""
log "✅ 부트스트랩 완료 ($([ "$DRY_RUN" = "1" ] && echo "dry-run" || echo "applied"))"
log ""
log "다음 단계:"
log "  bash $SCRIPT_DIR/registry-write.sh create \"첫 work-item\"   # WI-0001 생성"
log "  cat .nova/README.md                                        # 사용법"
exit 0
