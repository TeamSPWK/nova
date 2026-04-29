#!/usr/bin/env bash
# Nova publish-metrics.sh — 사용자 로컬 주간 리츄얼 (Sprint 3, measurement-spec.md §4)
#
# 동작:
#   1. nova-metrics.sh --json 으로 KPI 4종 산출
#   2. cwd_hash/session_id 금지 필드 strip 재검증 (publish-metrics 자체 가드)
#   3. period 산출 (UTC ISO 주차)
#   4. 이전 baselines 존재 시 delta_pct 계산
#   5. docs/baselines/{YYYY-WNN}.json 작성
#   6. README.md + README.ko.md AUTO-GEN 마커 영역 갱신
#   7. git pull --rebase + git diff 출력 + commit 안내 (실제 commit은 사용자 명시 결정)
#
# 옵션:
#   --dry-run            실제 파일 작성/git 작업 없이 stdout에 미리보기 (검증용)
#   --fixture <path>     events.jsonl 대신 사용 (테스트용)
#   --since <spec>       기본 30d (nova-metrics.sh 위임)
#
# 환경변수:
#   NOVA_TEST_INJECT_CWD_HASH=1   privacy 검증 테스트 — 의도적 위배 주입, abort 확인
#
# 실패 코드:
#   2 = 사전조건 (jq 미설치, repo 외부, 등)
#   3 = privacy 위배 (FATAL — commit 차단)
#   4 = git rebase 충돌

set -u

DRY_RUN=0
FIXTURE=""
SINCE="30d"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --fixture) FIXTURE="${2:-}"; shift 2 ;;
    --since)   SINCE="${2:-30d}"; shift 2 ;;
    -h|--help)
      sed -n '1,25p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) shift ;;
  esac
done

NOVA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$NOVA_ROOT"

# ── 사전 검증 ──
if ! command -v jq >/dev/null 2>&1; then
  echo "[publish-metrics] FATAL: jq 미설치" >&2
  exit 2
fi

if [[ ! -f "$NOVA_ROOT/.claude-plugin/plugin.json" && ! -f "$NOVA_ROOT/NOVA-STATE.md" ]]; then
  echo "[publish-metrics] FATAL: nova repo 외부 — abort" >&2
  exit 2
fi

# ── 1. KPI 산출 ──
NOVA_METRICS="$NOVA_ROOT/scripts/nova-metrics.sh"
NOVA_METRICS_ARGS=(--json --since "$SINCE")
if [[ -n "$FIXTURE" ]]; then
  NOVA_METRICS_ARGS+=(--fixture "$FIXTURE")
fi

KPIS_JSON=$(bash "$NOVA_METRICS" "${NOVA_METRICS_ARGS[@]}" 2>/dev/null) || {
  echo "[publish-metrics] FATAL: nova-metrics.sh --json 실패" >&2
  exit 2
}

if ! echo "$KPIS_JSON" | jq -e '. | type == "array" and length == 4' >/dev/null 2>&1; then
  echo "[publish-metrics] FATAL: KPI JSON 형식 위반 (4 KPI 배열 아님)" >&2
  exit 2
fi

# ── 1.5 테스트용 위배 주입 ──
if [[ "${NOVA_TEST_INJECT_CWD_HASH:-}" == "1" ]]; then
  echo "[publish-metrics] TEST: cwd_hash 위배 주입 — strip 가드 검증" >&2
  KPIS_JSON=$(echo "$KPIS_JSON" | jq '.[0] += {cwd_hash:"deadbeef"}')
fi

# ── 2. Privacy 재검증 (publish-metrics 자체 가드 — measurement-spec.md §4 금지 필드) ──
if echo "$KPIS_JSON" | jq -e 'any(.[]; has("cwd_hash") or has("session_id"))' >/dev/null 2>&1; then
  echo "[publish-metrics] FATAL: 금지 필드 노출 (cwd_hash 또는 session_id) — abort" >&2
  exit 3
fi

# ── 3. period 산출 (UTC ISO 8601 주차, GNU/BSD/Python3 호환) ──
PERIOD=$(date -u +%G-W%V)
read -r PERIOD_START PERIOD_END < <(python3 - "$PERIOD" << 'PY'
import sys, datetime
y, w = sys.argv[1].split("-W")
mon = datetime.date.fromisocalendar(int(y), int(w), 1)
sun = datetime.date.fromisocalendar(int(y), int(w), 7)
print(mon.isoformat(), sun.isoformat())
PY
)
PERIOD_START="${PERIOD_START:-$(date -u +%Y-%m-%d)}"
PERIOD_END="${PERIOD_END:-$(date -u +%Y-%m-%d)}"

# ── 4. delta 계산 (이전 baselines 존재 시) ──
PREV_FILE=""
if [[ -d "$NOVA_ROOT/docs/baselines" ]]; then
  PREV_FILE=$(ls -1 "$NOVA_ROOT"/docs/baselines/*.json 2>/dev/null | sort | tail -1 || true)
fi

merge_delta() {
  local current="$1" prev="$2"
  jq --slurpfile p "$prev" '
    [
      .[] as $cur |
      ($p[0].kpis[]? | select(.kpi == $cur.kpi)) as $pv |
      $cur + {
        delta_pct: (
          if $cur.pct == null or $pv.pct == null then null
          else ($cur.pct - $pv.pct) end
        )
      }
    ]
  ' <<< "$current"
}

if [[ -n "$PREV_FILE" && -f "$PREV_FILE" ]]; then
  KPIS_JSON=$(merge_delta "$KPIS_JSON" "$PREV_FILE")
fi

# ── 5. baselines JSON 조립 ──
NOVA_VERSION=$(tr -d '[:space:]' < "$NOVA_ROOT/scripts/.nova-version" 2>/dev/null || echo "unknown")
EVENTS_SCHEMA_VERSION=2  # spec §3 — 기본 v2 (drift 시 publish-metrics가 별도 결정)

OUT_FILE="$NOVA_ROOT/docs/baselines/${PERIOD}.json"
BASELINES_JSON=$(jq -n \
  --arg period "$PERIOD" \
  --arg ps "$PERIOD_START" \
  --arg pe "$PERIOD_END" \
  --arg nv "$NOVA_VERSION" \
  --argjson esv "$EVENTS_SCHEMA_VERSION" \
  --argjson kpis "$KPIS_JSON" \
  '{
    schema_version: 1,
    period: $period,
    period_start: $ps,
    period_end: $pe,
    nova_version: $nv,
    events_schema_version: $esv,
    kpis: $kpis
  }')

# ── 6. README badge 영역 갱신 ──
update_readme_badges() {
  local readme="$1"
  [[ ! -f "$readme" ]] && return 0
  local start_marker="<!-- nova-metrics:badges:start -->"
  local end_marker="<!-- nova-metrics:badges:end -->"
  if ! grep -q "$start_marker" "$readme" || ! grep -q "$end_marker" "$readme"; then
    echo "[publish-metrics] WARN: $readme 에 nova-metrics:badges 마커 부재 — skip" >&2
    return 0
  fi
  local badge_block
  badge_block=$(echo "$KPIS_JSON" | jq -r '.[] | "![\(.kpi)](\(.badge_url))"' | tr '\n' ' ')
  python3 - "$readme" "$start_marker" "$end_marker" "$badge_block" << 'PY'
import sys, re
path, start, end, block = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()
pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
replacement = f"{start}\n{block.strip()}\n{end}"
new = pattern.sub(replacement, src)
if new != src:
    with open(path, "w", encoding="utf-8") as f:
        f.write(new)
PY
}

# ── 7. dry-run / 실제 작성 분기 ──
if (( DRY_RUN == 1 )); then
  echo "Would write: docs/baselines/${PERIOD}.json"
  echo "$BASELINES_JSON"
  exit 0
fi

mkdir -p "$NOVA_ROOT/docs/baselines"
echo "$BASELINES_JSON" > "$OUT_FILE"
echo "[publish-metrics] 작성: docs/baselines/${PERIOD}.json"

update_readme_badges "$NOVA_ROOT/README.md"
update_readme_badges "$NOVA_ROOT/README.ko.md"

# ── 8. git pull --rebase + diff + commit 안내 ──
if [[ -d "$NOVA_ROOT/.git" ]]; then
  if ! git -C "$NOVA_ROOT" pull --rebase --quiet 2>/dev/null; then
    echo "[publish-metrics] WARN: git pull --rebase 실패 또는 충돌 — 수동 해결 후 재시도" >&2
    exit 4
  fi
  echo
  git -C "$NOVA_ROOT" diff --stat docs/baselines/ README.md README.ko.md 2>/dev/null || true
  echo
  echo "다음 명령으로 commit 하세요:"
  echo "  git add docs/baselines/${PERIOD}.json README.md README.ko.md"
  echo "  git commit -m 'metrics(${PERIOD}): 주간 baselines 갱신'"
fi

exit 0
