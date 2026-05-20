# [Design] NOVA-STATE.md 드리프트 클래스 구조적 차단

> Nova Engineering — CPS Framework
> 작성일: 2026-05-20
> 작성자: Nova Design
> Plan: [`docs/plans/state-drift-reconciliation.md`](../plans/state-drift-reconciliation.md)
> Work-item: WI-0013

---

## Context (설계 배경)

### Plan 요약

NOVA-STATE.md의 손편집 prose와 v3 work-item registry가 계약 없는 두 진실 평면이라, 완료된 작업이 prose에 "진행 중"으로 남아 `/nova:next`가 stale 추천을 낸다. 해결: **계약 1 + 대조 엔진 1 + 진입점 3**. 채택안은 신규 `scripts/reconcile-state.sh` + 단계적 3 스프린트(S1 계약+엔진+next / S2 pre-commit nudge+commit↔WI / S3 /nova:checkpoint).

### 설계 원칙

1. **엔진은 read-only 불변식** — `reconcile-state.sh`는 `NOVA-STATE.md`·`.nova/work-items/`를 절대 쓰지 않는다. 읽기 전용이면 다중 진입점 동시 호출이 race-free, lock 불요. (events.jsonl append는 호출자 책임.)
2. **탐지(엔진) ↔ 전이(호출자) 분리** — 엔진은 분류만, registry 전이는 `registry-write.sh`(자체 lock)를 통해 에이전트/커맨드가 수행.
3. **fuzzy는 ✅를 못 준다** — 결정적 신호(`evidence.commit_sha` reachable / `Nova-WI:` trailer)만 ✅. 키워드 매칭은 ⚠️까지만.
4. **정직 우선** — 검증 불가(❓)를 검증 완료(✅)와 합산 금지. exit code가 enforcement가 아니라 신호다.
5. **계약이 충돌 resolution 규칙** — registry=status 진실 / git=완료 진실 / prose=status 비권위. 충돌하면 prose가 진다.

### 이 Design이 확정하는 Plan Unknowns 4건

| Unknown | 확정 내용 | 위치 |
|---------|----------|------|
| 1. trailer 컨벤션 | `Nova-WI: WI-xxxx` git trailer, 반복 라인 = 다중 WI. Stop hook 자동 전이는 **v1 제외**(근거 명시) | §Solution 4 |
| 2. 임계값·윈도우 | 공유 **distinctive token ≥ 1** + `--since` 윈도우(기본 90d). 날짜별 ±14d 축소는 후속(S1 미구현). fuzzy는 항상 ⚠️ | §Solution 3 |
| 3. v2-only 동작 | skip 안 함 — **2-way 축소 모드**(prose↔git) + migrate 권고 배너 | §Solution 2 |
| 4. enforcement 강도 | Warn 시작. exit code(0/1/2)가 신호, 소비자가 enforcement 결정. release.sh 승격은 사용자 결정 | §Solution 6 |

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | NOVA-STATE.md 3종(v2-only/hybrid/v3) 파싱 — marker 안팎 분리, prose status 항목 추출 | 중 | awk/grep, marker 규약 |
| 2 | prose ↔ git log ↔ registry 3-way 대조 + 3분류 알고리즘 | 상 | git log, jq, `.nova/work-items/` |
| 3 | fuzzy 매칭 — 한↔영 노이즈 회피, distinctive token 추출 | 상 | git log 텍스트 |
| 4 | pre-commit-reminder.sh 확장 — 기존 7상태 Hard Gate·STATE_STALE·META_STALE와 단일 블록 통합 | 중 | 기존 훅 구조 |
| 5 | `/nova:checkpoint` 신규 커맨드 + session-start advisory | 중 | 커맨드/스킬 동기화 체크리스트 |

### 기존 시스템과의 접점

| 접점 | 현재 | 변경 |
|------|------|------|
| `scripts/check-state-drift.sh` | 코드↔STATE mtime drift, `--strict`/`warn` 2모드 | **재사용** — CLI 패턴(모드+`-h`+GUIDE_HINT), cross-platform epoch 로직 차용. 수정 없음 |
| `scripts/registry-drift-check.sh` | registry 내부 18룰 | 변경 없음 — SRP 분리 유지 |
| `scripts/registry-write.sh` | `create/update/transition/evaluator-pass/require-review` | 변경 없음 — 엔진이 호출만 (`transition <wi> done --evidence-commit=SHA`) |
| `hooks/pre-commit-reminder.sh` | PreToolUse, 7상태 Hard Gate + 정상경로 리마인더 JSON | **수정(S2)** — 정상경로 additionalContext에 `${DRIFT_NUDGE}` 추가 |
| `hooks/record-event.sh` | 범용 이벤트 기록 | **수정(S1)** — `state_reconciled` 이벤트 타입 문서화 |
| `.claude/commands/next.md` | git log 읽되 prose 대조 안 함 | **수정(S1)** — 추천 전 reconcile 선행 |
| `hooks/session-start.sh` | 규칙 주입 + 커맨드 목록 | **수정(S1·S3)** — §8 계약 동기화, `/nova:checkpoint` 등록, advisory reconcile |
| `docs/nova-rules.md §8` | 데이터 모델 분리(v5.44.0+) | **수정(S1)** — 계약 명문화 |

---

## Solution (설계 상세)

### 아키텍처

```
                         ┌──────────────────────────┐
   진입점 (소비자)        │   scripts/reconcile-state.sh │  ← read-only 엔진
   ─────────────         │   (어떤 파일도 쓰지 않음)     │
   S2 pre-commit  ──────▶ │                          │
   S1 /nova:next  ──────▶ │  1. STATE 클래스 판정      │
   S3 /nova:checkpoint ─▶ │  2. 3 소스 수집           │──▶ prose 파서 (marker 밖)
   S3 session-start ────▶ │  3. 대조·분류            │──▶ git log oracle (--since)
                          │  4. 3분류 출력 (exit 0/1) │──▶ registry (.nova/work-items)
                          └──────────────────────────┘
                                       │
                          stdout: ✅/⚠️/❓ 리포트 또는 --jsonl
                                       │
   전이(쓰기)는 호출자가 ───────────────┘
   registry-write.sh transition (자체 lock) 으로만 수행
```

엔진은 **순수 함수** — 입력(STATE+git+registry) → 출력(분류 리포트). 부작용 0. 그래서 pre-commit·next·checkpoint·session-start가 동시 호출해도 안전하다.

### 핵심 로직 — `reconcile-state.sh`

**CLI 계약** (`check-state-drift.sh` 패턴 차용):
```
bash scripts/reconcile-state.sh [--jsonl] [--since=<N>d] [-h|--help]
  (기본)      사람용 3분류 리포트, stdout
  --jsonl    기계 판독 단일 JSON object
  --since    git log 조회 윈도우 (기본 90d)
  -h         도움말 + 가이드 경로(docs/guides/state-drift-reconciliation.md)
```

**STEP 1 — STATE 클래스 판정** (frontmatter 아닌 산출물 기준):
```
has_registry = .nova/work-items/index.json 존재 && work_items 비어있지 않음
has_marker   = NOVA-STATE.md에 "<!-- nova:registry-rendered:start -->" 포함
schema_v     = frontmatter "schema_version:" 값

state_class:
  v3       = has_registry && schema_v == 3
  hybrid   = has_registry && schema_v != 3        (3-way 가능, migrate 권고 배너)
  v2-only  = !has_registry                        (2-way 축소 모드, migrate 권고 배너)
```
→ v3·hybrid = **3-way 모드**, v2-only = **2-way 모드**.

**STEP 2 — 3개 소스 수집:**

1. *prose 항목* — NOVA-STATE.md의 **marker 밖** 영역에서 추출. 다음은 **제외**: marker 안쪽, `## Recent Activity`/`## Recently Done`/`## 📊 Recent Activity` 표, `<details>` Archive 블록. 추출 단위 = 리스트 항목(`- `,`* `,`N.`) 또는 표 row 중 — (a) 체크박스 `- [ ]`(미완) 또는 (b) status 키워드 포함(`진행 중|진행중|작업 중|WIP|in progress|TODO`). 각 항목 → `{section, line_no, text}`.
2. *git 완료 oracle* — `git log --since=<window> --pretty=...`. 커밋별 `{sha, date_iso, subject, nova_wi[], tokens[]}` (body는 `%x1f` 구분자 보호 위해 미수집, date_iso는 수집만·현재 미사용). trailer 추출: `git log --pretty='%(trailers:key=Nova-WI,valueonly,separator=%x2C)'`.
3. *registry* — `.nova/work-items/index.json` + 개별 WI json. WI별 `{id, status, priority, title, evidence_sha, source_docs[]}`.

**STEP 3 — 대조·분류:**

*WI 분류* (3-way 모드):
| WI 상태 | 조건 | 분류 |
|---------|------|------|
| done | `evidence_sha` reachable (`git cat-file -e`) | 🟢 정상 |
| done | `evidence_sha` 부재/unreachable (squash/rebase 고아) | ⚠️ explicit (SHA 재바인딩) |
| active/proposed | 윈도우 내 커밋에 `Nova-WI: <id>` trailer 존재 | ⚠️ explicit (전이 누락 — 거의 확실) |
| active/proposed | 커밋과 distinctive token ≥1 일치 (trailer 없음) | ⚠️ fuzzy (확인 필요) |
| active/proposed | 일치 커밋 없음 | 🟢 정상 (정당하게 진행 중) |

*prose 항목 분류*:
| 조건 | 분류 |
|------|------|
| 윈도우 내 커밋과 distinctive token ≥1 일치 | ⚠️ fuzzy ("prose는 진행 중인데 git에 일치 커밋") |
| 일치 커밋 없음 + 대응 WI 없음 | ❓ untracked (Nova가 알 수 없음) |
| 텍스트가 특정 WI title과 겹침 | 해당 WI 분류로 흡수 (중복 보고 방지) |

**fuzzy 매칭 규칙** (Unknown 2 확정):
- **distinctive token** (언어 중립, 고신호): kebab 식별자 `[a-z][a-z0-9]*(-[a-z0-9]+)+` (예 `gc-cost-jump`), 플래그 `--[a-z][a-z-]+`, 경로(`/` 포함 또는 `.sh/.md/.json/.py` 등), 버전 `v?\d+\.\d+\.\d+`, `WI-\d+`, 따옴표 문자열.
- **매칭 성립 = 공유 distinctive token ≥ 1.** 자연어 단어만 겹치는 것은 매칭 불성립 (한↔영 노이즈 + `feat/fix` prefix floor 회피). git prefix(`feat|fix|chore|docs|refactor|update|security|axis` + `(scope):`)는 토큰화 전 제거.
- **score** = 공유 distinctive token 수. **시간 윈도우**: `--since`(기본 90d) 단일 적용. (prose 날짜별 ±14d 축소는 정밀도 refinement — S1 미구현, 후속 검토.)
- fuzzy는 **절대 ✅·자동전이 없음** — ⚠️ 보고까지만.
- 캘리브레이션: Sprint Contract S1-C7이 Nova git log 30커밋으로 ⚠️ 오탐 ≤ 2건 측정. 초과 시 임계값을 distinctive token ≥ 2로 상향.

**STEP 4 — 출력 + exit code:**
- exit 0 = 🟢만 (clean) · exit 1 = ⚠️/❓ ≥1 · exit 2 = 엔진 오류(STATE 없음 등)
- exit code는 **신호일 뿐 enforcement 아님** — 소비자가 처리 방식 결정.

사람용 출력:
```
Nova State Reconcile — hybrid STATE · registry 13 WI · git 90d
⚠️ hybrid: STATE 본문이 v2 형식 — /nova:migrate-state로 완전 v3 권고

✅ 완료검증 (N)
⚠️ 완료의심 — 확인 필요 (N)
  [explicit] WI-0013  registry=proposed ↔ 커밋 a1b2c3d Nova-WI:WI-0013
             → bash scripts/registry-write.sh transition WI-0013 done --evidence-commit=a1b2c3d
  [fuzzy]    prose L15 "gc-cost-jump --cron-window 진행 중" ↔ af5912f
             공유 토큰: gc-cost-jump, --cron-window
❓ 추적불가 — Nova가 상태를 알 수 없음 (N)
🟢 정상: N
```

### 진입점 설계

**S1 — `/nova:next` 통합** (`.claude/commands/next.md` 수정):
추천 로직 Step 1에 reconcile 선행 추가 — `reconcile-state.sh --jsonl` 실행 → ⚠️/❓ 항목을 "다음 작업" 추천 후보에서 **제외하거나 ⚠️ 플래그**. 신뢰도 순위 명문화: **git log > registry > prose**. reconcile 실패/타임아웃 시 graceful skip(기존 진단 계속).

**S2 — pre-commit nudge** (`hooks/pre-commit-reminder.sh` 수정):
기존 정상경로(Hard Gate PASS 이후, L182~)에서 `STATE_STALE`/`META_STALE` 산출 직후 `DRIFT_NUDGE` 산출 추가:
```
DRIFT_NUDGE=""
reconcile 실행 (timeout 3s, 실패 시 skip):
  exit==1 && (suspect+untracked) >= 1 이면:
    DRIFT_NUDGE="⚠️ STATE 드리프트: 완료의심 X · 추적불가 Y. /nova:checkpoint로 정리 권장."
    ⚠️-explicit 있으면 += " 커밋 후: registry-write.sh transition <wi> done --evidence-commit=<HEAD SHA>"
```
`${DRIFT_NUDGE}`를 기존 additionalContext의 `${STATE_STALE}\n${META_STALE}` 줄에 **합류 — 별도 블록 추가 X, 단일 통합 블록**. drift 0건이면 `DRIFT_NUDGE` 빈 문자열 → 침묵. 절대 `exit 2` 안 함(Warn). 차단 경로(Hard Gate FAIL)에는 reconcile 호출 안 함 — 지연 0.

**S3 — `/nova:checkpoint`** (`.claude/commands/checkpoint.md` 신규, 커맨드 단독 — 별도 skill 불요):
세션 종료 의도적 체크포인트. 동작: (1) `reconcile-state.sh` 실행 (2) 3분류를 **정직하게** 보고 — ❓는 "검증 불가 — 직접 확인 필요" 별도 상단 블록, ✅과 절대 합산 X (3) ⚠️-explicit은 `transition done` 명령을 제시하고 실행 여부를 사용자에게 확인 (4) ⚠️-fuzzy는 "이 작업 끝났나요?" 질문 (5) ❓는 보고만. 단일 PASS/FAIL verdict 금지 — 3분류 카운트 그대로 노출. 종료 시 `state_reconciled` 이벤트 기록.

**S3 — session-start advisory** (`hooks/session-start.sh` 수정):
세션 시작 시 `reconcile-state.sh --jsonl` 1회(timeout 짧게) → drift 있으면 additionalContext에 **1줄** advisory 주입("STATE 드리프트 N건 — `/nova:checkpoint` 권장"). session-start 경량 예산(soft ≤1200자) 준수 — 1줄 초과 금지. 실패 시 skip.

### commit↔WI 연결 (Unknown 1 확정)

- **trailer 형식**: git trailer `Nova-WI: WI-xxxx` (커밋 메시지 footer). 다중 WI = 반복 라인. 콤마 구분도 파서가 관용 수용.
- **에이전트 워크플로우**: WI 작업을 커밋할 때 (a) 커밋 메시지에 `Nova-WI:` trailer 추가 (b) 커밋 직후 `registry-write.sh transition <wi> done --evidence-commit=$(git rev-parse HEAD)` 호출. pre-commit nudge가 이를 상기.
- **trailer 누락 fallback**: trailer 없으면 reconcile가 fuzzy 경로로 처리(⚠️-fuzzy).
- **Stop hook 자동 전이 — v1 제외 (설계 결정)**: 근거 — (1) per-turn 발화 훅에서 registry 자동 변경은 SHA 추적 상태파일 필요 (2) hook의 침묵 자동 mutation은 "변경 전 확인" 원칙·승인 스코프("경고 수준")와 충돌. v1은 **trailer가 reconcile 탐지를 결정적(⚠️-explicit)으로 만드는 역할**까지. Sprint Contract S2-C13(Warn 효과 측정)에서 nudge 무시율이 높게 측정되면 v2에서 자동 전이를 재검토.

### nova-rules §8 계약 명문화 (S1)

`docs/nova-rules.md §8`에 추가 (+ `hooks/session-start.sh` 동기화):
```
- 상태 진실원 계약: registry(.nova/work-items) = status 단일 진실 ·
  git = 완료 단일 진실 · NOVA-STATE.md prose = status를 갖지 않는 비공식
  스냅샷(Goal·관찰·서사). 충돌 시 prose는 비권위 — 진다.
  "진행 중"인 작업은 prose가 아니라 work-item으로 표현한다.
  드리프트 점검: bash scripts/reconcile-state.sh (또는 /nova:checkpoint).
```

### 데이터 계약 (Data Contract)

| 필드 / 산출물 | 단위·포맷 | 규칙 |
|---------------|----------|------|
| `reconcile-state.sh` exit code | 0 / 1 / 2 | 0=clean, 1=drift(⚠️/❓≥1), 2=engine error. **신호이지 enforcement 아님** |
| `--jsonl` 출력 | 단일 JSON object | `{state_class, window, mode, counts:{verified,suspect_explicit,suspect_fuzzy,untracked,normal}, items:[...], banner?}` |
| `items[].category` | enum | `verified` \| `suspect_explicit` \| `suspect_fuzzy` \| `untracked` \| `normal` |
| `items[].source` | enum | `wi` \| `prose` |
| `items[].evidence` | string | wi: SHA 또는 trailer SHA / prose: 매칭 커밋 SHA + 공유 토큰 / untracked: `null` |
| STATE 클래스 | enum | `v3` \| `hybrid` \| `v2-only` — §STEP 1 산출물 기준 판정 |
| 시간 윈도우 | `<N>d` 문자열 | 기본 `90d`, `--since`로 조정. (날짜별 ±14d 축소는 후속 — S1 미구현) |
| distinctive token | 정규식 매칭 문자열 | kebab-id / `--flag` / path / `vX.Y.Z` / `WI-\d+` / 따옴표열. 매칭 임계 ≥1 |
| `Nova-WI:` trailer | `WI-` + 숫자 + slug | 커밋 footer. 다중 = 반복 라인. `git log --pretty='%(trailers:key=Nova-WI,valueonly)'` |
| `registry-write transition` 인자 | `<wi-id> done --evidence-commit=<40-hex SHA>` | SHA는 `git rev-parse HEAD` 결과. 엔진이 아닌 호출자가 실행 |
| `state_reconciled` 이벤트 | events.jsonl 1줄 | `extra={state_class, counts, trigger}`. 호출자(checkpoint/next/pre-commit)가 기록. append-only |
| reconcile 성능 예산 | < 500ms (typical), 호출 timeout 3s | 초과 시 graceful skip — 소비자는 진단/커밋 계속 |

### 에러 처리

| 상황 | 동작 |
|------|------|
| `NOVA-STATE.md` 없음 | exit 2 + "STATE 없음" 메시지. 소비자(pre-commit/next)는 skip — 차단 안 함 |
| `.nova/work-items/` 없음 (v2-only) | 2-way 모드로 축소 — skip 아님. migrate 권고 배너 |
| `git` 미설치 / git 레포 아님 | exit 2, graceful. prose만으로는 대조 불가 → "git 필요" 안내 |
| `jq` 없음 | `check-state-drift.sh`식 폴백 또는 exit 2 graceful. 소비자 skip |
| reconcile 타임아웃 (>3s) | 소비자가 `|| true`로 skip. pre-commit·session-start·next 모두 정상 진행 |
| `evidence_sha` unreachable | FAIL 아님 — ⚠️ "SHA 재바인딩 필요"로 분류 (squash/rebase 대응) |
| prose 파서가 marker 내부를 prose로 오인 | read-only라 파일 손상 0. 3 fixture 단위 테스트(S1-C2)가 회귀 차단 |

---

## Sprint Contract (스프린트별 검증 계약)

> 구현 전 정의 — Generator·Evaluator 사전 합의. Plan의 Verification Hooks 14건을 스프린트로 배분.

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| S1 | `reconcile-state.sh`가 v2-only/hybrid/v3 fixture를 정확히 분류 | 3 fixture로 `state_class` 확인 | `bash scripts/reconcile-state.sh --jsonl \| jq .state_class` (fixture별) | Critical |
| S1 | 파서가 marker 내부 `⬜`/Recent Activity 표를 prose status로 오인하지 않음 | hybrid fixture 출력 검사 | `bash scripts/reconcile-state.sh --jsonl \| jq '[.items[]\|select(.source=="prose")]'` → marker/표 항목 부재 | Critical |
| S1 | 엔진 read-only — 실행 후 STATE·registry 무변경 | 실행 전후 git status·mtime 비교 | `git status --porcelain > /tmp/a; bash scripts/reconcile-state.sh; git status --porcelain > /tmp/b; diff /tmp/a /tmp/b` | Critical |
| S1 | Nova 자기 레포 dogfooding — `goal` 불일치 + 12 proposed WI 탐지 | 실제 레포 실행 | `bash scripts/reconcile-state.sh \| grep -E 'goal\|WI-00'` | Critical |
| S1 | `/nova:next`가 git 완료 보이는 작업을 추천 안 함 (원래 버그 차단) | fixture STATE+커밋 → next 출력 | fixture에 "진행 중" prose + 일치 done 커밋 배치 후 `/nova:next` 출력에 해당 항목 제외/⚠️ | Critical |
| S1 | exit code 계약 — clean=0, drift=1 | clean·drift fixture | `bash scripts/reconcile-state.sh; echo $?` (fixture별 0 / 1) | Critical |
| S1 | fuzzy 오탐 정량 통제 | Nova git log 30커밋 대상 측정 | `bash scripts/reconcile-state.sh --since=30d` → ⚠️-fuzzy 오탐 ≤ 2건, 값을 가이드에 기록 | Critical |
| S1 | 계약 동기화 — nova-rules §8 ↔ session-start.sh + JSON 유효 | 동기화 테스트 | `bash hooks/session-start.sh \| python3 -m json.tool && bash tests/test-scripts.sh` | Critical |
| S1 | 가이드 존재 + `-h`가 가이드 경로 안내 | 회귀 가드 | `bash scripts/reconcile-state.sh -h \| grep guides/state-drift-reconciliation.md` | Critical |
| S2 | pre-commit nudge가 drift 0건일 때 침묵 | drift 없는 fixture에 stdin 주입 | drift-free fixture에서 `echo '{"tool_input":{"command":"git commit"}}' \| bash hooks/pre-commit-reminder.sh` → 출력에 드리프트 문구 부재 | Critical |
| S2 | drift ≥1건 시 기존 경고와 **단일 블록**으로 발화 | drift fixture | drift fixture에서 위 명령 → additionalContext에 드리프트 문구 1회, 블록 1개 | Critical |
| S2 | commit↔WI — `transition done --evidence-commit` 후 reconcile가 🟢로 분류 | 전이 후 재실행 | WI 전이 → `bash scripts/reconcile-state.sh --jsonl \| jq '.counts.suspect_explicit'` 감소 | Critical |
| S2 | Warn 효과 측정 훅 — `state_reconciled` 이벤트 기록됨 | events.jsonl 확인 | `grep -c state_reconciled .nova/events.jsonl` ≥ 1 (출시 후 무시율 분석 입력) | Nice-to-have |
| S3 | `/nova:checkpoint` 등록 — session-start 목록 + EXPECTED_COMMANDS | 자동 테스트 | `bash tests/test-scripts.sh` (EXPECTED_COMMANDS·커맨드 목록 검증) | Critical |
| S3 | checkpoint가 ❓를 ✅과 분리 보고 | 출력 구조 검사 | ❓ 포함 fixture에서 `/nova:checkpoint` → ❓가 별도 "검증 불가" 블록, ✅과 미합산 | Critical |
| S3 | session-start advisory 1줄 — 경량 예산 준수 | 길이 검사 | `bash hooks/session-start.sh \| python3 -m json.tool` + additionalContext drift 문구 ≤ 1줄 | Critical |
| 전체 | 기존 테스트 무손상 회귀 | 전체 스위트 | `bash tests/test-scripts.sh` 전체 PASS | Critical |

---

## 관통 검증 조건 (End-to-End)

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | WI에 해당하는 작업을 `Nova-WI:` trailer 없이 평범하게 `git commit` | `reconcile-state.sh`가 해당 WI를 ⚠️-fuzzy로 분류, `/nova:next`가 추천에서 제외 | Critical |
| 2 | 커밋에 `Nova-WI: WI-xxxx` trailer 포함 후 commit | reconcile가 ⚠️-explicit로 분류 + `transition done` 명령 제시 | Critical |
| 3 | 제시된 `registry-write transition done --evidence-commit` 실행 | 재실행 시 해당 WI가 🟢 정상, `/nova:next`·`/nova:checkpoint`에서 사라짐 | Critical |
| 4 | prose에만 있고 WI 아닌 "진행 중" 항목 + 일치 커밋 없음 | `/nova:checkpoint`가 ❓ "검증 불가" 블록에 표시, ✅로 합산 안 함 | Critical |
| 5 | drift 없는 깨끗한 상태에서 `git commit` | pre-commit nudge가 드리프트 문구 없이 침묵 | Critical |

---

## 평가 기준 (Evaluation Criteria)

- **기능**: Plan 요구 4항목(계약·엔진·3진입점·commit↔WI)이 동작하는가? 원래 stale 버그가 재현 차단되는가(E2E #1·#3)?
- **설계 품질**: 엔진 read-only 불변식이 지켜지는가? 엔진(탐지)과 registry-write(전이)의 책임 분리가 코드에서 유지되는가?
- **단순성**: 신규 스크립트 1 + 신규 커맨드 1로 한정되는가? `registry-drift-check.sh`와 책임 중복이 없는가?
- **정직성**: ❓가 ✅과 절대 합산되지 않는가? fuzzy가 ✅를 주지 않는가?

---

## 역방향 검증 체크리스트

- [ ] Plan의 계약(1)·대조 엔진(2)·진입점 3개(3)·commit↔WI(4)가 모두 Design에 반영됐는가
- [ ] Plan Unknowns 4건이 Design에서 확정됐는가 (trailer·임계값·v2-only·enforcement)
- [ ] Plan Risk Map 11건의 완화책이 Design 또는 Sprint Contract에 대응되는가
- [ ] reconcile-state.sh가 `check-state-drift.sh`·`registry-drift-check.sh`와 책임이 겹치지 않는가 (SRP)
- [ ] 누락 엣지: v2-only 레포 / squash 고아 SHA / WI title 날짜뿐 / fuzzy 한↔영 노이즈 — 모두 Solution·에러처리에 명시됐는가
- [ ] 신규 커맨드/스크립트 동기화 체크리스트(가이드·README·EXPECTED_COMMANDS·`-h`·session-start)가 Sprint Contract에 포함됐는가
