# [Design] Measurement Closed-Loop — 로컬 publish + Actions 검증 보조 모델

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> Plan: plans/measurement-closed-loop.md
> Verification: TBD (Gap 검증 후 경로 추가)

---

## Context (설계 배경)

### Plan 요약
- **핵심 문제**: events.jsonl 측정 인프라가 단방향 파이프 — 데이터 누적은 있으나 활용 채널 0. ECC 흡수 효과 입증 불가.
- **선택한 방안**: 방안 C (YAGNI 우선) — Phase 0(spec) + Phase 1(badge + baselines) 즉시 진행. Phase 2(nova-metrics repo + Astro)는 KPI 분모 ≥ 10 도달 시 진입.
- **자동화 모델**: GitHub Actions 직접 측정 X. 사용자 로컬 `publish-metrics.sh` + Actions는 baselines JSON 검증 보조만 (Critic Critical #1 해소).

### 설계 원칙

1. **Privacy by structure**: `.nova/events.jsonl`은 `.gitignore` 영구 유지. 집계만 commit. 식별 필드(cwd_hash/session_id) 파이프라인 단계에서 강제 strip.
2. **Silent failure 차단**: 모든 단계에 명시 종료 코드 + stderr 메시지. cron 의존 제거 → "데이터 없음 = 사용자 무인지" 시나리오 원천 차단.
3. **Fail-closed at validation, fail-open at observability**: 검증 단계는 strict (fail-closed). 관찰성 hook(record-event.sh)은 safe-default exit 0 유지.
4. **Single source of truth**: `nova-metrics.sh --json` 출력이 KPI 계약. publish-metrics.sh, metrics-validation.yml, README badge 모두 이 출력 형식에 종속.
5. **Fixture-driven CI**: `.nova/events.jsonl`은 GitHub Actions에 없으므로 모든 CI 검증은 `tests/fixtures/events-sample.jsonl` 기반 unit test로 분리.

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | `nova-metrics.sh --json` 모드 + n 임계 분기 + badge_url 생성 | 중간 | _metrics-helpers.py |
| 2 | `publish-metrics.sh` 단일 책임 — 측정/strip/delta/badge 갱신/git rebase 시퀀스 | 중간 | 과제 1 |
| 3 | `tests/fixtures/events-sample.jsonl` v1+v2 혼재 fixture 설계 | 낮음 | 없음 |
| 4 | `metrics-validation.yml` schema + 금지 필드 차단 + PR 코멘트 | 중간 | 과제 2 (fixture는 PR에 들어감) |
| 5 | README badge AUTO-GEN 마커 + 4 KPI 영역 동적 갱신 | 낮음 | 과제 1 |
| 6 | `session-start.sh` 4주 미실행 리마인더 (lean ≤1줄) | 낮음 | 과제 2 (baselines mtime 의존) |
| 7 | `release.sh` Step 2.5에 `.nova/` 실수 commit 차단 가드 | 낮음 | 없음 |
| 8 | `evolve_decision` 이벤트 emit 지점 추가 + KPI 3 재정의 | 중간 | record-event.sh + Sprint 1 spec |
| 9 | `session_id` 재사용 사전 조사 (Sprint 1 시작 전 필수) | 낮음 | 코드 분석만 |
| 10 | `docs/measurement-spec.md` 8 결정 사항 + Phase 2 인프라 설계 | 중간 | 없음 |

### 기존 시스템과의 접점

**영향받는 컴포넌트**:
- `scripts/nova-metrics.sh` (보강 — `--json` 플래그 추가, 텍스트 모드 무변경)
- `scripts/_metrics-helpers.py` (가능 시 보강 — JSON helper)
- `hooks/record-event.sh` (KPI 3 재정의 시 evolve_decision emit 호출 추가)
- `hooks/session-start.sh` (4주 리마인더 lean 1줄)
- `scripts/release.sh` (Step 2.5 `.nova/` 차단 가드)
- `tests/test-scripts.sh` (회귀 가드 ~10 신규 assert)
- `README.md` + `README.ko.md` (AUTO-GEN 마커 + badge 영역)

**호환성 고려**:
- nova-metrics.sh 텍스트 출력 (--json 미지정) **무변경 보장** (회귀 0)
- events.jsonl schema v1↔v2 혼재 처리 (publish-metrics.sh가 `select(.schema_version==2)` 필터 또는 v1→v2 매핑)
- release.sh Step 2.5 fail-open 정책 (4종 위생 게이트 → 5종으로 확장)

---

## Solution (설계 상세)

### 아키텍처 — 데이터 흐름

```
┌─────────────────────────────────────────────────────────────┐
│  로컬 (사용자 환경)                                          │
│                                                              │
│  Claude Code 세션                                            │
│     ↓ PreToolUse hook                                        │
│  hooks/record-event.sh                                       │
│     ↓ append (flock)                                         │
│  .nova/events.jsonl  ← .gitignore (절대 commit X)            │
│     ↑                                                        │
│     │ 주간 리츄얼 (사용자 명시 실행)                         │
│  bash scripts/publish-metrics.sh                             │
│     ↓ 1. nova-metrics.sh --json (KPI 4종 산출)               │
│     ↓ 2. privacy strip (cwd_hash/session_id 제거)            │
│     ↓ 3. delta 계산 (이전 baselines 존재 시)                 │
│     ↓ 4. docs/baselines/{YYYY-WNN}.json 작성                 │
│     ↓ 5. README.md badge 영역 갱신 (AUTO-GEN 마커)           │
│     ↓ 6. git pull --rebase                                   │
│     ↓ 7. git diff 출력 + 사용자 commit 안내                  │
│  사용자: git add + git commit + git push                     │
└──────────────┬──────────────────────────────────────────────┘
               │
               ↓ push
┌─────────────────────────────────────────────────────────────┐
│  GitHub (TeamSPWK/nova repo)                                │
│                                                              │
│  on: pull_request paths: docs/baselines/**.json              │
│  on: push branches: main paths: docs/baselines/**.json       │
│     ↓                                                        │
│  .github/workflows/metrics-validation.yml                    │
│     ↓ 1. JSON schema validation (jq)                         │
│     ↓ 2. 금지 필드 차단 (cwd_hash/session_id/raw events)     │
│     ↓ 3. README badge 영역 정합성 (마커/URL 형식)            │
│     ↓ 4. 위배 시 PR 코멘트 또는 Issue 생성                   │
│     ↓ 5. PASS 시 main에 머지                                 │
│                                                              │
│  README.md badge ← 외부 방문자가 GitHub repo 메인에서 봄    │
└─────────────────────────────────────────────────────────────┘

  Phase 2 (deferred — KPI 분모 ≥ 10 도달 시):
    docs/baselines/*.json → jay-swk/nova-metrics repo가 fetch →
    Astro + Observable Plot 빌드 → GitHub Pages 시계열 그래프
```

### 데이터 모델

#### events.jsonl schema v2 (입력 — 기존 v5.20.0 정착)

```jsonc
{
  "schema_version": 2,
  "timestamp": "2026-04-29T13:56:11.234Z",  // ISO 8601 with ms
  "timestamp_epoch": 1777438571,
  "monotonic_ns": 108153420632500,
  "session_id": "578ef3df4454",  // 12자 hex
  "event_type": "tool_call",  // tool_call|session_start|session_end|commit_blocked|evaluator_verdict|jury_verdict|plan_created|evolve_decision|sprint_completed|gap_detected
  "nova_version": "5.23.1",
  "redacted": false,
  "redaction_reasons": [],  // ["anthropic_api","openai_api","github_pat",...] 14 패턴
  "cwd_hash": "4080913c",  // 8자 hex (집계 단계에서 strip)
  "extra": {
    "tool": "Bash",  // event_type별 가변
    "duration_ms": 152,  // PostToolUse hook (현재 미사용)
    "pattern_id": "a3f2e1c8"  // SHA-256 앞 8자, evolve_decision일 때만
  }
}
```

#### baselines JSON schema (출력 — 신규, 공개 commit)

```jsonc
{
  "schema_version": 1,  // baselines schema 자체 버전 (events.jsonl과 별개)
  "period": "2026-W18",  // YYYY-WNN
  "period_start": "2026-04-27",  // ISO date
  "period_end": "2026-05-03",
  "nova_version": "5.23.1",
  "events_schema_version": 2,  // 집계 시점의 events.jsonl 우세 schema
  "kpis": [
    {
      "kpi": "process_consistency",
      "label": "Process Consistency",
      "pct": null,  // 또는 0~100 정수 (n<임계 시 null)
      "n": 0,
      "n_threshold": 10,
      "status": "insufficient",  // sufficient|insufficient
      "delta_pct": null,  // 이전 주 대비 변화율 (n<2 또는 첫 주는 null)
      "badge_url": "https://img.shields.io/badge/process_consistency-n%3D0%20insufficient-lightgrey"
    },
    { "kpi": "gap_detection_rate", ... },
    { "kpi": "rule_evolution_rate", ... },
    { "kpi": "multi_perspective", ... }
  ]
}
```

#### 데이터 계약 (Data Contract)

| 필드 | 타입 | 단위/포맷 | 변환 규칙 | 비고 |
|------|------|-----------|-----------|------|
| `kpis[].pct` | number\|null | 백분율 정수 (0~100) | 분자/분모 × 100, 정수 절사. n<n_threshold 시 `null` | "78"이지 "78.0"·"0.78" 아님 |
| `kpis[].n` | integer | 분모 이벤트 개수 | 음수 불가, 0 가능 | `n=0`이면 `pct=null` 강제 |
| `kpis[].n_threshold` | integer | KPI별 임계값 | spec 정의 (process/gap=10, multi=5) | 변경 시 spec.md 동기화 |
| `kpis[].status` | enum | `"sufficient"\|"insufficient"` | n≥n_threshold면 sufficient | UI gray-out 결정 키 |
| `kpis[].delta_pct` | number\|null | 변화율 (전주 대비) %p | (현재 pct - 이전 pct). 첫 주 또는 n<2 시 null | %p이지 % 아님 |
| `kpis[].badge_url` | string | shields.io URL | n<임계 시 `lightgrey`, 이상 시 `green` | URL encode 강제 (% → %25 등) |
| `period` | string | `YYYY-WNN` (ISO 8601 week) | `date -u +%G-W%V` (Linux/macOS 둘 다 동작) | timezone UTC 고정 |
| `period_start` / `period_end` | string | `YYYY-MM-DD` (UTC) | 월요일 = period_start | 일요일 = period_end |
| `events_schema_version` | integer | events.jsonl 우세 schema | 같은 주 v1+v2 혼재 시 더 많은 쪽 | drift 감지 시 spec.md 따라 결정 |
| `cwd_hash` / `session_id` | — | **금지 필드** | publish-metrics.sh 단계에서 strip 강제 | metrics-validation.yml이 자동 차단 |

### 핵심 로직

#### 알고리즘 1 — `nova-metrics.sh --json` 출력

```bash
# 입력: --since (기본 30d) | --fixture <path> | --json
# 출력: stdout JSON 배열 (4 KPI)

main() {
  parse_flags
  EVENTS_FILE="${FIXTURE:-.nova/events.jsonl}"

  # schema v2 필터 (v1은 schema_version 필드 없거나 1)
  if [[ "$JSON_MODE" == "1" ]]; then
    KPIS_JSON=$(compute_kpis_json "$EVENTS_FILE" "$SINCE")
    echo "$KPIS_JSON"
  else
    # 기존 텍스트 출력 경로 — 무변경
    print_text_kpis
  fi
}

compute_kpis_json() {
  # 4 KPI 각각 산출 → JSON 배열로 조립
  for kpi in process_consistency gap_detection_rate rule_evolution_rate multi_perspective; do
    n=$(count_denominator "$kpi")
    threshold=$(get_threshold "$kpi")  # 10 / 10 / 10 / 5

    if (( n < threshold )); then
      pct=null
      status=insufficient
      badge_color=lightgrey
      badge_text="n%3D${n}%20insufficient"
    else
      num=$(count_numerator "$kpi")
      pct=$((num * 100 / n))
      status=sufficient
      badge_color=$(pick_color "$pct")  # 80+ green / 60+ yellow / red
      badge_text="${pct}%25"
    fi

    badge_url="https://img.shields.io/badge/${kpi}-${badge_text}-${badge_color}"

    # JSON 객체 1건 emit (jq -cn으로 안전 조립)
  done | jq -s '.'  # 배열로 합치기
}
```

#### 알고리즘 2 — `publish-metrics.sh` 시퀀스

```bash
# 사용자 로컬 주간 리츄얼. 사용자 명시 실행 (cron 없음).
main() {
  # 0. 사전 검증
  ensure_jq_installed
  ensure_in_nova_repo  # NOVA-STATE.md 또는 .claude-plugin/plugin.json 존재 확인
  ensure_clean_or_warn  # uncommitted 있으면 stderr 경고

  # 1. KPI 산출
  KPIS_JSON=$(bash scripts/nova-metrics.sh --json) || die "nova-metrics.sh failed"

  # 2. Privacy 검증 (이중 가드 — nova-metrics.sh가 이미 strip하나 재확인)
  if echo "$KPIS_JSON" | jq -e 'any(.[]; has("cwd_hash") or has("session_id"))' >/dev/null; then
    die "FATAL: 금지 필드 노출 — abort"
  fi

  # 3. period 산출 (UTC)
  PERIOD=$(date -u +%G-W%V)
  PERIOD_START=$(date -u -d "$PERIOD-1" +%Y-%m-%d 2>/dev/null || gdate -u -d "$PERIOD-1" +%Y-%m-%d)
  PERIOD_END=$(date -u -d "$PERIOD-7" +%Y-%m-%d 2>/dev/null || gdate -u -d "$PERIOD-7" +%Y-%m-%d)

  # 4. delta 계산 (이전 주 baselines 존재 시)
  PREV_FILE=$(ls -1 docs/baselines/*.json 2>/dev/null | sort | tail -1)
  if [[ -n "$PREV_FILE" ]]; then
    KPIS_JSON=$(merge_delta "$KPIS_JSON" "$PREV_FILE")
  fi

  # 5. baselines JSON 조립 + 저장
  OUT_FILE="docs/baselines/${PERIOD}.json"
  jq -n \
    --arg period "$PERIOD" \
    --arg ps "$PERIOD_START" \
    --arg pe "$PERIOD_END" \
    --argjson kpis "$KPIS_JSON" \
    --arg nv "$(cat scripts/.nova-version)" \
    '{schema_version:1, period:$period, period_start:$ps, period_end:$pe,
      nova_version:$nv, events_schema_version:2, kpis:$kpis}' \
    > "$OUT_FILE"

  # 6. README badge 영역 갱신 (AUTO-GEN 마커 기반)
  update_readme_badges "$OUT_FILE" README.md
  update_readme_badges "$OUT_FILE" README.ko.md

  # 7. git pull --rebase (충돌 시 fail-closed)
  git pull --rebase || die "rebase failed — 사용자 수동 해결 필요"

  # 8. git diff 출력 + commit 안내
  git diff --stat docs/baselines/ README.md README.ko.md
  echo
  echo "다음 명령으로 commit하세요:"
  echo "  git add docs/baselines/${PERIOD}.json README.md README.ko.md"
  echo "  git commit -m 'metrics(${PERIOD}): 주간 baselines 갱신'"
}
```

#### 알고리즘 3 — `metrics-validation.yml` 워크플로우

```yaml
name: Metrics Validation
on:
  pull_request:
    paths: ['docs/baselines/**.json', 'README.md', 'README.ko.md']
  push:
    branches: [main]
    paths: ['docs/baselines/**.json']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Schema validation
        run: |
          for f in docs/baselines/*.json; do
            jq -e '. | (.schema_version==1 and .period and .kpis | type=="array" and length==4)' "$f" \
              || { echo "::error file=$f::schema invalid"; exit 1; }
          done

      - name: Forbidden fields check
        run: |
          for f in docs/baselines/*.json; do
            if jq -e 'any(.kpis[]; has("cwd_hash") or has("session_id"))' "$f"; then
              echo "::error file=$f::forbidden field detected"
              exit 1
            fi
          done

      - name: README badge marker integrity
        run: |
          grep -q '<!-- nova-metrics:badges:start -->' README.md || exit 1
          grep -q '<!-- nova-metrics:badges:end -->' README.md || exit 1
          # 동일 README.ko.md

      - name: .nova/ leak check
        run: |
          if git diff --name-only origin/main...HEAD | grep -E '^\.nova/' >/dev/null; then
            echo "::error::.nova/ 파일이 PR에 포함됨 — privacy 사고"
            exit 1
          fi

      - name: Comment on PR if failed
        if: failure() && github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '⚠️ Metrics validation FAIL — 위 단계 로그를 확인하세요.'
            })
```

#### 알고리즘 4 — `session-start.sh` 4주 미실행 리마인더 (lean 1줄)

```bash
# session-start.sh additionalContext 끝부분에 추가
# lean ≤1200자 예산 보호 — 1줄만, 조건 미충족 시 출력 0
LATEST_BASELINE=$(ls -1 docs/baselines/*.json 2>/dev/null | sort | tail -1)
if [[ -n "$LATEST_BASELINE" ]]; then
  AGE_DAYS=$(( ($(date +%s) - $(stat -f%m "$LATEST_BASELINE" 2>/dev/null || stat -c%Y "$LATEST_BASELINE")) / 86400 ))
  if (( AGE_DAYS > 28 )); then
    echo "⚠️ baselines가 ${AGE_DAYS}일 미갱신 — bash scripts/publish-metrics.sh 권장"
  fi
fi
# 첫 주(파일 0건)는 출력 안 함 — 신규 사용자 경로 보호
```

### 에러 처리

| 예상 에러 | 발생 위치 | 대응 |
|----------|----------|------|
| events.jsonl 없음 | nova-metrics.sh | --fixture 명시 권장 stderr + 모든 KPI N/A 출력 + exit 0 (관찰성) |
| events.jsonl 손상 (incomplete JSON) | nova-metrics.sh | 파싱 실패 줄 stderr 카운트 + exit 0. 5% 초과 손상 시 stderr WARN |
| jq 미설치 | publish-metrics.sh | exit 2 + "jq 설치 필요" 메시지 |
| git pull --rebase 충돌 | publish-metrics.sh | exit 2 + "수동 rebase 후 재시도" 메시지 |
| privacy 검증 실패 (cwd_hash 노출) | publish-metrics.sh | exit 3 + "FATAL: 금지 필드" + commit 차단 |
| schema validation FAIL | metrics-validation.yml | exit 1 + GitHub Actions error annotation + PR 코멘트 |
| `.nova/` 파일 PR 포함 | metrics-validation.yml | exit 1 + privacy 사고 경고 + PR 차단 |
| `.nova/` 파일 release.sh 시도 | release.sh Step 2.5 | exit 2 + "절대 commit 금지" 메시지 |
| README badge 마커 부재 | metrics-validation.yml | exit 1 + 마커 형식 안내 |
| baselines 첫 주(파일 0건) | session-start.sh | 리마인더 출력 안 함 (신규 사용자 보호) |

---

## Sprint Contract (스프린트별 검증 계약)

### Sprint 1 — Phase 0 Spec + 사전 조사

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 1 | `docs/measurement-spec.md`이 8 핵심 결정 사항 모두 명시 | grep으로 8 키워드 검출 | `for k in "KPI 4종" "n 임계" "schema_version" "baselines JSON schema" "Phase 2 인프라" "Phase 2 진입 트리거" "Phase 3 future hook" "badge gray-out 책임"; do grep -q "$k" docs/measurement-spec.md \|\| echo "MISSING: $k"; done` (출력 0줄이면 PASS) | Critical |
| 1 | `session_id` 재사용 사전 조사 결과가 spec에 반영 | spec에 "session_id 갱신 정책: {버그 수정\|의도된 재사용}" 섹션 존재 | `grep -A2 'session_id 갱신 정책' docs/measurement-spec.md` 결과 비어있지 않음 | Critical |
| 1 | KPI 3 재정의 결정 (grep 재작성 vs evolve_decision 기반) | spec에 결정 + emit 지점 명시 | `grep -E '^### KPI 3' docs/measurement-spec.md` + `grep 'evolve_decision' hooks/*.sh scripts/*.sh` 매칭 1개 이상 | Critical |
| 1 | Phase 2 인프라 설계 (jay-swk/nova-metrics repo 구조 + Astro 빌드 진입점 + cross-repo 데이터 흐름) | spec에 4 항목 모두 명시 | `grep -c -E '(repo 구조\|Astro\|GitHub Pages\|cross-repo)' docs/measurement-spec.md` ≥ 4 | Critical |
| 1 | tests/test-scripts.sh가 spec 파일 + 핵심 섹션 회귀 가드 | 신규 3~5 assert 추가 | `bash tests/test-scripts.sh` 통과 + 카운트 증가 확인 | Critical |

### Sprint 2 — `nova-metrics.sh --json` + Fixture

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 2 | `nova-metrics.sh --json` 출력이 valid JSON 4 KPI 배열 | 명령 실행 후 jq로 length=4 확인 | `bash scripts/nova-metrics.sh --json --fixture tests/fixtures/events-sample.jsonl \| jq -e '. \| length == 4'` exit 0 | Critical |
| 2 | n<임계 시 `pct: null` + `badge_url` gray | fixture로 n=1 상태 시뮬레이션 | `bash scripts/nova-metrics.sh --json --fixture tests/fixtures/events-low-n.jsonl \| jq -e '.[] \| select(.n < .n_threshold) \| .pct == null and (.badge_url \| contains("lightgrey"))'` exit 0 | Critical |
| 2 | n≥임계 시 `pct` 정수 + `badge_url` 색상 | fixture로 n=15 상태 시뮬레이션 | `bash scripts/nova-metrics.sh --json --fixture tests/fixtures/events-sufficient.jsonl \| jq -e '.[] \| select(.n >= .n_threshold) \| .pct \| type == "number"'` exit 0 | Critical |
| 2 | 텍스트 출력 회귀 0 (--json 미지정 시 기존 동작 유지) | 기존 출력 형식 비교 | `bash scripts/nova-metrics.sh \| grep -E '(Process consistency\|Gap detection\|Rule evolution\|Multi-perspective)'` 4줄 모두 존재 | Critical |
| 2 | tests/fixtures/events-sample.jsonl이 v1+v2 혼재 + 모든 event_type 포함 | jq로 schema 다양성 검증 | `jq -s 'map(.schema_version) \| unique \| sort == [1,2]' tests/fixtures/events-sample.jsonl` true | Critical |
| 2 | tests/test-scripts.sh 회귀 + 신규 6~8 assert | 카운트 증가 + PASS | `bash tests/test-scripts.sh \| tail -1 \| grep PASS` | Critical |
| 2 | _metrics-helpers.py가 schema_version 분기 처리 | unit test 추가 | `python3 -m pytest tests/test_metrics_helpers.py -v` (또는 stdin pipe 테스트로 대체) | Nice-to-have |

### Sprint 3 — `publish-metrics.sh` + Validation Workflow + Badge + 가드

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| 3 | `publish-metrics.sh --dry-run` 후 baselines JSON 후보 생성 | 임시 디렉토리에 dry-run 출력 | `bash scripts/publish-metrics.sh --dry-run \| grep -E 'docs/baselines/[0-9]{4}-W[0-9]{2}\.json'` 1줄 이상 | Critical |
| 3 | publish-metrics.sh가 cwd_hash/session_id strip 검증 | 위배 fixture 의도 주입 후 abort 확인 | (테스트 시나리오) `NOVA_TEST_INJECT_CWD_HASH=1 bash scripts/publish-metrics.sh --dry-run; [ $? -ne 0 ]` | Critical |
| 3 | 첫 회 baselines/{week}.json 실제 생성 + commit | 1회 수동 실행 | `bash scripts/publish-metrics.sh && ls docs/baselines/2026-W18.json` 존재 | Critical |
| 3 | `metrics-validation.yml` 유효성 (actionlint) | actionlint 또는 GitHub UI syntax check | `actionlint .github/workflows/metrics-validation.yml` exit 0 (없으면 GitHub UI 수동 확인) | Critical |
| 3 | metrics-validation.yml이 의도적 위배 PR을 차단 | 위배 fixture로 PR 1회 만들어 fail 확인 | (수동) PR 만들고 Actions 로그 확인 + PR 코멘트 자동 생성 확인 | Critical |
| 3 | README.md + README.ko.md AUTO-GEN 마커 + 4 KPI badge 영역 | publish 후 마커 사이 영역에 4 badge URL | `awk '/<!-- nova-metrics:badges:start -->/,/<!-- nova-metrics:badges:end -->/' README.md \| grep -c 'shields.io'` ≥ 4 | Critical |
| 3 | session-start.sh 4주 미실행 리마인더 (조건부 출력) | mtime 28일+ baselines 파일 시뮬 | (테스트) `touch -t 202603010000 docs/baselines/test.json && bash hooks/session-start.sh \| grep '미갱신'` 1줄 출력 | Critical |
| 3 | release.sh Step 2.5에 `.nova/` 차단 가드 | 의도적 .nova/ staging 후 release 시도 | `git add -f .nova/events.jsonl; bash scripts/release.sh patch "test" 2>&1 \| grep -E '(\.nova/\|FATAL)'; git rm --cached .nova/events.jsonl` 차단 메시지 출력 | Critical |
| 3 | tests/test-scripts.sh 회귀 + 신규 8~10 assert | 카운트 증가 + PASS | `bash tests/test-scripts.sh \| tail -1 \| grep PASS` | Critical |
| 3 | Phase 1.5 delta 계산 자동 활성 (baselines ≥2건 시) | 이전 baselines 존재 상태에서 publish 실행 후 delta_pct 필드 검증 | `jq '.kpis[] \| select(.delta_pct != null) \| .kpi' docs/baselines/2026-W19.json` 1줄 이상 | Nice-to-have |

### 관통 검증 조건 (End-to-End)

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | Claude Code 세션에서 Bash/Read 도구 사용 | `.nova/events.jsonl`에 tool_call 이벤트 1줄 추가 | Critical |
| 2 | `bash scripts/publish-metrics.sh` 1회 실행 | `docs/baselines/{period}.json` 생성 + README.md badge 영역 갱신 + git diff 출력 | Critical |
| 3 | 사용자가 baselines JSON commit + push | GitHub repo 메인 페이지 README에서 4 KPI badge 보임 + n<임계 시 gray | Critical |
| 4 | 의도적으로 `cwd_hash` 포함된 baselines JSON commit 시도 | metrics-validation.yml이 PR 차단 + 코멘트 자동 생성 | Critical |
| 5 | 4주 동안 publish-metrics.sh 미실행 후 Claude Code 세션 시작 | session-start.sh additionalContext에 "baselines XX일 미갱신" 1줄 알림 출력 | Critical |
| 6 | 2주차 publish-metrics.sh 실행 (baselines ≥2건) | baselines JSON에 `delta_pct` 필드 채워짐 + README badge 영역에 변화율 추가 | Nice-to-have |
| 7 | KPI 분모 ≥ 10 도달 (어느 KPI든 1개) | NOVA-STATE 또는 README에 "Phase 2 진입 가능" 표시 (수동 결정 트리거) | Nice-to-have |

### 역방향 검증 체크리스트

- [ ] Plan의 8 P 분해 (P1~P8)가 Design Solution에 모두 반영되었는가?
- [ ] Plan의 12 Risk Map 중 H/M 리스크 완화책이 Sprint Contract에 반영되었는가?
- [ ] Plan의 15 Verification Hooks가 Sprint Contract Done 조건으로 변환되었는가?
- [ ] Plan Phase 0~2 + Phase 3 future hook이 Sprint 1~3 + 명시적 deferred로 매핑되었는가?
- [ ] Critic이 발견한 6 이슈가 Design 단계에서도 보존되는가? (특히 Critical #1 자동화 모델 재설계)
- [ ] 메모리 정합 5종 (evidence_first_identity, nova_spike_skill_deferred, evaluator_hallucination, no_manual_setup, nova_universal_plugin) 위배 없는가?

### 평가 기준

- **기능**: Sprint Contract 28개 Done 조건 (Critical 24 / Nice-to-have 4) 모두 검증 명령으로 PASS/FAIL 자동 판정 가능. 관통 7건 중 5건 자동화 + 2건 수동.
- **설계 품질**:
  - 단일 데이터 소스 (`nova-metrics.sh --json`) 강제 — publish/validation/badge 모두 이 출력에 종속
  - Privacy 가드 4중 (gitignore + nova-metrics.sh strip + publish-metrics.sh 재검증 + metrics-validation.yml 차단 + release.sh Step 2.5)
  - Phase 1→2 전환 비용 0 (baselines JSON schema가 nova-metrics repo Astro 빌드 입력으로 직접 사용)
- **단순성**: cron 의존 제거. 사용자 명시 결정으로 전체 흐름 시작 (publish-metrics.sh 1회 실행). Actions는 검증만 (silent failure 위험 0).

### Phase 2 future hook (deferred 명시)

본 Design은 Phase 0~1 (Sprint 1~3)만 다룬다. Phase 2는 별도 Design (`measurement-visualization.md`) 시점에 다음을 결정:

- jay-swk/nova-metrics repo 부트스트랩 시퀀스
- Astro + Observable Plot 빌드 파이프라인
- cross-repo 데이터 흐름 (raw GitHub URL fetch vs git submodule 결정)
- GitHub Pages 배포 + 도메인 정책
- Phase 1.5 delta가 Phase 2 시계열 그래프에 어떻게 흡수되는지

**Phase 2 진입 트리거**: 본 Design Sprint 3 완료 + 4주 누적 후 KPI 4종 중 2개 이상 분모 ≥ 10 도달 시 사용자 결정.

---

## 메모리 정합 명시

| 메모리 | 정합 |
|--------|------|
| `feedback_evidence_first_identity` | n<임계 시 gray-out 강제. "Self-only metrics" 라벨 noises X. 측정→입증→정체성 사이클이 본 Design 자체 |
| `nova_spike_skill_deferred` | Phase 2를 데이터 임계로 deferred. n>1 시점 진입 원칙 그대로 |
| `feedback_evaluator_hallucination` | 측정값 그대로 신뢰 X — 4중 privacy 가드 + n 명시 + delta는 n≥2부터만 |
| `feedback_no_manual_setup` | publish-metrics.sh는 사용자 명시 1회 실행이지만 그 외 모든 단계 자동 (Actions 검증/badge 갱신/리마인더) |
| `nova_universal_plugin` | nova 본체 변경 최소 (--json 추가만). 외부 사용자 환경 영향 0. fixture 기반 CI로 dogfood 의존 제거 |
| `feedback_session_start_lightweight` | session-start.sh 리마인더 1줄 + 조건부 출력 (≤1200자 lean 예산 보호) |
| `feedback_release_sh_staging_trap` | release.sh Step 2.5에 `.nova/` 차단 가드 추가 — 동일 사고 재발 차단 |
