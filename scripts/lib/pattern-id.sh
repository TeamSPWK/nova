#!/usr/bin/env bash
# Nova — pattern-id.sh
# events.jsonl 패턴 식별자 생성 (BSD/GNU 양호환)
#
# Usage:
#   source scripts/lib/pattern-id.sh
#   compute_pattern_id <event_type> [<tool>] [<timestamp_iso>]
#
# 출력: SHA-256 hex 앞 8자
#
# 형식: sha256("{event_type}:{tool|"-"}:{week_iso}")[:8]
#   - week_iso: ISO 8601 주 (예: "2026-W18")
#   - tool 미지정 시 "-" 사용
#   - timestamp 미지정 시 현재 UTC
#
# 안정성: 동일 입력 → 동일 출력 (단위 테스트 가드 권장).
# 충돌: 1/4G ≈ 1e-9 (v5.20.0 운영 데이터 2K~10K record 범위에서 발생 가능성 매우 낮음).

set -u

compute_pattern_id_week() {
  # week_iso 계산 (BSD/GNU 호환) — analyze-observations.sh 등에서 재사용
  local ts="${1:-}"
  local week_iso
  if [[ -z "$ts" ]]; then
    week_iso=$(date -u +"%G-W%V" 2>/dev/null)
  elif date -u -d "$ts" +"%G-W%V" >/dev/null 2>&1; then
    # GNU date (Linux)
    week_iso=$(date -u -d "$ts" +"%G-W%V")
  else
    # BSD date (macOS) — 타임존 suffix(+09:00, Z) 제거 후 파싱
    local ts_clean="${ts%+*}"
    ts_clean="${ts_clean%Z}"
    ts_clean="${ts_clean%.*}"
    week_iso=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "$ts_clean" +"%G-W%V" 2>/dev/null || echo "1970-W01")
  fi
  [[ -z "$week_iso" ]] && week_iso="1970-W01"
  printf '%s' "$week_iso"
}

compute_pattern_id() {
  local event_type="${1:?event_type required}"
  local tool="${2:-}"
  local ts="${3:-}"

  # ── week_iso 계산 ──
  local week_iso
  week_iso=$(compute_pattern_id_week "$ts")

  # ── 키 조립 ──
  local key="${event_type}:${tool:--}:${week_iso}"

  # ── SHA-256 hex 앞 8자 (BSD/GNU 호환) ──
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$key" | sha256sum | cut -c1-8
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$key" | shasum -a 256 | cut -c1-8
  else
    # 둘 다 없으면 fallback (운영에서 발생 가능성 낮음)
    echo "00000000"
    return 1
  fi
}

# ── 신뢰도 산출 (clamp 0~1) ──
# Usage: compute_confidence <n_unique_sessions> <n_accept> <n_reject>
# 공식: clamp(0, 1, 0.3 + 0.1·N_sessions + 0.2·N_accept - 0.3·N_reject)
# python3 사용 — bash 부동소수점 안정성 회피
compute_confidence() {
  local n_sessions="${1:-0}"
  local n_accept="${2:-0}"
  local n_reject="${3:-0}"

  python3 -c "
n_s = int('${n_sessions}')
n_a = int('${n_accept}')
n_r = int('${n_reject}')
score = 0.3 + 0.1 * n_s + 0.2 * n_a - 0.3 * n_r
clamped = max(0.0, min(1.0, score))
print(f'{clamped:.2f}')
" 2>/dev/null || echo "0.30"
}

# 직접 실행 시 첫 인자에 따라 분기 (CLI 호환)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    pattern-id|pattern_id)
      shift
      compute_pattern_id "$@"
      ;;
    confidence)
      shift
      compute_confidence "$@"
      ;;
    *)
      echo "Usage: $0 {pattern-id|confidence} <args...>" >&2
      exit 1
      ;;
  esac
fi
