# [Design] Measurement Infrastructure

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> 작성자: Nova Design
> Plan: docs/plans/measurement-infrastructure.md

---

## Context (설계 배경)

### Plan 요약

Plan에서 결정된 4대 사항:

1. **pattern_id**: `sha256({event_type}:{tool|"-"}:{week_iso})` 의 hex 앞 8자
2. **`--accept`/`--reject`**: 기존 `evolve.md` 옵션 추가 (신규 커맨드 X)
3. **`evolve_decision` 이벤트**: JSONL only, NOVA-STATE 트리거 제외 (9 진입점 유지)
4. **신뢰도 공식**: `clamp(0, 1, 0.3 + 0.1·N_unique_sessions + 0.2·N_accept - 0.3·N_reject)`

### 설계 원칙

- **소급 산출 우선** (방안 A): 기록 시점에 confidence를 박지 않는다. 분석 시점에 in-memory 계산 → 기존 v1 record를 즉시 활용 가능.
- **flock + safe-default exit 0**: Sprint 1 자산 보존. 신규 코드도 동일 패턴.
- **수동 설정 금지**: `.nova/config.yml` 같은 사용자 편집 요구 X. 모든 설정은 코드 상수 또는 CLI 플래그.
- **9 진입점 동결**: NOVA-STATE 갱신 트리거를 늘리지 않는다 (`evolve_decision`은 JSONL only).
- **macOS BSD ↔ Linux GNU 양호환**: jq, sha256sum/shasum, date 명령어 차이 명시 처리.

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | pattern_id SHA-256 8자 안정 생성 (BSD/GNU 호환) | Medium | `shasum -a 256` (macOS) ↔ `sha256sum` (Linux) |
| 2 | analyze-observations.sh `--format json` 추가 시 텍스트 출력 회귀 0 | Medium | jq, 기존 3 분석 함수 |
| 3 | confidence 산출 함수 — N_unique_sessions/N_accept/N_reject 동시 집계 | High | jq group_by, evolve_decision 이벤트 분리 처리 |
| 4 | jq `// null` fallback의 BSD/GNU 동작 검증 (Critic 이슈 후속) | Medium | jq 1.6+ |
| 5 | record-event.sh schema v2 호환 — extra payload nullable 필드 가이드 | Low | 기존 `--argjson`/`--arg` 패턴 |
| 6 | evolve.md `--accept`/`--reject` 인라인 트리거 — bash heredoc + record-event.sh 호출 | Medium | 기존 hooks/record-event.sh CLI 인터페이스 |
| 7 | baseline 스냅샷 자동 생성 스크립트 (`scripts/snapshot-baseline.sh`) | Low | analyze-observations.sh + jq |
| 8 | 회귀 가드 +9 assert — 신뢰도 공식 8 케이스 + 기타 1 | Medium | tests/test-scripts.sh assert 패턴 |

### 기존 시스템과의 접점

- `hooks/record-event.sh:1-250` — schema_version 필드 접점, extra payload 호환
- `scripts/analyze-observations.sh:1-307` — 3 분석 함수와 새 confidence 함수 공존
- `.claude/commands/evolve.md:20` — `--from-observations` 모드 + 신규 `--accept`/`--reject` 옵션
- `tests/test-scripts.sh:62-250` — assert/assert_grep/assert_count 패턴 활용
- `docs/nova-rules.md §10` — 관찰성 계약 절에 신뢰도 공식 1줄
- `.claude/skills/context-chain/SKILL.md:17-27, 62` — JSONL × NOVA-STATE 표 1행 추가 (트리거 X 명시)

---

## Solution (설계 상세)

### 아키텍처

```
                    ┌─────────────────────────────────────────────┐
                    │      Phase 1 (v5.20.0): 분석 시점 산출       │
                    └─────────────────────────────────────────────┘

  Claude Code 도구 호출
        │
        ▼
   PreToolUse 훅 ──── record-event.sh ──┐
                                          │       (변경 X)
   SessionStart 훅 ─── record-event.sh ──┤
                                          ▼
   사용자 결정    ─── /nova:evolve       .nova/events.jsonl  (schema v2)
   (--accept)        --accept {p_id}      ────────┬────────
   (--reject)        --reject {p_id}              │
                          │                       │
                     record-event.sh              │
                     evolve_decision              │
                     ───────────────►─────────────┘
                                                  │
                                                  │ (read-only)
                                                  ▼
                                       analyze-observations.sh
                                       ┌──────────────────────┐
                                       │ compute_pattern_id() │ ─── jq stream
                                       │ compute_confidence() │ ─── clamp(0,1,…)
                                       │ filter ≥ threshold   │
                                       └──────────┬───────────┘
                                                  │
                                                  ▼
                                       --format json | text
                                                  │
                                                  ▼
                                       /nova:evolve --from-observations
                                       (≥0.7 만 표시 + 자동 승격 금지)


                    ┌─────────────────────────────────────────────┐
                    │  Phase 2 (v5.21.0): PostToolUse Spike + 훅   │
                    └─────────────────────────────────────────────┘

   Claude Code 도구 호출
        │
        ├──► PreToolUse 훅 (변경 X)
        │
        ├──► (도구 실행)
        │
        └──► PostToolUse 훅 ─── post-tool-use.sh ─── record-event.sh
                                  (Spike 통과 후)    extra.tool, .duration_ms
                                                       │
                                                       ▼
                                          .nova/events.jsonl (schema v2 풍부화)
```

### 데이터 계약 (Data Contract)

| 필드 | 타입 | 단위 | 기본값 | 변환 규칙 / 검증 |
|------|------|------|--------|-------------------|
| `schema_version` | int | — | 2 | record-event.sh 자동. v5.20.0부터 2 |
| `timestamp` | string | ISO 8601 (UTC) | required | `date -u +"%Y-%m-%dT%H:%M:%S+00:00"` |
| `monotonic_ns` | int | nanoseconds | required | wallclock skew 보정. `python3 -c "import time; print(time.monotonic_ns())"` |
| `session_id` | string | hex | required | CWD+PID+rand SHA-256 앞 16자 (기존 유지) |
| `event_type` | string (enum) | — | required | 12개: 기존 11 + `evolve_decision` (v5.20.0 신규) |
| `redacted` | bool | — | false | privacy filter 적용 여부 |
| `extra.tool` | string \| null | — | null | PostToolUse만 채움 (v5.21.0). `Bash`/`Read`/`Edit` 등 |
| `extra.duration_ms` | int \| null | **milliseconds** | null | Claude Code v2.1.119 PostToolUse stdin (Spike 후 채움) |
| `extra.confidence` | float \| null | 0.0~1.0 | null | **events.jsonl에 기록 X** — analyze-observations.sh 산출 시점에 부여 |
| `extra.pattern_id` | string \| null | hex 8자 | null | **evolve_decision 이벤트에만 기록** — 다른 이벤트는 분석 시점 in-memory 산출 |
| `extra.decision` | string (enum) | — | required (evolve_decision일 때) | `"accept"` 또는 `"reject"` |

#### pattern_id 생성 규칙 (BSD/GNU 호환)

```bash
# scripts/lib/pattern-id.sh (신규)
compute_pattern_id() {
  local event_type="$1"
  local tool="${2:-}"
  local ts="${3:-$(date -u +%Y-%m-%dT%H:%M:%S)}"
  
  local week_iso
  if date -u -d "$ts" +"%G-W%V" >/dev/null 2>&1; then
    # GNU date (Linux)
    week_iso=$(date -u -d "$ts" +"%G-W%V")
  else
    # BSD date (macOS) — -j -f 형식 사용
    week_iso=$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${ts%+*}" +"%G-W%V" 2>/dev/null || echo "1970-W01")
  fi
  
  local key="${event_type}:${tool:--}:${week_iso}"
  
  # SHA-256 hex 앞 8자 (BSD/GNU 호환)
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$key" | sha256sum | cut -c1-8
  else
    printf '%s' "$key" | shasum -a 256 | cut -c1-8
  fi
}
```

검증: 동일 입력 → 동일 출력 (단위 테스트로 확인). 충돌 확률 1/4G ≈ 1e-9. 충돌 시 두 패턴이 합쳐져 신뢰도가 부풀려질 수 있으나 v5.20.0 운영 데이터(2051줄)에서 발생 가능성 매우 낮음. v5.21.0+ 모니터링 항목.

#### confidence 산출 (분석 시점, in-memory)

```bash
# scripts/analyze-observations.sh 신규 함수
compute_confidence() {
  local n_sessions="$1"   # 고유 session_id 수
  local n_accept="$2"     # evolve_decision decision=accept 수
  local n_reject="$3"     # evolve_decision decision=reject 수
  
  python3 -c "
n_s = int('${n_sessions}')
n_a = int('${n_accept}')
n_r = int('${n_reject}')
score = 0.3 + 0.1 * n_s + 0.2 * n_a - 0.3 * n_r
clamped = max(0.0, min(1.0, score))
print(f'{clamped:.2f}')
"
}
```

> **왜 python3?** macOS bash의 부동소수점 처리 + clamp 안정성. python3는 Nova 메모리 ([Claude Code 설치 경로](#)) 환경에서 항상 가용 (record-event.sh도 python3 의존).

검증 8 케이스 (회귀 가드 ②):

| # | n_s | n_a | n_r | 기대 | 검증 의도 |
|---|-----|-----|-----|------|----------|
| 1 | 0 | 0 | 0 | 0.30 | 베이스 |
| 2 | 6 | 0 | 0 | 0.90 | N=6 → 0.9 도달 (clamp 미발동) |
| 3 | 7 | 0 | 0 | 1.00 | N=7 → 1.0 clamp |
| 4 | 0 | 1 | 0 | 0.50 | accept +0.2 |
| 5 | 0 | 2 | 0 | 0.70 | accept x2 → 0.7 |
| 6 | 0 | 0 | 1 | 0.00 | reject -0.3 → 0 clamp |
| 7 | 0 | 0 | 2 | 0.00 | reject x2 → 음수 clamp |
| 8 | 10 | 0 | 5 | 0.00 | 큰 값 + 거부 다수 → clamp 정상 |

#### evolve_decision 이벤트 기록 형태

```jsonl
{"schema_version":2,"timestamp":"2026-04-29T13:00:00+00:00","monotonic_ns":1234567890,"session_id":"abc123","event_type":"evolve_decision","redacted":false,"extra":{"pattern_id":"a3f2e1c8","decision":"accept"}}
```

evolve.md 인라인 트리거 (S1-3/S1-4):

```bash
# .claude/commands/evolve.md 안 (--accept 분기)
PATTERN_ID="${1:?pattern_id 필수}"  # 8자 hex
if [[ ! "$PATTERN_ID" =~ ^[0-9a-f]{8}$ ]]; then
  echo "❌ pattern_id 형식 오류: 8자 hex 필요" >&2
  exit 1
fi

bash hooks/record-event.sh evolve_decision \
  "$(jq -cn --arg p "$PATTERN_ID" --arg d "accept" \
       '{pattern_id:$p, decision:$d}')"

echo "✅ accept 기록: $PATTERN_ID"
echo "ℹ️  자동 승격 금지 — Skill 승격은 사용자가 명시적으로 결정"
```

`--reject` 분기는 `decision="reject"` 만 다름.

### baseline 스냅샷 형식 (S1-0)

`scripts/snapshot-baseline.sh` (신규):

```bash
#!/usr/bin/env bash
set -euo pipefail
NOVA_VERSION="$1"  # "v5.20.0"
OUT="docs/baselines/${NOVA_VERSION}-baseline.md"
mkdir -p docs/baselines

{
  echo "# Nova ${NOVA_VERSION} Baseline Snapshot"
  echo ""
  echo "> 생성: $(date -u +"%Y-%m-%dT%H:%M:%S+00:00")"
  echo "> 목적: ECC 흡수(P0-2/P0-3/P1-1) 이전 측정 기준선"
  echo ""
  echo "## 1. events.jsonl 통계"
  echo "- 라인 수: $(wc -l < .nova/events.jsonl 2>/dev/null || echo 0)"
  echo "- 파일 크기: $(du -h .nova/events.jsonl 2>/dev/null | cut -f1 || echo 0)"
  echo "- schema_version=1: $(jq -c 'select(.schema_version==1)' .nova/events.jsonl 2>/dev/null | wc -l || echo 0)"
  echo "- schema_version=2: $(jq -c 'select(.schema_version==2)' .nova/events.jsonl 2>/dev/null | wc -l || echo 0)"
  echo ""
  echo "## 2. analyze-observations 출력"
  echo '```'
  bash scripts/analyze-observations.sh 2>/dev/null || echo "(no data)"
  echo '```'
  echo ""
  echo "## 3. Evaluator FAIL률 (최근 30일)"
  # evaluator_verdict 이벤트 집계
  # ...
  echo ""
  echo "## 4. tools 호출 빈도 Top 10"
  # tool_call 이벤트 tool 별 카운트
  echo ""
  echo "## 5. 측정 메타"
  echo "- Nova 버전: ${NOVA_VERSION}"
  echo "- jq 버전: $(jq --version 2>/dev/null || echo 'n/a')"
  echo "- OS: $(uname -s)"
} > "$OUT"

echo "✅ baseline 스냅샷 저장: $OUT"
```

S1-0에서 `bash scripts/snapshot-baseline.sh v5.20.0` 1회 호출 → docs/baselines/v5.20.0-baseline.md 생성.

### 에러 처리

| 시나리오 | 처리 |
|---------|------|
| record-event.sh 실패 (lock timeout 등) | stderr WARN + exit 0 (safe-default) |
| analyze-observations.sh `--format json` 출력에 v1 record null 필드 | jq `// null` fallback. 출력 헤더에 "v1 record N건 confidence 없음" 안내 |
| `--accept` 인자 형식 오류 (8자 hex 아님) | exit 1 + 에러 메시지. evolve_decision 미기록 |
| pattern_id 충돌 (1e-9 이하) | v5.20.0 무시. v5.21.0+ 모니터링 추가 |
| baseline 스크립트 실행 시 .nova/events.jsonl 부재 | "(no data)" 출력. 빈 baseline 파일 생성 (회귀 가드 통과용) |
| jq 부재 | record-event.sh 진입 시 검증 (기존 동작 유지) |
| BSD date `-d` 옵션 부재 (macOS) | `-j -f` 분기 (compute_pattern_id 함수 안) |

---

## Sprint Contract (스프린트별 검증 계약) — 구현 전 필수

### Sprint 1 (v5.20.0)

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 1 | schema v2 필드 4개(tool, duration_ms, confidence, pattern_id)가 record-event.sh extra 가이드에 nullable로 정의됨 | grep | `grep -E "confidence\|pattern_id\|duration_ms" hooks/record-event.sh \| wc -l` ≥ 3 | Critical |
| 1 | pattern_id 함수가 동일 입력 → 동일 8자 hex 출력 | 단위 테스트 | `bash -c "source scripts/lib/pattern-id.sh && [[ $(compute_pattern_id tool_call Bash 2026-04-29T00:00:00) == $(compute_pattern_id tool_call Bash 2026-04-29T00:00:00) ]]"` | Critical |
| 1 | pattern_id 형식 8-hex 검증 | 정규식 | `compute_pattern_id` 출력이 `^[0-9a-f]{8}$` 매치 | Critical |
| 1 | 신뢰도 공식 8 케이스 PASS | 단위 테스트 | `bash tests/test-scripts.sh` 신규 assert ② 8건 모두 PASS | Critical |
| 1 | analyze-observations.sh `--format json` 출력이 유효 JSON | jq parse | `bash scripts/analyze-observations.sh --format json \| jq -e .` exit 0 | Critical |
| 1 | analyze-observations.sh 기본 출력(텍스트 테이블) 회귀 0 | 출력 비교 | `bash scripts/analyze-observations.sh \| diff - tests/fixtures/analyze-baseline.txt` 차이 없음 | Critical |
| 1 | `/nova:evolve --from-observations` 출력에 "자동 승격 금지" 키워드 노출 | grep | `grep -i "자동 승격 금지\|never auto-promote" .claude/commands/evolve.md` ≥ 1 | Critical |
| 1 | `/nova:evolve --accept {dummy_id}` → events.jsonl `evolve_decision` 이벤트 1건 append | tail+jq | `tail -1 .nova/events.jsonl \| jq -r '.event_type'` == `evolve_decision` AND `.extra.decision` == `accept` | Critical |
| 1 | `--accept` 호출 후 NOVA-STATE.md 미갱신 (트리거 제외 검증) | git diff | `git diff NOVA-STATE.md` 빈 출력 (단, NOVA-STATE는 .gitignore이므로 mtime 비교로 대체) | Critical |
| 1 | 491 → 500 tests, 회귀 0 | 테스트 실행 | `bash tests/test-scripts.sh \| grep -E "PASS: 500"` 매치 | Critical |
| 1 | session-start.sh JSON 유효성 + 동기화 | python3 json.tool | `bash hooks/session-start.sh \| python3 -m json.tool >/dev/null` | Critical |
| 1 | `docs/baselines/v5.20.0-baseline.md` 5 섹션 존재 | grep | `grep -c "^## " docs/baselines/v5.20.0-baseline.md` ≥ 5 | Critical |
| 1 | docs/nova-rules.md §10 신뢰도 공식 + clamp 노출 | grep | `grep -E "clamp.*0.*1\|0\.3 \+ 0\.1" docs/nova-rules.md` ≥ 1 | Nice-to-have |
| 1 | context-chain SKILL "evolve_decision JSONL only" 행 추가 | grep | `grep -E "evolve_decision.*JSONL only\|트리거 제외" .claude/skills/context-chain/SKILL.md` ≥ 1 | Nice-to-have |

### Sprint 2 (v5.21.0)

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 2 | PostToolUse Spike 5건 실측 결과 메모리/문서 기록 (stdin 페이로드, duration_ms 단위, MCP vs 일반 도구, exit non-zero, session_start 중복 패턴 적용 여부) | 파일 존재 | `test -f memory/feedback_post_tool_use_*.md \|\| test -f docs/unknowns-resolution.md` | Critical |
| 2 | post-tool-use.sh가 `tool` + `duration_ms` 추출 | 통합 테스트 | `echo '{"tool_name":"Bash","duration_ms":1234}' \| bash hooks/post-tool-use.sh && tail -1 .nova/events.jsonl \| jq -r '.extra.tool'` == `Bash` | Critical |
| 2 | hooks.json PostToolUse 등록 | jq | `jq -r '.hooks.PostToolUse' hooks/hooks.json` 존재 | Critical |
| 2 | 도구별 평균/p95 duration 출력 | jq | `bash scripts/analyze-observations.sh --tool-stats --format json \| jq -e '.tools.Bash.p95'` | Critical |
| 2 | session_end 이후 이벤트 sequence 분석에서 제외 | 통합 테스트 | session_end + 후속 tool_call fixture에서 sequence 출력 확인 | Critical |
| 2 | v5.20.0 baseline 비교 출력 가능 | flag 옵션 | `bash scripts/analyze-observations.sh --compare docs/baselines/v5.20.0-baseline.md` exit 0 | Nice-to-have |
| 2 | PostToolUse 훅 non-zero exit 시 도구 차단 X 검증 | 통합 테스트 | post-tool-use.sh에 `exit 1` 강제 후 다음 도구 호출 정상 (실측 1건) | Critical |

---

## 관통 검증 조건 (End-to-End)

> "기록됨" ≠ "사용자가 활용 가능". 데이터가 입력부터 사용자 결정까지 관통하는지 검증.

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | 사용자가 `/nova:evolve --from-observations` 호출 | 신뢰도 ≥0.7 패턴이 표시됨 + "자동 승격 금지" 메시지 출력 | Critical |
| 2 | 사용자가 출력에서 pattern_id 복사 → `/nova:evolve --accept {pattern_id}` 호출 | events.jsonl에 `evolve_decision` 이벤트 1건 append + "✅ accept 기록" 메시지 | Critical |
| 3 | 다시 `/nova:evolve --from-observations` 재호출 | 같은 pattern_id 의 신뢰도가 +0.2 반영되어 표시됨 | Critical |
| 4 | (v5.21.0) Claude Code 도구 호출 발생 | events.jsonl에 `tool_call` 이벤트의 `extra.tool` + `extra.duration_ms` 채워짐 | Critical |
| 5 | (v5.21.0) `analyze-observations.sh --tool-stats` 호출 | 도구별 평균/p95 출력. v5.20.0 baseline과 비교 가능 | Critical |
| 6 | P0-2 비용 가이드 적용 후 (v5.20.0+ 흡수) | baseline 대비 model=sonnet 호출 비율 변화 측정 가능 | Nice-to-have (v5.22.0+) |

---

## 평가 기준 (Evaluation Criteria)

- **기능**: Sprint Contract 모든 Critical 항목 PASS
- **설계 품질**: schema v1↔v2 호환 + BSD/GNU 양호환 + safe-default 보존
- **단순성**: 신규 파일 최소화 (Sprint 1: 신규 4파일 = pattern-id.sh / snapshot-baseline.sh / analyze-baseline.txt fixture / baselines 디렉토리), 기존 파일 수정 최소화

---

## 역방향 검증 체크리스트

- [x] Plan 결정 #1 (pattern_id) → Design "데이터 계약" + compute_pattern_id 함수에 반영
- [x] Plan 결정 #2 (--accept/--reject 옵션) → Design evolve.md 인라인 트리거 + Sprint Contract Critical 1건
- [x] Plan 결정 #3 (evolve_decision JSONL only) → Design 데이터 계약 + Sprint Contract "NOVA-STATE 미갱신 검증"
- [x] Plan 결정 #4 (clamp 공식) → Design compute_confidence + 8 케이스 단위 테스트
- [x] Plan Risk Map 10건 → Design 에러 처리 표 + Sprint 2 (PostToolUse 위험은 v5.21.0 격리)
- [x] Plan Unknowns [U1][U2][U5] → Sprint 2 Spike 게이트(S2-0) + v5.21.0 경고 로그
- [x] Plan Verification Hooks 16건 (v5.20.0:11 + v5.21.0:5) → Sprint Contract 표 14건 (Critical 12 + Nice 2) + 관통 검증 6건
- [x] 누락된 엣지 케이스: BSD vs GNU date/sha — 명시 처리 (compute_pattern_id 분기)
- [x] 누락된 엣지 케이스: jq `// null` fallback BSD/GNU 동작 차이 — Sprint Contract 검증 명령 #6 (analyze 기본 출력 회귀)
- [ ] (v5.22.0+ 후속) ECC 흡수 baseline 비교 자동화 — 본 Design 범위 외

---

## 다음 단계

1. **본 Design에 대한 사용자 승인** — Sprint Contract Critical 12건 + 관통 검증 6건이 합리적인지 확인
2. Plan 헤더에 `> Design: designs/measurement-infrastructure.md` 추가
3. Sprint 1 구현 진입 — 8파일 (S1-0 baseline + S1-1 record-event.sh + S1-2 analyze-observations.sh + S1-3 evolve.md + S1-4 evolve.md 인라인 트리거 + S1-5 tests + S1-6 nova-rules.md + S1-7 context-chain SKILL + 신규 scripts/lib/pattern-id.sh + scripts/snapshot-baseline.sh) — **실제 신규 2 + 수정 7 = 9 파일**
4. release.sh minor (v5.20.0)
5. PostToolUse Spike → Sprint 2 → release.sh minor (v5.21.0)
