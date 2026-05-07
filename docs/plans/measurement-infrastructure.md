# [Plan] Measurement Infrastructure (events.jsonl 스키마 v2 + 신뢰도 점수)

> Nova Engineering — CPS Framework
> 작성일: 2026-04-29
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1 (Critic 7건 → Refiner 7건 모두 해소)
> Design: docs/designs/measurement-infrastructure.md

---

## Context (배경)

### 현재 상태

Nova v5.19.5 HEAD, v5.19.6 (state-prune-symmetry) patch 미릴리스. 관찰성 인프라 Sprint 1 완성:

- `hooks/record-event.sh` — append-only JSONL, flock + mkdir fallback, schema_version=1, 14 패턴 + entropy privacy filter, safe-default exit 0
- `hooks/pre-tool-use-record.sh` — PreToolUse stdin JSON 파싱 (메모리: v5.18.0~1 환경변수 가정 오류 학습)
- `scripts/analyze-observations.sh` (307줄) — tool-frequency / sequence / failures 3 패턴 jq 집계, 텍스트 테이블 출력
- `.nova/events.jsonl` — 현재 2051줄 / 586KB, schema v1 11 이벤트 타입
- `.gitignore` `.nova/` 등록, CI=true 시 별도 경로 분기
- `session.id` 파일이 `${EVENTS_DIR}/session.id` (= `.nova/session.id`) — **CWD 기반 → 다중 worktree 시 분리**

2026-04-29 적대적 평가(`docs/proposals/2026-04-29-ecc-adversarial-gap.md`): Nova 진짜 메커니즘 차별 1개(NOVA-STATE) + ECC 흡수 가치 6건. 사용자 결정: **정체성 정의 보류, 측정 인프라 우선** (메모리 `feedback_evidence_first_identity.md`).

### 왜 필요한가

1. ECC 흡수 6건의 효과를 후험적으로 검증할 인프라 부재.
2. 현재 events.jsonl이 모든 패턴을 동등 가중. 신뢰도 점수 없어 노이즈/신호 분리 불가.
3. 하네스 엔지니어링 갭 분석(메모리 2026-04-19) 부분 해소 — 신뢰도 산출 + 도구별 통계 미통합.
4. evolve scan 2026-04-29 P3 (PostToolUse `duration_ms` Claude Code v2.1.119) 자연 결합 가능하나 미실측 → "공식 문서 ≠ 실제 런타임" 메모리 리스크.

### 관련 자료

- `hooks/record-event.sh:1-250` — append-only JSONL + rotation + privacy filter
- `scripts/analyze-observations.sh:1-307` — 3 패턴 jq 집계
- `hooks/pre-tool-use-record.sh:1-34` — PreToolUse stdin JSON 파싱
- `.claude/commands/evolve.md:20` — `--from-observations` 옵션 문서화 (구현 공백)
- `docs/designs/harness-engineering-gap-coverage.md:100-200` — 스키마 v1 정의
- `tests/test-scripts.sh:62-250` — 회귀 가드 assert 패턴
- `docs/nova-rules.md §0, §10` — 관찰성 계약
- `.claude/skills/context-chain/SKILL.md:17-27, 62` — NOVA-STATE × JSONL 역할 분담 + 트림 트리거 룰
- `hooks/hooks.json:44-74` — PreToolUse 훅 등록 구조
- `docs/proposals/2026-04-29-ecc-adversarial-gap.md` — P1-3 항목
- `docs/proposals/2026-04-29-evolve-scan.md` — P3 PostToolUse duration_ms

---

## Problem (문제 정의)

### 핵심 문제

Nova `.nova/events.jsonl` 기록은 풍부하나 **신뢰도 차별 + 도구 시간 통계 + 자동 승격 가드 + 사용자 채택/거부 명시 트리거** 가 없어 ECC 흡수 작업의 효과를 후험적으로 측정할 수 없다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **스키마 빈약** | schema v1에 `tool`, `duration_ms`, `confidence`, `pattern_id` 필드 없음. 기존 2051줄 v1 호환 처리 미정의 | High |
| 2 | **신뢰도 산출 부재** | `/nova:evolve --from-observations`가 모든 패턴 동등 가중. 노이즈 vs 신호 분리 불가 | High |
| 3 | **도구별 통계 부재** | analyze-observations.sh가 평균/p95 duration 미산출 | Medium |
| 4 | **자동 승격 가드 미명문화** | 신뢰도 0.9 패턴이 자동 skill 승격 위험 | High |
| 5 | **PostToolUse 미실측** | duration_ms 필드 위치/단위/exit 코드 동작 미검증 | High (Spike 차단) |
| 6 | **채택/거부 입력 인터페이스 부재** | 신뢰도 공식의 "+0.2 / -0.3" 트리거 경로 미정 | High |
| 7 | **회귀 가드 카테고리 부재** | 신뢰도 공식 단위 테스트, 스키마 v1/v2 분기 처리 단위 테스트 없음 | Medium |
| 8 | **다중 worktree 신뢰도 집계 왜곡** | session.id가 CWD 기반 → worktree A의 5세션이 worktree B JSONL에서는 0세션. v5.20.0 scope-out, v5.21.0+ 검토 | Medium (scope-out) |
| 9 | **ECC 흡수 baseline 미정의** | v5.20.0 배포 이전/이후 비교 기준점 없음. 2051줄 v1 record에 마커 부재 | High |

### 제약 조건

(code-explorer 현재 제약 + risk-explorer 구조적 리스크 + Critic 이슈 #1, #3 반영)

1. **schema v1 ↔ v2 호환** — 기존 2051줄 record를 무효화하지 않아야 함. v1 record의 신규 필드 부재는 `null` 처리 + jq `// null` fallback.
2. **safe-default exit 0** — 모든 훅·스크립트는 실패 시 stderr WARN + exit 0. PostToolUse 훅이 non-zero 반환 시 도구 차단 가능성 있어 `2>/dev/null || true` 래핑 필수.
3. **flock + mkdir fallback** — 동시 쓰기 잠금 패턴 유지. 신규 필드 추가가 lock 경합 증가시키면 안 됨.
4. **수동 설정 금지 원칙** — 사용자가 `.nova/config.yml` 등을 직접 편집하게 만들면 안 됨 (메모리 `feedback_no_manual_setup.md`).
5. **session-start.sh 동기화 필수** — CLAUDE.md/nova-rules.md 변경 시 session-start.sh 동시 수정.
6. **NOVA-STATE 9 진입점 동기화 룰 유지** — 신규 산출물이 9 진입점을 늘리지 않아야 함. **`evolve_decision` 이벤트는 NOVA-STATE 갱신 트리거에서 제외** (Critic 이슈 #3 반영). JSONL에만 기록.
7. **공식 문서 ≠ 실제 런타임** — PostToolUse `duration_ms` 실측 전 도입 금지. v5.18.3 `if` 필드 사건 학습.
8. **자동 승격 금지** — 신뢰도 0.9여도 사용자 승인 필수 (메모리 `feedback_evidence_first_identity.md`).
9. **다중 worktree 분산 JSONL — v5.20.0 scope-out** — session.id CWD 기반 분리 가정. v5.20.0 신뢰도 집계는 **단일 worktree 기준**. v5.21.0+에서 worktree 통합/마커 도입 별도 검토. (Critic 이슈 #1 반영)
10. **CLAUDE.md 커맨드 추가 체크리스트 회피** — S1-4는 신규 커맨드가 아닌 **기존 `evolve.md`에 `--accept` / `--reject` 플래그 추가**로 결정. EXPECTED_COMMANDS 배열 / session-start.sh 커맨드 목록 변경 X. (Critic 이슈 #2 반영)

---

## Solution (해결 방안)

### 선택한 방안

**방안 A**: JSONL 단일 파일 유지 + **분석 시점 confidence 산출** + PostToolUse Spike v5.21.0 분리.

**선택 근거** (option-explorer 권장 + 메모리 원칙 부합):

1. **"공식 문서 ≠ 실제 런타임" 원칙 부합.** PostToolUse 미검증을 v5.20.0 블로커에서 제외. v5.21.0 Spike 분기로 격리.
2. **소급 산출 가능.** 기존 2051줄 v1 record로 즉시 신뢰도 산출 시작.
3. **flock/safe-default/14 regex 자산 보존.** Sprint 1 인프라 유지.
4. **2 스프린트 자연 분리.**
5. **수동 설정 금지 원칙 부합** — 방안 C(config.yml 옵트인) 거부.

### 대안 비교

| 방안 | 접근 (분기 1+2+3) | 장점 | 단점 | 권장도 |
|------|-------------------|------|------|--------|
| A | **1a + 2b + 3b**: JSONL 단일 + 분석 시점 confidence + PostToolUse v5.21.0 분리 | 기존 record-event.sh 변경 최소화. 과거 이벤트 소급 적용. PostToolUse 리스크 격리. safe-default 보존 | tool/duration_ms는 v5.21.0까지 부재. 초기 신뢰도가 evaluator_verdict/session_start 위주 | ⭐ |
| B | **1a + 2a + 3a**: JSONL 단일 + 기록 시점 confidence + PostToolUse 즉시 도입 | 단일 스프린트 완성. tool/duration_ms 즉시 확보 | PostToolUse 미실측 도입 = v5.18.3 사고 재현. 기록 시점 산출이 매 훅마다 events.jsonl 재집계 → lock 경합 | |
| C | **1c + 2c + 3c**: SQLite + patterns.yml 인덱스 + config.yml 옵트인 | SQL 정확/빠름. ECC instinct 매핑 | sqlite3 의존. 수동 설정 금지 정면 충돌. flock/JSONL 자산 폐기. 비용 최대 | |

### 구현 범위 (Plan 단계 결정 사항 명문화)

#### Plan 단계 4대 결정

(Critic 이슈 #2, #3, #4, #6 반영 — Design 이관 X, Plan에서 확정)

1. **`pattern_id` 최소 스펙** (Critic 이슈 #4):
   - 형식: `{event_type}:{tool_name|"-"}:{week_iso}` 의 SHA-256 hex 앞 8자
   - 예: `tool_call:Bash:2026-W18` → SHA-256 앞 8자 = `a3f2e1c8`
   - 안정성: event_type + tool_name 안정. week_iso는 주 단위 시간 슬롯 — 패턴 신뢰도가 주 경계에서 새로 누적 시작 (의도된 시간 감쇠).
   - 충돌 처리: SHA-256 앞 8자 충돌은 무시 (collision rate ~1e-9). Design에서 정밀화 가능.

2. **S1-4 산출 형태**: **기존 `.claude/commands/evolve.md` 에 옵션 추가** (신규 커맨드 X) → CLAUDE.md 커맨드 추가 체크리스트 회피.
   - `/nova:evolve --accept {pattern_id}` — events.jsonl에 `evolve_decision` 이벤트 1건 append (extra: pattern_id, decision="accept", ts). NOVA-STATE 갱신 트리거 X.
   - `/nova:evolve --reject {pattern_id}` — 동일 패턴, decision="reject".
   - 호출 흐름: `/nova:evolve --from-observations` 출력 표 보고 → 사용자가 pattern_id 복사 → `/nova:evolve --accept {pattern_id}`. AI는 `evolve_decision` 이벤트 자가 기록 절대 금지.

3. **`evolve_decision` 이벤트 NOVA-STATE 트리거 제외** (Critic 이슈 #3): JSONL에만 기록. NOVA-STATE 9 진입점 유지. Risk Map에 트림 루프 항목 명시 + 완화 적용.

4. **신뢰도 공식 clamp 명문화** (Critic 이슈 #7):
   - `confidence = clamp(0, 1, 0.3 + 0.1 * N_unique_sessions + 0.2 * N_accept - 0.3 * N_reject)`
   - `N_unique_sessions` = 같은 pattern_id를 발생시킨 **고유 session_id 수** (game화 방지)
   - 클램프: 최소 0.0, 최대 1.0
   - 단위 테스트: 8 케이스 (N=0/N=6/+1 accept/+2 accept/-1 reject/-2 reject/clamp 1.0/clamp 0.0)

#### Sprint 1 — v5.20.0 (스키마 v2 + 신뢰도 + 회귀 가드)

수정 파일 8개 — 단일 스프린트:

- [ ] **S1-0. baseline 스냅샷** (Critic 이슈 #6): v5.20.0 빌드 직전 1회. `docs/baselines/v5.20.0-baseline.md` 작성:
  - `wc -l .nova/events.jsonl` 결과
  - `bash scripts/analyze-observations.sh` 출력 전체 (tool-frequency/sequence/failures Top 10)
  - 현재 evaluator FAIL률 (events.jsonl `evaluator_verdict` 이벤트 집계)
  - tools 별 호출 빈도 Top 10
  - schema_version=1 record 수
  - **목적**: ECC 흡수(P0-2/P0-3/P1-1) 이후 비교 기준선.
- [ ] **S1-1.** `hooks/record-event.sh` — `schema_version: 2` 범프 + `extra` payload 안에 `tool`, `duration_ms`, `confidence`, `pattern_id` nullable 필드 가이드(주석 + 예시 호출). 기존 호출부(session-start.sh 등) 변경 X. 호환성 테스트 1건.
- [ ] **S1-2.** `scripts/analyze-observations.sh` — `--format json` 플래그 추가. 핵심 함수:
  - `compute_pattern_id()` — Plan 결정 #1 형식 SHA-256 앞 8자
  - `compute_confidence()` — Plan 결정 #4 clamp 공식
  - `pattern_id`별 N_unique_sessions / N_accept / N_reject 집계 (jq)
  - ≥0.7 필터 (--threshold 옵션 기본값 0.7)
  - schema v1/v2 분기 처리 (jq `// null` fallback)
- [ ] **S1-3.** `.claude/commands/evolve.md` — `--from-observations` 모드에 신뢰도 컬럼 추가 (0.7~0.9 황색, ≥0.9 적색), **자동 승격 금지 명문화** (한 줄 + 거부 메시지). `--accept` / `--reject` 옵션 절 신규.
- [ ] **S1-4.** `commands/evolve.md` 의 `--accept` / `--reject` 트리거 구현 — events.jsonl `evolve_decision` 이벤트 append. NOVA-STATE 갱신 X (Plan 결정 #3).
- [ ] **S1-5.** `tests/test-scripts.sh` — 회귀 가드 +9 assert (이전 +6 → +9):
  - ① schema v2 필드 nullable
  - ② 신뢰도 공식 단위 테스트 8 케이스 (Plan 결정 #4 clamp 포함)
  - ③ ≥0.7 필터
  - ④ v1 record null 방어
  - ⑤ analyze --format json 스키마
  - ⑥ "자동 승격 금지" 키워드 evolve.md 노출
  - ⑦ pattern_id SHA-256 앞 8자 형식 검증
  - ⑧ `/nova:evolve --accept {dummy_id}` 시 evolve_decision 이벤트 기록 + NOVA-STATE 미갱신 검증
  - ⑨ baseline 스냅샷 파일 존재 (`docs/baselines/v5.20.0-baseline.md`)
- [ ] **S1-6.** `docs/nova-rules.md` §10 관찰성 계약 — 신뢰도 산출 공식 + 자동 승격 금지 + Plan 결정 #3 (evolve_decision NOVA-STATE 트리거 제외) 1줄.
- [ ] **S1-7.** `.claude/skills/context-chain/SKILL.md` — NOVA-STATE × JSONL 역할 분담 표에 "evolve_decision = JSONL only, NOVA-STATE 트리거 제외" 1행 추가 (9 진입점 **유지**).

스프린트 종료 시: `bash tests/test-scripts.sh` 회귀 0 + `/nova:review --fast` PASS + Evaluator PASS → release.sh minor (v5.20.0).

#### Sprint 2 — v5.21.0 (PostToolUse Spike + 훅 도입)

선행 조건: v5.20.0 릴리스 완료.

수정 파일 5개:

- [ ] **S2-0. (Spike, 차단 게이트)** 더미 `hooks/post-tool-use.sh` 등록 → 실제 stdin JSON 페이로드 파일 dump 1회 → `duration_ms` 필드 위치/단위/MCP vs 일반 도구 차이/non-zero exit 동작 4건 + session_start 중복 버스트가 PostToolUse에 적용되는지 1건 (총 5건) 실측. 결과를 `feedback_*` 메모리에 기록. 실측 실패 또는 unknown 1건이라도 발견 시 v5.21.0 블로커.
- [ ] **S2-1.** `hooks/post-tool-use.sh` 신규 — Spike 결과 기반 `duration_ms` + `tool` 추출, `record-event.sh` 비동기 호출(`&`), 모든 에러 `exit 0`.
- [ ] **S2-2.** `hooks/hooks.json` 또는 `.claude-plugin/plugin.json` — PostToolUse 등록.
- [ ] **S2-3.** `scripts/analyze-observations.sh` — 도구별 평균/p95 duration 통계 섹션 추가 (json + 텍스트 양쪽). v5.20.0 baseline과 비교 출력.
- [ ] **S2-4.** `tests/test-scripts.sh` — Spike 결과 회귀 가드 (PostToolUse 등록, duration_ms 추출 단위 테스트, session_end 순서 sentinel 처리).

스프린트 종료 시: 동일 게이트 → release.sh minor (v5.21.0).

### 검증 기준

(Verification Hooks의 v5.20.0 핵심 발췌)

- v5.20.0: schema v2 + 신뢰도 산출 (clamp + N_unique_sessions) + pattern_id SHA-256 + `--accept`/`--reject` + 회귀 +9 assert + baseline 스냅샷.
- v5.21.0: PostToolUse Spike PASS + duration_ms 기록 검증 + 도구별 p95 + baseline 비교.
- 두 스프린트 모두 491 → 500+ tests, 회귀 0, NOVA-STATE 50줄 이내, **9 진입점 유지**.

---

## Sprints (스프린트 분할)

위 "구현 범위" 섹션의 Sprint 1 (v5.20.0, 8파일) + Sprint 2 (v5.21.0, 5파일) 참조. 두 스프린트는 독립 릴리스로 분리 — Sprint 2 진입은 Sprint 1 PASS + PostToolUse Spike 게이트 통과 후. **Verification Hooks 테이블도 스프린트별 분리** (Critic 이슈 #5).

---

## Risk Map

(risk-explorer 8건 + Critic 추가 2건 → 총 10건)

| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| **신뢰도 공식 게임화** — 반복 Bash 호출만으로 N=6→0.9 도달 | H | M | **N = 고유 session_id 수**로 집계 (Plan 결정 #4). 같은 세션 내 반복은 max(1) 처리. clamp 최소/최대 적용 |
| **PostToolUse `duration_ms` 미실측 → v5.18.3급 사고** | H | H | **v5.21.0 Spike 게이트 차단** (S2-0). 5건 실측 후 진행 |
| **events.jsonl 비대화** — 현재 2051줄/586KB. PostToolUse 추가 시 도구 1000회 = +1000줄 | H | M | rotation 1MB로 낮추거나 PostToolUse 별도 파일(tool-events.jsonl) 분리. analyze에 `--since DATE` 필터. v5.21.0 결정 |
| **schema v1↔v2 미호환** — 기존 2051줄 confidence=null. ≥0.7 필터가 전부 걸러내면 사용자 혼란 | M | M | jq `// null` fallback 전체 적용. analyze 출력에 schema_version 분기 표시 + "v1 record N건 confidence 없음" 안내 |
| **채택/거부 입력 인터페이스 미정의** | H | M | **`/nova:evolve --accept` / `--reject`** 명시 트리거 (Plan 결정 #2). AI 자가 기록 절대 금지 |
| **Multi-AI `/nova:ask` PostToolUse 비용 오집계** — duration_ms를 비용으로 오해 | M | L | event_subtype: "tool_timing" 명시. evolve 리포트에서 duration_ms 비용 표기 금지 |
| **PostToolUse 훅 실패 시 도구 차단 여부** — non-zero exit 동작 미검증 | M | H | Spike(S2-0)에서 실측. 최종 `exit 0` 강제. 비동기 spawn(`&`) 패턴 적용 |
| **NOVA-STATE 9 진입점 + Stop 훅 이중 session_end** — PostToolUse → session_end 순서 역전 | M | M | session_end 이후 이벤트는 sequence 분석에서 제외. sentinel 처리 (S2-4 회귀 가드) |
| **`--accept`/`--reject` 다중 호출 → NOVA-STATE 트림 루프** (Critic 이슈 #3) | M | M | `evolve_decision` 이벤트는 NOVA-STATE 갱신 트리거 **제외** (Plan 결정 #3). JSONL only |
| **다중 worktree 신뢰도 집계 왜곡** — session.id CWD 기반 분리 (Critic 이슈 #1) | M | M | v5.20.0 scope-out (단일 worktree 가정). 사용자 안내 문구 (analyze 출력 헤더). v5.21.0+ worktree 통합 검토 |

---

## Unknowns

(risk-explorer 5건 → Plan 결정으로 [U3], [U4] 해소. [U6] 신규)

- **[U1] PostToolUse stdin 페이로드 필드 실측 미완** — Claude Code v2.1.119 `duration_ms`, `output`, `error` 키 위치/단위. v5.18.3 패턴. **v5.21.0 Spike 게이트(S2-0)로 격리.**
- **[U2] session_start 중복 버스트의 근본 원인** — events.jsonl 라인 11~49에 0.1초 간격 11회 연속. PostToolUse 적용 여부 미확인. **v5.21.0 Spike(S2-0)에서 실측.**
- **~~[U3] confidence 필드 역방향 마이그레이션~~** — **해소**: jq `// null` fallback + schema_version 분기 출력 (S1-2).
- **~~[U4] pattern_id 정의~~** — **해소**: Plan 결정 #1로 SHA-256 앞 8자 형식 확정. 충돌 처리는 Design에서 정밀화.
- **[U5] CI=true 환경변수 사용자 로컬 실수** — `./nova-events/events.jsonl`(프로젝트 루트) 분기. v5.21.0에서 경고 로그 1줄 추가.
- **[U6] ECC 흡수 baseline 미정의** — **해소 진행 중**: S1-0 baseline 스냅샷 단계 추가 (`docs/baselines/v5.20.0-baseline.md`). 단 v5.20.0 자체가 baseline이라 P0-2/P0-3/P1-1 흡수 후 비교 자료가 누적되는 시점은 v5.22.0+ 예상.

---

## Verification Hooks (v5.20.0 릴리스 게이트)

> v5.20.0 릴리스 게이트 — 모든 항목 PASS 시 release.sh minor 진입.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 1 | schema v2 필드(`tool`, `duration_ms`, `confidence`, `pattern_id`)가 `extra` payload에 nullable로 정의됨 | `grep -E "confidence\|pattern_id" hooks/record-event.sh` | Critical |
| 2 | 신뢰도 공식 8 케이스 단위 테스트 PASS (clamp 경계 포함) | `bash tests/test-scripts.sh` 신규 assert ② | Critical |
| 3 | analyze-observations.sh `--format json` 플래그 schema v1/v2 모두 처리 | `bash scripts/analyze-observations.sh --format json \| jq .` PASS | Critical |
| 4 | `/nova:evolve --from-observations` ≥0.7 패턴만 노출 + "자동 승격 금지" 키워드 출력 | `bash -c 'cat .claude/commands/evolve.md \| grep -i "자동 승격 금지"'` | Critical |
| 5 | `/nova:evolve --accept {dummy_id}` 호출 → events.jsonl evolve_decision 이벤트 기록 + NOVA-STATE 미갱신 | 통합 테스트 1건: `tail -1 .nova/events.jsonl \| jq -r '.event_type'` == `"evolve_decision"` AND `git diff NOVA-STATE.md` 없음 | Critical |
| 6 | pattern_id SHA-256 앞 8자 형식 — 동일 입력 동일 출력 | 단위 테스트: `(event_type=tool_call, tool=Bash, week=2026-W18) → 8자 hex` | Critical |
| 7 | 491 → 500+ tests, 회귀 0 | `bash tests/test-scripts.sh` 출력 라인 수 | Critical |
| 8 | NOVA-STATE.md 50줄 이내, **9 진입점 유지** (10 진입점 X) | `wc -l NOVA-STATE.md` ≤ 50 + `grep -c "evolve_decision" .claude/skills/context-chain/SKILL.md` 검증 (트리거 X 명시) | Critical |
| 9 | session-start.sh JSON 유효성 + 동기화 | `bash hooks/session-start.sh \| python3 -m json.tool` | Critical |
| 10 | docs/nova-rules.md §10 신뢰도 공식 + clamp 노출 | `grep -E "clamp.*0.*1" docs/nova-rules.md` | Nice-to-have |
| 11 | `docs/baselines/v5.20.0-baseline.md` 존재 + 5개 항목 (wc/analyze/evaluator FAIL률/Top 10/v1 record수) | `test -f docs/baselines/v5.20.0-baseline.md` + grep 5 항목 | Critical |

## Verification Hooks (v5.21.0 릴리스 게이트)

> v5.21.0 릴리스 시점에 도입. v5.20.0 회귀 가드에는 **포함하지 않음** (release FAIL 회피).

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 12 | PostToolUse Spike 5건 실측 결과 메모리/문서 기록 | `feedback_post_tool_use_*.md` 또는 `docs/unknowns-resolution.md` 존재 | Critical |
| 13 | `bash hooks/post-tool-use.sh < {payload}` → events.jsonl에 `tool` + `duration_ms` 기록 | 통합 테스트 1건 | Critical |
| 14 | 도구별 평균/p95 duration 출력 (json + 텍스트) | `bash scripts/analyze-observations.sh --tool-stats \| jq '.tools.Bash.p95'` | Critical |
| 15 | session_end 이후 이벤트 sequence 분석 sentinel 처리 | 통합 테스트: `session_end` → `tool_call` 기록 후 sequence 출력에서 제외 확인 | Critical |
| 16 | v5.20.0 baseline과의 비교 보고 가능 | `bash scripts/analyze-observations.sh --compare docs/baselines/v5.20.0-baseline.md` | Nice-to-have |

---

## 다음 단계

1. **본 Plan에 대한 Critic 재검증 완료** — 7건 모두 Plan 단계에서 해소 (이 문서 자체).
2. `/nova:design "measurement-infrastructure"` — Sprint 1 8파일 + Sprint 2 5파일 구체 설계 (특히 pattern_id 충돌 처리, jq macOS/Linux 호환).
3. Sprint 1 구현 → 회귀 0 → release.sh minor (v5.20.0).
4. PostToolUse Spike 게이트 → Sprint 2 → release.sh minor (v5.21.0).
5. 측정 인프라 깔린 후 P0-2 / P0-3 / P1-1 흡수 작업의 효과를 baseline 대비 후험적으로 검증.

---

## Refiner 변경 요약 (Iteration 1)

Critic FAIL 7건 → Plan 단계 해소 7건:

1. **이슈 #1 (worktree)** → 제약 조건 9, MECE #8, Risk Map 행 추가. v5.20.0 scope-out 명시.
2. **이슈 #2 (--accept/--reject UI)** → 제약 조건 10, Plan 결정 #2 (기존 evolve.md 옵션 추가, 신규 커맨드 X), Verification Hook #5 검증 명령 구체화.
3. **이슈 #3 (트림 루프)** → 제약 조건 6, Plan 결정 #3 (evolve_decision NOVA-STATE 트리거 제외), Risk Map 행 추가, Verification Hook #8 검증 추가.
4. **이슈 #4 (pattern_id)** → Plan 결정 #1 (SHA-256 앞 8자), Unknowns [U4] 해소, S1-5 회귀 가드 ⑦ 추가, Verification Hook #6 추가.
5. **이슈 #5 (v5.21.0 혼재)** → Verification Hooks 테이블 v5.20.0 / v5.21.0 분리.
6. **이슈 #6 (baseline)** → S1-0 baseline 스냅샷 단계 추가, MECE #9, Unknowns [U6], Verification Hook #11.
7. **이슈 #7 (clamp)** → Plan 결정 #4 (clamp 공식 명문화), S1-5 단위 테스트 8 케이스 (이전 6 → 8).

수정 파일 카운트: 7 → 8 (S1-0 baseline 추가). 회귀 가드 카운트: +6 → +9.
