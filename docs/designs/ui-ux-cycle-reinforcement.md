# [Design] UI/UX 인지 사이클 강화 (ui-ux-cycle-reinforcement)

> Nova Engineering — CPS Framework
> 작성일: 2026-04-18
> Plan: docs/plans/ui-ux-cycle-reinforcement.md
> Verification: docs/verifications/2026-04-18-Nova-5기둥-AI-Agent-Ops-프레임워크-환경-맥락-품질-협업.md

---

## Context (설계 배경)

### Plan 요약
- **핵심 문제**: Nova는 UI 코드 변경 시 (1) 디자인 시스템 정합성을 자동 검증하지 못하고, (2) UI 작업이라는 사실을 인식해 적절한 평가를 자동 트리거하지 못한다.
- **선택한 방안**: 2 Sprint 분할. Sprint A = ux-audit Cognitive Load 평가자에 디자인 항목 흡수. Sprint B = orchestrator(auto)에 UI 감지 분기 + ux-audit Lite 자동 호출.

### 설계 원칙
1. **신규 슬래시 커맨드/스킬 0개** — 기존 자산 강화로만 진행
2. **하네스 비의존성** — Claude Design / Figma 등 특정 도구에 종속되지 않음
3. **Deterministic over LLM** — 휴리스틱은 셸 스크립트 헬퍼로 분리해 LLM 변동성 제거
4. **첫 트리거 학습** — 자동화는 사전 고지 + opt-out 경로를 항상 동반
5. **5인 평가자 구조 유지** — 항목 추가는 OK, 평가자 신설은 금지
6. **메트릭 기록 우선, 분석은 차기 evolve** — 진화 기둥의 최소 진입점

---

## Problem (설계 과제)

### 기술적 과제

| # | 과제 | 복잡도 | 의존성 |
|---|------|--------|--------|
| 1 | 디자인 시스템 자동 감지 (다중 스택 대응) | 중간 | 없음 |
| 2 | Cognitive Load 평가자 프롬프트 재작성 (정체성 유지 + B 항목 동적 비활성) | 낮음 | 과제 1 |
| 3 | UI 감지 휴리스틱 (오탐 방지 5종 + 캐시) | **높음** | 없음 |
| 4 | orchestrator Phase 5↔7 사이에 ux-audit Lite 호출 분기 삽입 | 중간 | 과제 3 |
| 5 | nova-config.json 스키마 도입 + .nova/ 런타임 디렉토리 표준화 | 중간 | 없음 |
| 6 | 메트릭 jsonl 로깅 (append-only + 회전) | 낮음 | 과제 5 |
| 7 | 사전 고지 메시지의 "첫 트리거" 상태 추적 | 낮음 | 과제 5 |

### 기존 시스템과의 접점

- **commands/auto.md** — 단순 디스패처(15줄). 실 변경은 orchestrator 스킬에서. **Plan 6파일 명시는 정정**: auto.md는 변경 없음
- **skills/orchestrator/SKILL.md** — Phase 1 (요청 분석)에서 UI 감지 1차, Phase 5(Evaluator) 이후 ux-audit Lite 실행
- **skills/ux-audit/SKILL.md** + **commands/ux-audit.md** — Cognitive Load 섹션 동기화 (둘 다 수정 필수, 테스트가 동기화 자동 검증)
- **hooks/session-start.sh** — 자동 적용 규칙에 변경 없음. 단 1200자 제약 유지 위해 신규 규칙 텍스트 추가하지 않음
- **.nova/** — 기존에 `session-state.json` 1개 존재. 새 파일 4개 추가 (`ui-state.json`, `last-audit.json`, `metrics.jsonl`, `.gitignore`)

### 호환성 고려사항
- 기존 사용자: 첫 트리거 시 자세한 안내 → opt-out 가능. 깜짝 변경 차단
- 기존 ux-audit 호출 사용자: 동작 변화 없음 (Lite 모드는 auto에서만 사용, 직접 호출은 Full 5인 그대로)
- nova-config.json 미존재 시 기본값 사용 — 기존 프로젝트 중단 없음

---

## Solution (설계 상세)

### 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│  /nova:auto "요청"                                               │
│  └─ commands/auto.md (디스패처)                                  │
│     └─ skills/orchestrator/SKILL.md                              │
│        Phase 1: 요청 분석                                        │
│        ├─ 복잡도 판단                                            │
│        └─ [신규] scripts/detect-ui-change.sh --planning-mode     │
│           "UI 변경 가능성 N% (휴리스틱 기반)"                     │
│        Phase 2: Architect (생략 가능)                            │
│        Phase 3: 프롬프트 변환                                    │
│        Phase 4: Generator                                        │
│        Phase 5: Evaluator (PASS/FAIL)                            │
│        ├─ FAIL: Phase 6 → 재시도                                 │
│        └─ PASS:                                                  │
│           [신규] scripts/detect-ui-change.sh --post-impl         │
│           ├─ isUI? = false → Phase 7 (보고)                      │
│           └─ isUI? = true:                                       │
│              ├─ cache hit? → "이전 감사와 동일" 1줄 → Phase 7    │
│              ├─ --no-ux-audit? → opt-out 기록 → Phase 7          │
│              ├─ config.auto.uiAudit=false? → opt-out → Phase 7   │
│              └─ ux-audit Lite (3인) 실행                          │
│                 ├─ Critical 0 → PASS, 결과를 Phase 7에 통합     │
│                 └─ Critical ≥ 1 → 커밋 차단, 사용자 보고        │
│        Phase 7: 결과 보고                                        │
│           └─ NOVA-STATE.md Last Activity 갱신 (UI 감지 결과 포함)│
└──────────────────────────────────────────────────────────────────┘

병렬 자산:
  ┌──────────────────────────────────────────────────┐
  │  skills/ux-audit/SKILL.md                        │
  │  Phase 1 환경 분석                                │
  │  └─ [신규] 디자인 시스템 자동 감지                │
  │     scripts/detect-design-system.sh              │
  │  Phase 2 평가자 5인 (Cognitive Load 강화)         │
  └──────────────────────────────────────────────────┘
```

### 데이터 모델

#### 디자인 시스템 카탈로그 (메모리 객체, JSON)

```jsonc
{
  "detected": true,
  "sources": [
    { "type": "tailwind", "path": "tailwind.config.ts" },
    { "type": "css-vars", "path": "src/styles/globals.css" }
  ],
  "tokens": {
    "color": ["primary", "secondary", "error", "success", "warning", "neutral-50", "neutral-900"],
    "spacing": ["xs", "sm", "md", "lg", "xl", "2xl"],
    "fontSize": ["xs", "sm", "base", "lg", "xl"],
    "borderRadius": ["sm", "md", "lg", "full"]
  },
  "tokenCount": { "color": 7, "spacing": 6, "fontSize": 5, "borderRadius": 4 },
  "components": ["Button", "Input", "Card", "Modal"]
}
```

평가자 컨텍스트 주입 방식: **요약 우선** — 토큰 카탈로그 전체가 아니라 `tokenCount` + 카테고리별 첫 5개만 주입(평가자 프롬프트 토큰 부담 최소화). 평가자가 필요 시 Read 도구로 원본 파일 직접 읽음.

#### .nova/ui-state.json (첫 트리거 추적)

```jsonc
{
  "first_ui_audit_shown": true,
  "first_shown_ts": "2026-04-18T10:00:00+09:00",
  "total_triggered": 23
}
```

#### .nova/last-audit.json (재감사 캐시)

```jsonc
{
  "hash": "sha256:abc123...",
  "ts": "2026-04-18T10:05:00+09:00",
  "result": "PASS",
  "files": ["src/components/Button.tsx", "src/styles/theme.css"],
  "stats": { "critical": 0, "high": 1, "medium": 2, "low": 3 }
}
```

#### .nova/metrics.jsonl (append-only 이벤트 로그)

```jsonc
{"ts":"2026-04-18T10:05:00+09:00","event":"ui_audit_triggered","files":2,"loc":42,"cache_hit":false}
{"ts":"2026-04-18T10:05:30+09:00","event":"ui_audit_completed","critical":0,"high":1,"medium":2,"low":3,"duration_ms":28000}
{"ts":"2026-04-18T11:00:00+09:00","event":"ui_audit_opt_out","reason":"flag"}
{"ts":"2026-04-18T11:30:00+09:00","event":"ui_audit_opt_out","reason":"config"}
{"ts":"2026-04-18T12:00:00+09:00","event":"ui_audit_b_item_silenced","reason":"no-design-system"}
```

회전: `wc -l metrics.jsonl > 1000` 시 `metrics.YYYYMM.jsonl`로 mv, 새 파일 시작.

#### nova-config.json (프로젝트 루트, 신규)

```jsonc
{
  "auto": {
    "uiAudit": true,
    "uiAuditMode": "lite",
    "uiAuditBlockOnCritical": true
  },
  "ui": {
    "paths": ["src/**", "packages/*/src/**", "apps/*/app/**"],
    "exclude": ["**/*.test.*", "**/*.spec.*", "**/*.stories.*"],
    "cssInJsImports": ["styled-components", "@emotion/styled", "@emotion/react", "@linaria/core", "@stitches/react", "@vanilla-extract/css"]
  }
}
```

기본값: 파일 부재 시 모든 필드 위 값으로 동작. 사용자가 일부 필드만 정의하면 나머지는 기본값 머지.

### 데이터 계약 (Data Contract)

| 필드 | 타입 | 단위/포맷 | 변환 규칙 | 비고 |
|------|------|-----------|-----------|------|
| `metrics.ts` | string | ISO 8601 (KST `+09:00`) | KST 고정, UTC 변환 안 함 | jsonl 모든 이벤트 공통 |
| `metrics.loc` | number | 변경 라인 수 (added + deleted) | `git diff --shortstat` 합산 | UI 파일만 카운트 |
| `last-audit.hash` | string | `sha256:` prefix + hex 64자 | `sha256(sorted_filenames + concat(diffs))` | 동일 변경 캐싱 키 |
| `last-audit.result` | enum | "PASS" \| "FAIL" | Critical 0이면 PASS | High 이하는 PASS |
| `ui-state.first_ui_audit_shown` | boolean | true 시 자세한 안내 생략 | 첫 트리거 직후 true로 갱신 | 프로젝트별 상태 |
| `nova-config.auto.uiAudit` | boolean | true(기본) / false(영구 비활성) | 미정의 시 true | 팀 공유 권장 (commit) |
| `nova-config.ui.paths` | string[] | glob pattern | minimatch syntax | 사용자 추가 경로 |
| `tokenCatalog.tokenCount` | object | 카테고리별 정수 | 사용된 카테고리만 포함 | 평가자 주입용 요약 |

### API 설계 (헬퍼 스크립트 인터페이스)

`scripts/detect-ui-change.sh`:

| 모드 | 호출 | 입력 | 출력 (stdout JSON) |
|------|------|------|-------------------|
| 사전 감지 | `--planning` | (없음, git status 자동) | `{"likely_ui": bool, "files": [...]}` |
| 사후 판정 | `--post-impl` | (없음) | `{"is_ui": bool, "files": [...], "loc": N, "reason": "..."}` |
| 캐시 체크 | `--check-cache` | (없음) | `{"hit": bool, "prev_hash": "..."}` |

`scripts/detect-design-system.sh`:

| 호출 | 출력 |
|------|------|
| (인자 없음) | `tokenCatalog` JSON (위 스키마) 또는 `{"detected": false}` |

`scripts/log-metric.sh`:

| 호출 | 동작 |
|------|------|
| `--event <name> [--key val]...` | metrics.jsonl에 1줄 append + 회전 체크 |

### 핵심 로직

#### 알고리즘 1: UI 변경 감지 (`detect-ui-change.sh --post-impl`)

```bash
function isUiChange():
  changed_files = git diff --name-only HEAD~1..HEAD  # 또는 staged
  diff_text = git diff HEAD~1..HEAD

  # 1. 제외 규칙 적용 (config.ui.exclude + 기본값)
  filtered = filter_out(changed_files, EXCLUSION_GLOBS)

  # 2. UI 파일 후보 수집
  ui_files = []
  for file in filtered:
    if matches_glob(file, UI_PATH_GLOBS): ui_files.append(file)
    elif file.endswith(('.ts', '.tsx')) and is_css_in_js(file, diff_text):
      ui_files.append(file)

  # 3. 임계치 체크
  if len(ui_files) == 0: return {is_ui: false, reason: "no UI files"}
  ui_loc = count_added_deleted_lines(diff_text, ui_files)
  if len(ui_files) < 2 and ui_loc < 20:
    return {is_ui: false, reason: "below threshold"}

  # 4. diff 키워드 정밀 체크 (4-1 참조)
  if not has_ui_keywords(diff_text, ui_files, token_catalog):
    return {is_ui: false, reason: "no UI keywords in diff (logic-only change)"}

  # 5. 캐시 체크
  current_hash = sha256(sorted(ui_files) + diff_text)
  if cache_match(current_hash):
    return {is_ui: true, cache_hit: true, files: ui_files, loc: ui_loc}

  return {is_ui: true, cache_hit: false, files: ui_files, loc: ui_loc, hash: current_hash}
```

#### 알고리즘 1-1: UI 키워드 정밀 체크

확정 키워드 리스트 (정규식):

```
# React/JSX
className=, style={, styled\., css\(

# Vue
class=, :class=, <style, <template

# CSS 속성 (디자인 의도)
\b(color|background|border|padding|margin|font-size|font-weight|font-family|line-height|width|height|display|position|gap|grid|flex)\b

# 색상값 직접 표기
#[0-9a-fA-F]{3,8}\b, rgba?\(, hsla?\(

# 디자인 토큰 동적 매칭 (token_catalog.tokens.*에서 동적 추출)
{각 토큰명 정규식 OR 결합}
```

판정: diff_text 내 ui_files 라인 중 위 정규식 1개 이상 매치 시 true.

#### 알고리즘 2: orchestrator Phase 5↔7 분기

```
[Phase 5 종료, Evaluator PASS]
  ↓
result = bash scripts/detect-ui-change.sh --post-impl
  ↓
if result.is_ui == false:
  → Phase 7 (보고)
  → log-metric: 없음

if result.cache_hit == true:
  → "[Nova] 이전 감사와 동일한 변경 — ux-audit Lite 생략" (한 줄)
  → log-metric: ui_audit_triggered (cache_hit: true)
  → Phase 7

if --no-ux-audit OR config.auto.uiAudit == false:
  → log-metric: ui_audit_opt_out (reason: "flag" or "config")
  → Phase 7

# 사전 고지
if .nova/ui-state.json.first_ui_audit_shown == false:
  → 자세한 안내 출력 (B-6 첫 트리거 템플릿)
  → ui-state.first_ui_audit_shown = true
else:
  → 한 줄 안내 출력

# ux-audit Lite 실행 (Newcomer + Accessibility + Cognitive Load 3인)
audit_result = invoke_ux_audit_lite(target=result.files)
  ↓
log-metric: ui_audit_completed (critical, high, medium, low, duration_ms)
update .nova/last-audit.json (hash, ts, result, files, stats)

if audit_result.critical >= 1 AND config.auto.uiAuditBlockOnCritical == true:
  → 커밋 차단, 사용자에게 Critical 목록 보고
  → 수정 옵션 제시 (재시도 / --no-ux-audit / 수동 fix)
else:
  → Phase 7 (보고에 audit 결과 통합)
```

#### 알고리즘 3: 디자인 시스템 자동 감지 (`detect-design-system.sh`)

```
priority order:
  1. tailwind.config.{ts,js,mjs,cjs} → Tailwind preset 추출
  2. theme.{ts,tsx,js} 파일 (root, src/, app/) → export 객체 파싱
  3. *.css에 :root { --token-name: ... } → CSS 변수 추출
  4. design-tokens/*.{json,ts,js} → 직접 토큰 정의
  5. packages/*/tokens/, packages/design-system/ → monorepo 케이스

결과:
  - 1개 이상 발견 → tokenCatalog 생성, sources에 모두 기록
  - 0개 → {detected: false}
  - 여러 개 발견 시 우선순위는 발견 순(1→5), 토큰명 충돌 시 첫 발견 우선
```

#### 알고리즘 4: Cognitive Load 평가자 프롬프트 (강화 버전)

기존 10개 항목 뒤에 11~12 추가:

```
[디자인 시스템 정합 — 인지 부하 관점]
11. 같은 의미의 UI(에러/성공/경고/로딩)가 화면마다 다른 색·폰트로 표시되는가?
    → 사용자가 학습한 시각 패턴을 깨면 매번 의미를 재해석해야 함 (인지 부하 ↑)

12. 디자인 토큰을 거치지 않은 하드코딩(색상·spacing·font-size)이 인지 일관성을 깨는가?
    → 같은 의미인데 미세하게 다른 값 = 사용자가 "다른 것"으로 인식 → 학습 비용 증가
    → ★ 디자인 시스템이 정의되지 않은 프로젝트에서는 이 항목을 건너뜁니다.

[디자인 항목 출력 제한]
- 위 11~12 항목에서 발견한 이슈는 최대 3건까지만 보고하세요.
- 전체 출력 8건 제한은 그대로 유지합니다.
```

B 비활성화 처리: orchestrator가 `tokenCatalog.detected == false`면 평가자 프롬프트에 다음 1줄 prepend:

```
[Context Override] 이 프로젝트에는 디자인 시스템 정의가 없습니다. 항목 12는 평가에서 제외하고, 보고서 끝에 "디자인 시스템 정의 없음 — 토큰 검증 스킵" 1줄을 표기하세요.
```

#### 알고리즘 5: 평가자 출력 서브 제한 (3건 강제)

1차 방어: 프롬프트에 명시 ("최대 3건")
2차 방어: 평가자 출력 후처리 — 디자인 항목(11/12 번호)을 필터링, 4번째 이상은 잘라냄
3차 방어: 자른 경우 보고서에 "(디자인 항목 N건 중 3건만 표시)" 안내

### 에러 처리

| 시나리오 | 대응 |
|---------|------|
| `git diff` 실패 (git 저장소 아님) | UI 감지 스킵, 로그만 남김. orchestrator는 정상 진행 |
| `nova-config.json` 파싱 실패 | 기본값 사용, "[Nova] config 파싱 실패 — 기본값 적용" 경고 1줄 |
| `detect-ui-change.sh` 실행 실패 | UI 감지 스킵 (안전 우선), `metrics.jsonl`에 `event: detect_error` 기록 |
| `.nova/` 디렉토리 쓰기 실패 (권한) | 메트릭/캐시 스킵, audit은 정상 실행 |
| `metrics.jsonl` 회전 실패 | 다음 호출에서 재시도, 실패 영구화 시 새 이름으로 회피 |
| ux-audit Lite 자체 실패 (모델 에러 등) | 1회 재시도, 재실패 시 "감사 실패 — 수동 검토 권장" 경고 + Phase 7 진행 |
| 디자인 시스템 감지 false positive (잘못 파싱) | 평가자가 토큰 카탈로그 신뢰도 의심 시 Read 도구로 재검증 |
| Critical 차단 후 사용자가 즉시 재시도 | 같은 hash 캐시는 여전히 PASS로 남아있어 무한 루프 안 됨. last-audit.result가 FAIL이면 캐시 무효화 |

---

## Sprint Contract (스프린트별 검증 계약)

### 스프린트별 Done 조건

| Sprint | Done 조건 | 검증 방법 | 검증 명령 | 우선순위 |
|--------|----------|----------|----------|---------|
| A | Cognitive Load 평가자가 11/12 항목을 출력에 포함한다 | dry-run 보고서에서 항목 11/12 키워드 grep | `bash tests/test-scripts.sh && grep -E "디자인 시스템 정합\|학습한 시각 패턴" /tmp/nova-uxaudit-dry.txt` | Critical |
| A | 디자인 시스템 미정의 프로젝트에서 항목 12가 자동 제외되고 1줄 안내가 출력된다 | dummy 프로젝트에 tailwind/theme 없음 → 보고서 끝줄 검증 | `cd /tmp/no-design-fixture && /nova:ux-audit \| grep "디자인 시스템 정의 없음"` | Critical |
| A | SKILL.md와 commands/ux-audit.md의 평가자 섹션이 동기화되어 있다 | 자동 동기화 테스트 | `bash tests/test-scripts.sh -- --filter ux-audit-sync` | Critical |
| A | 디자인 항목(11/12) 출력이 보고서당 3건 이하다 | dry-run 보고서 파싱 | `python3 scripts/test/count-design-items.py /tmp/nova-uxaudit-dry.txt` | Nice-to-have |
| A | 평가자 전체 출력이 8건 제한을 초과하지 않는다 (기존 보장 회귀) | dry-run 보고서 파싱 | `python3 scripts/test/count-total-items.py` | Critical |
| B | UI 파일 단독 변경(예: 1개 .tsx, 30 LoC)에 대해 ux-audit Lite가 자동 호출된다 | react-component fixture에서 dry-run | `cd fixtures/react-component && /nova:auto "Button 색상 변경" --dry-run \| grep "ux-audit Lite"` | Critical |
| B | 백엔드 단독 변경(.py, .go 등)에 대해 ux-audit Lite가 호출되지 않는다 | backend-only fixture | `cd fixtures/backend-only && /nova:auto "API 추가" --dry-run \| grep -v "ux-audit"` | Critical |
| B | UI 파일이지만 순수 로직만 수정(useEffect만) → 키워드 체크에서 스킵 | logic-only fixture | `cd fixtures/logic-only && /nova:auto "..." --dry-run \| grep "no UI keywords"` | Critical |
| B | `--no-ux-audit` 플래그로 1회 비활성, opt-out 메트릭 기록 | flag 사용 후 metrics.jsonl 검증 | `/nova:auto "UI 작업" --no-ux-audit && tail -1 .nova/metrics.jsonl \| grep '"reason":"flag"'` | Critical |
| B | `nova-config.json`의 `auto.uiAudit: false`로 영구 비활성, opt-out 메트릭 기록 | config 설정 후 자동 검증 | `echo '{"auto":{"uiAudit":false}}' > nova-config.json && /nova:auto "UI" && tail -1 .nova/metrics.jsonl \| grep '"reason":"config"'` | Critical |
| B | 첫 트리거에서 자세한 안내, 두 번째 트리거에서 한 줄 안내 | 연속 호출 출력 비교 | `bash tests/test-ui-audit-notice.sh` | Critical |
| B | 동일 변경 재호출 시 캐시 hit으로 ux-audit 생략 | hash 충돌 fixture | `bash tests/test-cache-hit.sh` | Critical |
| B | Critical ≥ 1 발견 시 커밋이 차단된다 | Critical 유발 fixture | `cd fixtures/critical-violation && /nova:auto "..." ; echo $? \| grep -v 0` | Critical |
| B | metrics.jsonl이 1000줄 초과 시 회전된다 | 시뮬레이션 | `bash tests/test-metrics-rotation.sh` | Nice-to-have |
| B | monorepo 경로(packages/*/src/)에서 UI 감지가 동작한다 | monorepo fixture | `cd fixtures/monorepo && /nova:auto "..." \| grep "ux-audit Lite"` | Critical |
| B | CSS-in-JS(.ts에 styled-components import)가 UI 파일로 승격된다 | css-in-js fixture | `cd fixtures/css-in-js && /nova:auto "..." \| grep "ux-audit Lite"` | Critical |

### 관통 검증 조건 (End-to-End)

| # | 시작점 (사용자 행동) | 종착점 (결과 확인) | 우선순위 |
|---|---------------------|-------------------|---------|
| 1 | `cd fixtures/react-component && /nova:auto "Button에 hover 효과 추가"` 실행 | Phase 5 PASS 후 ux-audit Lite 자동 실행, 결과가 Phase 7 보고에 통합, NOVA-STATE Last Activity에 "UI 감지 → ux-audit Lite PASS" 기록 | Critical |
| 2 | 동일 변경으로 `/nova:auto` 재실행 | "이전 감사와 동일한 변경" 한 줄 + ux-audit 생략 + metrics.jsonl에 cache_hit:true 기록 | Critical |
| 3 | `nova-config.json` 미존재 + 디자인 시스템 미정의 프로젝트에서 UI 변경 | 기본값으로 동작, 항목 12 자동 비활성, 보고서에 "디자인 시스템 정의 없음" 1줄 | Critical |
| 4 | Cognitive Load 평가자가 디자인 일관성 위반을 감지 | 보고서 우선순위 표에 "출처: 평가자 3 (Cognitive Load)" + 디자인 항목 표시 | Critical |
| 5 | `--no-ux-audit` 사용 → metrics 기록 → 다음 evolve --scan 시 opt-out율 참조 가능 | metrics.jsonl 1줄 추가 + 향후 evolve 입력으로 사용 가능 | Critical |

### 역방향 검증 체크리스트

- [x] Plan의 5가지 MECE 문제 영역(품질 검증/환경 인식/협업 핸드오프/진화 메트릭/추가 금지)이 모두 설계에 매핑됨
- [x] X-Verification 합의 4개(오탐 필터/사전 고지/A 정합/진화 메트릭) 모두 설계에 반영
- [x] X-Verification 갈림 2개(우선순위/B 정체성) 해결안 설계에 반영
- [x] 비목표(ui-build/figma 가이드/6번째 평가자) 명시적으로 제외
- [x] 신규 슬래시 커맨드 0개 (명령은 기존 /nova:auto, /nova:ux-audit만 사용)
- [x] 평가자 5인 유지 (항목 추가만)
- [x] session-start.sh additionalContext 변경 없음 (1200자 제약 보존)
- [x] ux-audit 8건 제한 유지 (디자인 항목 3건 서브 제한 추가)
- [x] 누락 엣지 케이스: 빈 git 저장소, .nova/ 권한 부재, config 파싱 실패, ux-audit 모델 에러 모두 에러 처리 섹션에 기록

### 평가 기준

- **기능**: Sprint Contract의 Critical 16건 전원 PASS
- **설계 품질**:
  - 휴리스틱이 셸 스크립트로 분리되어 LLM 변동성 없음 (deterministic)
  - 헬퍼 스크립트가 단일 책임 (detect-ui-change / detect-design-system / log-metric)
  - nova-config.json 스키마가 향후 확장 가능 (uiAuditMode "lite" → "full" 추가 여지)
- **단순성**:
  - 신규 슬래시 커맨드 0개 ✓
  - 신규 스킬 0개 ✓
  - 신규 평가자 0개 (항목만 추가) ✓
  - 신규 헬퍼 스크립트 3개(detect-ui-change, detect-design-system, log-metric) — 단일 책임으로 분리, 각 50줄 이내 목표

---

## 파일 변경 정정 (Plan에서 6파일 → 실제 8파일)

Plan에서 commands/auto.md를 변경 대상으로 명시했으나, 실제 디스패처(15줄)라 변경 없음. 대신 다음으로 정정:

### Sprint A 파일 (4 → 4, 변경 없음)
1. `skills/ux-audit/SKILL.md` — Cognitive Load 평가자 항목 11/12 + Phase 1 디자인 시스템 감지
2. `commands/ux-audit.md` — 동일 동기화
3. `tests/test-scripts.sh` — 항목 11/12 + 디자인 시스템 미정의 케이스
4. `README.md`, `README.ko.md` — AUTO-GEN (자동)

### Sprint B 파일 (6 → 8, 정정)
1. ~~`commands/auto.md`~~ → **변경 없음** (디스패처)
2. **`skills/orchestrator/SKILL.md`** — Phase 1/5/7에 UI 감지 분기 + ux-audit Lite 호출
3. **`scripts/detect-ui-change.sh`** (신규) — 휴리스틱 헬퍼
4. **`scripts/detect-design-system.sh`** (신규) — 디자인 시스템 자동 감지
5. **`scripts/log-metric.sh`** (신규) — 메트릭 jsonl 로깅
6. `tests/test-scripts.sh` — Sprint A에서 이미 수정. Sprint B에서 추가
7. `tests/test-ui-audit-notice.sh` (신규) — 첫 트리거/이후 트리거 검증
8. `tests/test-cache-hit.sh` (신규) — 캐시 hit 검증
9. `.nova/.gitignore` (신규, 자동 생성) — `metrics*.jsonl`, `last-audit.json`, `ui-state.json` 제외
10. `NOVA-STATE.md` — 갱신 형식만 (코드 변경 0)
11. `README.md`, `README.ko.md` — AUTO-GEN

→ **Sprint B 실제 파일: 8개** (테스트 fixture 별도 카운트 제외 시).
→ Plan 복잡도 재평가: Sprint B 단독 8파일이라 **복잡** 등급. 단, 8파일 중 3개는 신규 스크립트(단일 책임, 50줄 이내), 3개는 신규 테스트(독립 검증), 2개는 SKILL.md 1개 + AUTO-GEN. **본질적 복잡도는 보통**으로 유지 가능.

→ **Sprint B를 추가 분할할 필요는 없음**. 신규 스크립트 3종은 독립 가능하나 orchestrator와 강결합되어 한 사이클로 검증되어야 함.

---

## 다음 단계

Sprint A 구현부터 진입. `/nova:run` 호출 시 본 Design 문서가 Generator-Evaluator 계약의 기준이 됨.

**Sprint A 시작 전 확인 사항**:
- 본 Design의 Sprint Contract 표(Critical 16건)에 추가/수정 필요 여부
- 헬퍼 스크립트 위치 `scripts/` 디렉토리 채택 (기존 `scripts/bump-version.sh`, `scripts/release.sh`와 동거)

**Sprint B 시작 전 확인 사항**:
- fixtures/ 디렉토리 — Nova 레포 내 `tests/fixtures/`에 익명 fixture 6개 자체 생성 (외부 프로젝트 의존 0):
  - `react-component/` (단일 .tsx + LoC ≥ 20)
  - `backend-only/` (백엔드만 변경, UI 0)
  - `logic-only/` (.tsx인데 useEffect만 변경)
  - `monorepo/` (packages/*/src/ 구조)
  - `css-in-js/` (.ts에 styled-components import)
  - `critical-violation/` (Critical 유발 코드)
