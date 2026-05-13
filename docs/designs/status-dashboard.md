---
title: Status Dashboard (`/nova:status` — 현황 + drift)
sprint: S1 (Design)
created: 2026-05-13
related:
  - docs/plans/status-dashboard.md
  - docs/guides/status-dashboard.md
  - skills/status-dashboard/SKILL.md
  - commands/status.md
  - scripts/build-status.sh
  - scripts/render-status.sh
  - templates/status-dashboard/index.html
---

# Status Dashboard (`/nova:status` — 현황 + drift)

본 문서는 Sprint S1 기준의 **설계 정본**이다.
구현 전 단계이므로 코드 라인 근거 대신 인터페이스/스키마/매트릭스를 단일 진실원으로 둔다.
Sprint S2~S3 구현은 본 문서의 계약을 surgical하게 따른다.

---

## 1) Context

### 1.1 왜 이 게이트가 필요한가

AI 에이전트 위임 빈도 증가로 **"원래 계획(roadmap intent) vs 실제 진행(git/code)"** 간 drift가 발생한다.
기존 Nova 게이트는 코드 정합성 + 시각 의도까지 보지만 **로드맵 의도** 차원은 빠져 있다.
`/nova:status`는 이 빈자리를 채운다.

근거:
- `docs/plans/status-dashboard.md` Context
- `docs/verifications/2026-05-13-맥락-Claude-Code-Codex-같은-AI-에이전트에게-작업을-위.md` (멀티 AI 자문, 합의 95%)

### 1.2 Sprint 분할 맥락

| Sprint | 핵심 | 산출 |
|--------|------|-----|
| S1 | Design + 스키마 + 템플릿 | 본 문서 + HTML 템플릿 + JSON 인터페이스 freeze |
| S2 | 파서 + 데이터 빌더 | `build-status.sh` → JSON |
| S3 | 렌더 + 카드 + drift | `render-status.sh` → HTML |
| S4 | 통합 + 가드 + 가이드 + 릴리스 | 커맨드/스킬/훅/테스트/가이드 |

본 문서는 S1 정본이다.

---

## 2) Problem

### 2.1 가시화 공백

Phase 시계열, 현재 Sprint, 그룹별 진행률을 **한 화면**에 결정론적으로 볼 수단이 없다.

### 2.2 SOT sync drift

노션/wiki/README의 진행률은 손으로 입력 → 실제 코드와 어긋난다.
별도 metadata 파일을 또 만들면 sync 부담 재현 (3 SOT 문제).

### 2.3 결정론 부재

기존 마크다운 휴리스틱은 60~70% 정확도 (선행 구현 실측). 95%+ 필요.

### 2.4 환경 제약

stand-alone HTML 1개, 외부 의존성 0, `file://` 작동 — 모든 사용자 보장.

---

## 3) Architecture Overview

### 3.1 4단 파이프라인

```
[1] discover    plan frontmatter 발견 + YAML 파싱
       ↓
[2] build       fast-glob count + git log path 매칭 → StatusData JSON
       ↓
[3] render      StatusData → HTML (template + inline JSON)
       ↓
[4] write       .nova/status/index.html + .nova/status/data.json
```

### 3.2 진입점

| 진입점 | 역할 | 호출 위치 |
|--------|-----|----------|
| `/nova:status` 슬래시 커맨드 | 전체 4단 실행 | `commands/status.md` |
| `scripts/build-status.sh` | [1]+[2] 단독 실행 가능 (`--json` 출력) | bash · CI 통합 |
| `scripts/render-status.sh` | [3]+[4] 단독 실행 가능 (`--data <path>`) | bash · 임의 데이터 렌더 |
| Skill `status-dashboard` | `/nova:status` 자연어 위임 시 발화 | 스킬 description MUST TRIGGER |

### 3.3 단일 책임 원칙

- `build`: 데이터 수집·계산. HTML 모름.
- `render`: 데이터 시각화. git 모름.
- 둘은 **JSON 인터페이스로만 연결** (§5 참조).

---

## 4) Data Contract — plan frontmatter v1.0

### 4.1 위치

`docs/plans/<slug>.md` 의 YAML frontmatter.
별도 metadata 파일은 만들지 않는다 (SOT 단일화 원칙).

### 4.2 스키마 (Astro Content Collections + Zod 스타일)

```yaml
---
# === 메타 ===
plan_id: string         # 필수. URL-safe slug. drift commit tag와 매칭됨
title: string           # 필수. 사람 친화적 제목
created: string         # ISO 8601 date

# === 현재 위치 (커서) ===
current_phase: string   # phases[].id 중 하나. 없으면 첫 in_progress 자동 선택
current_sprint: string  # 선택. sprints[current_phase][].id 중 하나

# === Phase 시계열 ===
phases:
  - id: string          # 필수. 짧은 ID (P1, M0, ...)
    title: string       # 필수
    status: enum        # 필수. done | in_progress | pending | blocked
    summary: string     # 선택. 부제

# === Sprint (phase 안 세부 작업) ===
sprints:
  <phase_id>:           # phases[].id 와 매칭
    - id: string        # 필수. C1, S1, ...
      title: string     # 필수
      status: enum      # done | in_progress | pending | blocked

# === Group (화면/기능 단위 진행률) ===
groups:
  - id: string          # 필수. H1, ws, ...
    title: string       # 필수
    target: number      # 필수 양의 정수. 목표 카운트 (예: "6개 화면")
    paths: [string]     # 필수. fast-glob 패턴 배열 (예: ['app/h1/**/page.tsx'])
    count_strategy: enum # 선택. files | screens | manual. 기본 files
                         #   files: paths 매칭 파일 수
                         #   screens: paths 매칭 Next.js page.tsx 수 (alias)
                         #   manual: status_field 필드를 사람이 직접 갱신

# === Goals (drift 추적 단위) ===
goals:
  - id: string          # 필수. G1, G2, ...
    title: string       # 필수
    paths: [string]     # 필수. drift 매칭용 glob
    status: enum        # done | in_progress | pending | blocked
    needs_approval: bool # 선택. 외부 승인 대기 표시
---
```

### 4.3 검증 규칙 (build 시점 차단)

| 규칙 | 위반 시 동작 |
|------|------------|
| `plan_id` 누락 | FAIL — minimal mode 진입 (제목 + Last Activity body만) |
| `phases[]` 비어있음 | WARN — Phase bar 0단 표시 |
| `current_phase` 미선언 + `in_progress` 없음 | WARN — Sprint 리스트 빈 카드 |
| `groups[].target` ≤ 0 | FAIL — 해당 group 진행률 bar 표시 X (false 0% 방지) |
| `groups[].paths` 비어있음 | FAIL — 해당 group skip |
| enum 값이 정의 밖 (예: status: doing) | FAIL — pending으로 fallback + WARN |
| 같은 id 중복 (phases[].id 등) | FAIL — 첫 번째만 사용 + WARN |

### 4.4 예시 (이미지 1·2 SOT 재현)

```yaml
---
plan_id: ai-audit-trail
title: AI Audit Trail SaaS for Korean SMB
created: 2026-04-01
current_phase: P3
current_sprint: C2
phases:
  - {id: P1, title: 시안→코드, status: done, summary: "m2 inside-app 28 + m2.5 외부 14 + UX Audit S1~S3"}
  - {id: P2, title: M0 부분 PASS, status: done, summary: "S1 회수·S1.5 hash·S1.6 baseline·S1.7·H2-b"}
  - {id: P3, title: Local Dogfooding Ready, status: in_progress, summary: 실사용 수준 도달}
  - {id: P4, title: M0/S2 자기 캡처 1주 측정 (재개), status: pending}
  - {id: P5, title: M0/S3 잔여 가설, status: pending, summary: "H1 1분 회상·H2-a 매칭·H3 RCA"}
  - {id: P6, title: M0/S4 PRD §1.1 정정 + M1 진입 결정, status: pending}
  - {id: P7, title: M1 Foundation, status: pending, summary: "Stack 결정·multi-tenant"}
sprints:
  P3:
    - {id: C1, title: 측정 환경 자동 기동 + dev/status 메뉴, status: done}
    - {id: C2, title: Intent 가공 — 단편 → 의도 한 줄, status: in_progress}
    - {id: C3, title: Audit summary + WorkPacket 의도 변환, status: pending}
    - {id: C4, title: Risk 세션 fan-out, status: pending}
    - {id: C5, title: SessionDetail 실 데이터 어댑터 (25→15+ fields), status: pending}
    - {id: C6, title: Repo 파서 정합 100%, status: pending}
    - {id: C7, title: Incident·Reviewer 깊은 화면 jargon 평이화, status: pending}
    - {id: C8, title: 1주 dogfooding 검증, status: pending}
groups:
  - {id: H1, title: 회상 흐름, target: 6, paths: ['app/h1/**/page.tsx']}
  - {id: H2, title: 매칭, target: 5, paths: ['app/h2/**/page.tsx']}
  - {id: H3, title: RCA, target: 5, paths: ['app/h3/**/page.tsx']}
  - {id: H4, title: 분석, target: 5, paths: ['app/h4/**/page.tsx']}
  - {id: ws, title: 워크스페이스, target: 3, paths: ['app/ws/**/page.tsx']}
  - {id: settings, title: 설정, target: 4, paths: ['app/settings/**/page.tsx']}
  - {id: public, title: 공개, target: 14, paths: ['app/public/**/page.tsx']}
goals:
  - {id: G-Intent, title: Intent 가공, paths: ['app/audit/intent/**'], status: in_progress}
  - {id: G-Summary, title: Audit summary, paths: ['app/audit/summary/**'], status: pending}
---
```

이 입력이 이미지 1·2와 동일 출력을 만들면 S3 동일성 검증 PASS.

---

## 5) Output Contract — StatusData JSON v1.0

`build-status.sh` 표준 출력. `render-status.sh` 입력. **두 스크립트의 유일한 인터페이스**.

### 5.1 위치

- 표준 출력: stdout (1줄 JSON)
- 파일 출력: `.nova/status/data.json` (pretty)

### 5.2 필드 정의

| 필드 | 타입 | 설명 |
|------|------|------|
| `$schema` | string | `"https://nova/status-data/v1.0"` 고정 |
| `version` | string | `"1.0"` 고정 |
| `generated_at` | string (ISO 8601) | 생성 시각 |
| `plan` | object | plan_id / title / plan_path |
| `cursor` | object | current_phase / current_sprint (resolve된 값) |
| `phases` | array | frontmatter 그대로 + `progress` 계산값 추가 |
| `sprints` | object | frontmatter 그대로 |
| `groups` | array | frontmatter + `count` (현재 카운트) + `percent` (count/target) |
| `goals` | array | frontmatter 그대로 |
| `screens_total` | object | `{done: N, total: M}` — 모든 group 합산 |
| `drift` | object | drift 분석 결과 (§6) |
| `warnings` | array | 검증 규칙 위반 메시지 (사용자에게 카드로 표시) |

### 5.3 예시 (이미지 2 재현 입력)

```json
{
  "$schema": "https://nova/status-data/v1.0",
  "version": "1.0",
  "generated_at": "2026-05-13T14:30:00+09:00",
  "plan": {
    "plan_id": "ai-audit-trail",
    "title": "AI Audit Trail SaaS for Korean SMB",
    "plan_path": "docs/plans/ai-audit-trail.md"
  },
  "cursor": {
    "current_phase": "P3",
    "current_sprint": "C2"
  },
  "phases": [
    {"id": "P1", "title": "시안→코드", "status": "done", "progress": 100},
    {"id": "P2", "title": "M0 부분 PASS", "status": "done", "progress": 100},
    {"id": "P3", "title": "Local Dogfooding Ready", "status": "in_progress", "progress": 12},
    {"id": "P4", "title": "M0/S2 자기 캡처 1주 측정 (재개)", "status": "pending", "progress": 0}
  ],
  "sprints": {
    "P3": [
      {"id": "C1", "title": "측정 환경 자동 기동", "status": "done"},
      {"id": "C2", "title": "Intent 가공", "status": "in_progress"}
    ]
  },
  "groups": [
    {"id": "H1", "title": "회상 흐름", "target": 6, "count": 6, "percent": 100},
    {"id": "H2", "title": "매칭", "target": 5, "count": 5, "percent": 100},
    {"id": "H3", "title": "RCA", "target": 5, "count": 5, "percent": 100},
    {"id": "H4", "title": "분석", "target": 5, "count": 5, "percent": 100},
    {"id": "ws", "title": "워크스페이스", "target": 3, "count": 3, "percent": 100},
    {"id": "settings", "title": "설정", "target": 4, "count": 4, "percent": 100},
    {"id": "public", "title": "공개", "target": 14, "count": 2, "percent": 14}
  ],
  "screens_total": {"done": 30, "total": 42},
  "drift": {
    "since": "2026-05-06",
    "commits_total": 23,
    "buckets": {
      "aligned": 14,
      "drifted": 2,
      "unspecced": 0,
      "unverifiable": 1,
      "conflict": 0,
      "tag_missing": 6
    },
    "drift_percent": 13,
    "verdict": "green",
    "drifted_commits": [
      {"sha": "abc1234", "subject": "fix: 결제 검증", "goal_declared": "G-Intent", "paths_actual": ["src/payment/checkout.ts"]}
    ]
  },
  "warnings": []
}
```

### 5.4 phases[].progress 계산식

```
phase.progress =
  if status == done    → 100
  elif status == pending → 0
  elif status == blocked → 50 (회색, 알람 별도)
  elif status == in_progress:
    if sprints[phase.id] 존재:
      done_count / total_count * 100
    else:
      0  (Sprint 미정의 시 진행률 unknown)
```

### 5.5 결정론 보장 (build 재실행 byte-identical)

- `generated_at` 외 모든 필드는 동일 입력 → byte-identical
- 회귀 테스트: 동일 fixture 10회 build → `generated_at` 제외 후 diff 0

---

## 6) Drift Detection — 5분류 매트릭스

### 6.1 입력

- `goals[]` (frontmatter)
- `git log --since=<since> --name-only --pretty="%H%n%s%n%b%n---"` (default since: 7일 전)

### 6.2 commit tag 정규식

```
Plan: <plan_id>       (또는 plan_id 생략 시 같은 디렉토리 plan 자동 매칭)
Goal: <goal_id>       (선택, goal 단위 추적)
```

정규식 (한 줄당 매칭):
```
^Plan:\s*([A-Za-z0-9_\-]+)\s*$
^Goal:\s*([A-Za-z0-9_\-]+)\s*$
```

### 6.3 분류 의사코드

```python
for commit in commits:
    plan_tag = extract_plan_tag(commit.body)
    goal_tag = extract_goal_tag(commit.body)
    paths = commit.changed_files

    if plan_tag is None:
        bucket = "tag_missing"   # drift 아님, 별도 카운트
        continue

    if plan_tag != current_plan_id:
        bucket = "tag_missing"   # 다른 plan
        continue

    if goal_tag is None:
        # plan은 맞지만 goal 미선언
        if any(p matches any goal.paths for p in paths):
            bucket = "aligned"   # paths로 추정 가능
        else:
            bucket = "unspecced"
        continue

    goal = goals[goal_tag]
    if goal is None:
        bucket = "conflict"      # 존재하지 않는 goal 참조
        continue

    matched_goals = [g for g in goals if any(p matches g.paths for p in paths)]

    if len(matched_goals) == 0:
        if paths are test/docs/non-functional:
            bucket = "unverifiable"
        else:
            bucket = "drifted"
    elif len(matched_goals) == 1 and matched_goals[0].id == goal_tag:
        bucket = "aligned"
    elif goal_tag in [g.id for g in matched_goals]:
        bucket = "aligned"       # 여러 goal 매칭하지만 선언된 goal 포함
    else:
        bucket = "drifted"       # 선언과 실제 경로 불일치
```

### 6.4 verdict 임계

```
drift_percent = (drifted + conflict) / (commits_total - tag_missing) * 100

verdict =
  green   if drift_percent < 30
  amber   if 30 <= drift_percent < 70
  red     if drift_percent >= 70
```

`tag_missing`은 분모에서 제외 (drift 신호 아님, 별도 카드 표시).

### 6.5 false positive 대응

| 케이스 | 대응 |
|--------|-----|
| test/docs/config 수정 | `unverifiable` 버킷 |
| 메인 plan 외 작업 (`Plan: <other>`) | `tag_missing` 동치 |
| 동일 commit이 여러 goal paths 매칭 | 선언된 goal 포함 시 aligned, 미포함 시 drifted |
| merge commit | --no-merges로 제외 (기본) |
| 빈 commit (chore: 빈) | 파일 변경 0이면 분석 skip |

---

## 7) HTML Template 명세

### 7.1 파일 위치

`templates/status-dashboard/index.html` — Sprint S1 산출.
`scripts/render-status.sh`가 이 파일을 읽고 inline JSON 치환.

### 7.2 외부 의존성

| 리소스 | 출처 | 비고 |
|--------|-----|------|
| Tailwind | `<script src="https://cdn.tailwindcss.com">` | Play CDN, file:// 작동 |
| 폰트 | 시스템 폰트 stack (`-apple-system, ...`) | 외부 fetch 0 |
| 데이터 | `<script>const DATA = {/* injected */};</script>` | inline JSON 임베드 |

**외부 JSON fetch / XHR / WebSocket 0건** — file:// CORS 차단 회피.

### 7.3 레이아웃 (top → bottom)

```
┌────────────────────────────────────────────────────────────┐
│ <header> Plan 제목 + 메타 (owner, last commit, generated)  │
├────────────────────────────────────────────────────────────┤
│ <section id="phase-bar">                                  │
│   Phase 시계열 7단 progress bar (이미지 1 상단 동일)         │
│   - 점·선·체크 + Phase 제목 + summary                       │
├────────────────────────────────────────────────────────────┤
│ <section id="screens-total">                              │
│   좌측: 큰 숫자 "30 / 42 화면 완료"                          │
│   우측: 그룹별 진행률 bar grid (이미지 2 동일)               │
├────────────────────────────────────────────────────────────┤
│ <section id="sprint-list">                                │
│   현재 Phase의 Sprint 리스트 (이미지 1 하단 동일)            │
│   - 체크 / 화살표 / 빈원 + 제목 + 상태 텍스트                │
├────────────────────────────────────────────────────────────┤
│ <section id="drift-card">  (drift_percent > 0 일 때만)     │
│   verdict 배지 (green/amber/red)                          │
│   5분류 버킷 카운트 + drifted commits 표                    │
├────────────────────────────────────────────────────────────┤
│ <section id="warnings">  (warnings.length > 0 일 때만)     │
│   검증 위반 사항 (스키마 미준수, target 누락 등)             │
└────────────────────────────────────────────────────────────┘
```

### 7.4 색상 토큰

| 토큰 | 값 | 사용처 |
|------|-----|-------|
| `--ok` | `#16a34a` (green-600) | done 체크, aligned 배지, green verdict |
| `--progress` | `#2563eb` (blue-600) | in_progress 화살표, progress bar fill |
| `--pending` | `#9ca3af` (gray-400) | pending 빈원, 빈 bar |
| `--warn` | `#f59e0b` (amber-500) | amber verdict, drifted 배지 |
| `--danger` | `#dc2626` (red-600) | red verdict, blocked, conflict |
| `--text` | `#111827` (gray-900) | 본문 |
| `--text-mute` | `#6b7280` (gray-500) | summary, 메타 |

토스식 UX 원칙:
- 흰 배경 + 충분한 여백 + 단색 강조
- 그림자 최소, 라운드 모서리 8~12px
- 진행률은 숫자 + 막대 동시 표시

### 7.5 데스크탑 전용

메모리 `feedback_no_mobile_responsive.md` — 반응형 작업 없음. min-width: 1024px 고정 레이아웃.

---

## 8) Graceful Degradation

| 입력 결함 | 동작 | 표시 |
|----------|------|-----|
| frontmatter 0 | minimal mode | 제목 + body 첫 200자 |
| `plan_id` 누락 | minimal mode | warning 카드 |
| `phases[]` 비어있음 | Phase bar 숨김 | 다른 섹션은 정상 |
| `sprints` 비어있음 | Sprint 리스트 숨김 | 다른 섹션은 정상 |
| `groups[]` 비어있음 | screens-total 숨김 | 다른 섹션은 정상 |
| `groups[].target ≤ 0` | 해당 group 표시 X | warning 카드 |
| `goals[]` 비어있음 | drift 섹션 숨김 | 다른 섹션은 정상 |
| git log 비어있음 | drift 섹션에 "이력 없음" | 차단 X |
| commit tag 0% | tag_missing 100% 카드 + 가이드 링크 | drift verdict는 unknown |
| paths glob 매칭 0 파일 | count: 0 | bar 0% (정직) |

**원칙**: 검증 실패는 **차단 X**, 사용자에게 **warning 카드**로 안내. 도구는 항상 동작해야 한다.

---

## 9) Commit Convention (사용자/AI 협업)

### 9.1 권장 형식

```
<type>(<scope>): <subject>

<body>

Plan: <plan_id>
Goal: <goal_id>
```

예시:
```
feat: drift 5분류 매트릭스 구현

drifted/unspecced/unverifiable/conflict + tag_missing 별도 버킷.
임계 30/70% 기준.

Plan: status-dashboard
Goal: G2
```

### 9.2 CLAUDE.md 룰 1줄 (사용자 프로젝트가 추가)

```markdown
## Commit Convention
- 모든 의도된 작업은 commit 본문에 `Plan: <id>` 명시. goal 단위 추적 시 `Goal: <id>` 추가.
- tag 누락은 차단 안 됨 (Nova는 tag_missing 버킷으로 분리만)
```

### 9.3 AI 에이전트 자동 동참

- 시스템 룰 1줄만으로 Claude/Codex/Cursor가 자동 동참
- 외부 도구 강제 0
- 누락 시 차단 0 (soft 강제)

### 9.4 Nova 자체 적용

본 status-dashboard 작업 commit부터 `Plan: status-dashboard`를 본문에 포함하여 dogfooding 시작.

---

## 10) 산출물 매핑 (Sprint S1)

| 설계 항목 | 산출물 | 비고 |
|----------|--------|-----|
| frontmatter 스키마 freeze | 본 문서 §4 | Sprint S2 build의 검증 기준 |
| StatusData JSON 인터페이스 | 본 문서 §5 | Sprint S2 build 출력 + Sprint S3 render 입력 |
| Drift 5분류 매트릭스 | 본 문서 §6 | Sprint S2 분석 로직 명세 |
| HTML 템플릿 레이아웃 | 본 문서 §7 + `templates/status-dashboard/index.html` | Sprint S3 render 베이스 |
| Graceful degradation 룰 | 본 문서 §8 | 모든 Sprint 공통 |
| Commit convention | 본 문서 §9 | Nova 자체 dogfooding 즉시 적용 |

Sprint S2~S3은 본 문서의 §4/§5/§6/§7 계약을 **글자 그대로** 따른다.
계약 변경이 필요하면 본 문서를 먼저 수정하고 PR 단위로 적용.

---

## 11) Out of Scope (S1~S4 범위 외)

| 항목 | 사유 |
|------|-----|
| 멀티 프로젝트 통합 대시보드 | 후속 — 단일 프로젝트 HTML 우선 안정화 |
| Slack/Discord 알람 | SWK 색채 제거 (메모리 `feedback_nova_universal_plugin.md`) |
| Next.js `app/status/` 자동 생성 | framework-specific 분기 회피 |
| `/nova:reconcile` (drift 자동 수정) | spec-kit-reconcile 영감, 별도 스킬 후보 |
| Linear/Jira 외부 SOT 연동 | 네트워크 의존 — 제약 위반 |
| 모바일 반응형 | 메모리 `feedback_no_mobile_responsive.md` — 데스크탑 전용 |
| 다국어 i18n | v1.0 한국어 고정 (Nova 사용자 다수 한국어) |

---

# Phase 2 — ROADMAP 통합 + init wizard

> Phase 1(§1~§11)은 그대로 유지. 본 섹션은 추가 계약 정의.
> Phase 1과의 호환성: ROADMAP.md 부재 시 §1~§11 동작 100% 유지.

## 12) ROADMAP.md frontmatter v1.0 스키마

### 12.1 위치 + 발견 규칙

- 우선순위: `ROADMAP.md` (루트) → `docs/ROADMAP.md` → `docs/roadmap.md`
- 발견 실패 시 → Phase 1 동작 (단일 plan frontmatter SOT)

### 12.2 스키마

```yaml
---
# === 메타 ===
roadmap_id: string         # 필수. URL-safe slug (project 식별자)
title: string              # 필수
created: string            # 선택. ISO 8601 date

# === 현재 위치 ===
current_phase: string      # 필수. phases[].id 중 하나

# === Phase 시계열 ===
phases:                    # 필수. 1+ entry
  - id: string             # 필수 (P12, M0, Phase-13 등 자유)
    title: string          # 필수
    status: enum           # 필수. done | in_progress | pending | blocked
    summary: string        # 선택
    range_months: integer  # 선택 — "장기 3~6개월" 표시용 (UI 부제)

# === 외부 승인 대기 ===
external_pending:          # 선택. dashboard 카드로 별도 표시
  - id: string             # slug
    title: string
    blocker: string        # "Josh Anthropic Org Admin"
    activation: string     # "env 1~2줄 주입"
    phase: string          # 어느 phase에서 풀려야 하는지 (phases[].id)

# === 참조 ===
links:                     # 선택. UI에 "외부 자산" 카드로
  - {title: string, url: string}
---
```

### 12.3 검증 규칙

| 규칙 | 위반 시 |
|------|--------|
| `roadmap_id` 누락 | FAIL — fallback to Phase 1 (단일 plan 모드) |
| `current_phase` 미선언 + `in_progress` 없음 | WARN — Phase bar 첫 항목 시각만 |
| 같은 phases[].id 중복 | FAIL — 첫 항목만, WARN |
| enum 값 정의 밖 | pending fallback + WARN |
| `external_pending[].phase` 가 phases에 없음 | WARN — phase=null로 표시 |

## 13) 멀티 plan 통합 규칙

### 13.1 plan.md frontmatter 확장 (v1.1)

기존 §4 스키마에 옵션 필드 추가 (Phase 1 호환 — 미선언 시 무영향):

```yaml
---
plan_id: ao-12
parent_phase: P13              # 신규. roadmap.phases[].id 중 하나
sprint_id: AO-12               # 신규. parent_phase 안에서 유니크
title: S2 흡수형 Cost Jump Enrichment
status: in_progress            # 신규 top-level. done|in_progress|pending|blocked
---
```

### 13.2 통합 알고리즘

```python
def integrate(roadmap, plan_files):
    # 1. ROADMAP phases 그대로 사용
    phases = roadmap.phases

    # 2. plan.md 멀티 스캔 → parent_phase로 그룹핑
    sprints = {p.id: [] for p in phases}
    seen_sprint_ids = set()
    warnings = []

    for plan in plan_files:
        if not plan.frontmatter.parent_phase:
            continue  # 단일 plan 모드 (Phase 1) 또는 ROADMAP과 무관

        phase_id = plan.parent_phase
        if phase_id not in sprints:
            warnings.append(f"plan {plan.plan_id} parent_phase={phase_id} not in ROADMAP")
            continue

        sprint_id = plan.sprint_id or plan.plan_id
        if sprint_id in seen_sprint_ids:
            warnings.append(f"duplicate sprint_id {sprint_id} — first wins")
            continue
        seen_sprint_ids.add(sprint_id)

        sprints[phase_id].append({
            "id": sprint_id,
            "title": plan.title,
            "status": plan.status or "pending",
        })

    return phases, sprints, warnings
```

### 13.3 단일 plan 호환 (backward compat)

ROADMAP.md가 있어도 `docs/plans/<single>.md`에 sprints[] 직접 정의되어 있으면 그것이 우선 (해당 plan 내부에서만).
즉 Phase 1 single-plan 사용자가 ROADMAP을 도입하면서도 plan 안 sprints[]를 그대로 사용 가능.

## 14) Stale 검증

### 14.1 stale 조건

ROADMAP.md 또는 그 frontmatter의 신선도 검증.
다음 중 하나라도 해당 시 `stale: true`:

1. ROADMAP.md 마지막 commit 시각이 7일+ 전 (default — `--stale-threshold` 인자로 조정 가능)
2. 최근 7일 git 활동 중 `parent_phase` 매칭률이 `current_phase`와 50% 이상 불일치 (advisory)

### 14.2 측정

```python
def is_stale(roadmap_path, threshold_days=7):
    # git log 마지막 commit 시각
    out = git log -1 --format=%cI -- <roadmap_path>
    last_commit = parse_iso(out)
    age_days = (now() - last_commit).days
    return age_days > threshold_days
```

### 14.3 출력

StatusData JSON에 추가:

```json
"roadmap": {
  "path": "docs/ROADMAP.md",
  "last_commit": "2026-05-06T14:30:00+09:00",
  "age_days": 7,
  "stale": true,
  "stale_reason": "commit 8 days ago > threshold 7"
}
```

### 14.4 시각화

HTML 헤더에 ⚠️ 배지:
```
⚠️ ROADMAP stale — 마지막 commit 8일 전
```
차단 X. 사용자가 ROADMAP.md를 갱신하면 자동 해소.

## 15) init wizard — 3 모드

### 15.1 진입점

```bash
./scripts/render-status.sh --init        # 또는
./scripts/init-roadmap.sh                  # 직접 호출
/nova:status init                          # slash command
```

ROADMAP.md 부재 + 첫 `/nova:status` 호출 시 자동 wizard 안내 (강제 X — `--no-init` 옵션으로 skip).

### 15.2 모드 정의

| 모드 | 입력 | 출력 | 외부 의존 | 소요 |
|------|------|------|----------|------|
| **1. blank** | 없음 | 빈 frontmatter + 본문 placeholder | 0 | 1초 |
| **2. llm** | NOVA-STATE.md + git log 30일 + docs/plans/* frontmatter | LLM 초안 (⚠️ unsure 마커 포함) | Claude Code 세션 모델 (API 키 0) | 1~2분 |
| **3. scan** | docs/plans/*.md frontmatter (parent_phase·sprint_id) | 추출된 phases (parent_phase unique 집합) + sprints | 0 | 5초 |

### 15.3 모드 (2) LLM 동작 (Agent subagent 패턴)

`visual-self-verify.sh`의 Agent subagent 호출 패턴 그대로 차용 (메모리 `feedback_api_key_optional_principle`):

1. 메인 스크립트가 입력 자료 수집 (`.nova/init-wizard-input.json` 임시 파일)
2. Agent(general-purpose) subagent 호출 — prompt에 입력 자료 + ROADMAP frontmatter 스키마 + ⚠️ unsure 룰
3. subagent가 ROADMAP.md 초안 작성 → 사용자에게 `ROADMAP.md.draft`로 표시
4. 사용자 검수 → `mv ROADMAP.md.draft ROADMAP.md` + commit (자동 commit 금지)

### 15.4 ⚠️ unsure 룰 (모드 2)

LLM 추정 신뢰도 낮은 항목:
- phases[].status 추정 불가 → `pending` + `# ⚠️ unsure: 직접 확인` 주석
- external_pending 추정 어려움 → 빈 배열 + 본문 안내
- summary 모호 → 빈 문자열

### 15.5 모드 (3) scan 동작 (결정론)

```python
def scan_mode():
    phases = []
    seen = set()
    for plan in glob('docs/plans/*.md'):
        fm = parse_frontmatter(plan)
        if fm.parent_phase and fm.parent_phase not in seen:
            seen.add(fm.parent_phase)
            phases.append({
                "id": fm.parent_phase,
                "title": fm.parent_phase,  # 사용자가 ROADMAP에서 다듬을 필요 있음
                "status": "in_progress" if any in_progress sprint else "pending",
            })
    return phases
```

모드 (3)는 plan frontmatter v1.1을 이미 사용 중인 프로젝트에 적합.

### 15.6 모드 선택 prompt

```
$ /nova:status init

ROADMAP.md 없음. 어떻게 시작할까요?

  [1] 빈 템플릿        — 1초. 사용자가 손으로 채움. 레거시 docs 0건 참조.
  [2] LLM 자동 초안    — 1~2분. NOVA-STATE + git log + plans 기반. ⚠️ 검수 필수.
  [3] docs/plans 스캔  — 5초. 기존 plan frontmatter에서 추출.

선택 (1/2/3): _
```

### 15.7 commit 정책

자동 commit 0건. 모든 모드는 파일만 생성 + 사용자에게 안내:

```
ROADMAP.md 생성 완료.
검토 후 commit:
  git add ROADMAP.md
  git commit -m "feat: ROADMAP.md initial (status-dashboard Phase 2 SOT)"
```

## 16) Phase 2 산출물 매핑 (Sprint S5)

| 설계 항목 | 산출물 | 비고 |
|----------|--------|-----|
| ROADMAP frontmatter 스키마 v1.0 | 본 문서 §12 | Sprint S6 build의 검증 기준 |
| 멀티 plan 통합 알고리즘 | 본 문서 §13 | Sprint S6 통합 로직 |
| Stale 검증 정책 | 본 문서 §14 | Sprint S6 + Sprint S8 시각 |
| init wizard 3 모드 spec | 본 문서 §15 | Sprint S7 구현 |
| ROADMAP.md fixture | `tests/fixtures/status-dashboard/roadmap-sample.md` | Sprint S6 회귀 입력 |

Sprint S6~S8은 본 문서 §12~§15 계약을 글자 그대로 따른다.

---

# Phase 3 — Plan Frontmatter Auto-Enrich

> Phase 1·2(§1~§16)는 그대로 유지. 본 섹션은 추가 계약 정의.
> 동기: Phase 2 dogfooding 결과 (planreview 51 / swk-gc 13 / spwk-product 6) 모두 `sprints[]` 빈 배열 — plan에 `parent_phase` frontmatter가 없어 통합 그룹핑 불가. 사용자가 수동으로 51개 plan 수정은 비용 부담 ↑.

## 17) enrich-plans — 3 모드

### 17.1 진입점

```bash
./scripts/enrich-plans.sh --dry-run    # default. 변경 0건. <plan>.frontmatter.draft 생성
./scripts/enrich-plans.sh --patch       # unified diff 1개 → git apply -p1 (사용자 명시 적용)
./scripts/enrich-plans.sh --apply       # 원본 직접 prepend (.bak 자동, --force 필요)
```

### 17.2 모드 비교

| 모드 | 변경 대상 | 안전성 | 사용처 |
|------|----------|--------|--------|
| `--dry-run` | 없음 (`docs/plans/<x>.md.frontmatter.draft` 생성) | 🟢 100% | 첫 검수, 51개 plan 일괄 확인 |
| `--patch` | `.nova/enrich-plans.patch` 1개 생성 | 🟢 git 친화 | `git apply -p1 --check` → 적용 |
| `--apply` | 원본 prepend + `.bak` 자동 백업 | 🟡 사용자 명시 | dry-run 검수 통과 후 일괄 적용 |

### 17.3 5중 안전 가드 (모든 모드 공통)

1. **본문 0 byte 변경** — frontmatter 영역만 prepend (정규식 `^---\n` 시작 안 함을 확인 후)
2. **기존 frontmatter 있는 plan은 skip** — `^---\s*\n` 매치 시 그대로 두고 warning
3. **`.bak` 자동 백업** (`--apply` 시) — 손쉬운 복구
4. **batch 단위 (default 10)** — LLM context 폭증 방지 + 진행률 표시
5. **자동 commit 0건** — 모든 모드에서 git 호출 X

### 17.4 ROADMAP 의존성

`enrich-plans`는 **ROADMAP.md frontmatter v1.0이 존재하는 프로젝트**에서만 작동.
- ROADMAP 없으면: "먼저 `init-roadmap.sh` 실행" 안내 후 exit 5
- 이유: `parent_phase` 매핑 SOT가 ROADMAP의 `phases[].id` 집합이어야 결정론 보장

## 18) Agent prompt 스키마

### 18.1 입력 (각 batch)

```json
{
  "$schema": "https://nova/enrich-plans-input/v1.0",
  "version": "1.0",
  "roadmap_phases": [
    {"id": "P12", "title": "AXIS Autonomous Ops", "status": "done"},
    {"id": "P13", "title": "인프라 + 비용", "status": "in_progress"}
  ],
  "batch_index": 0,
  "batch_size": 10,
  "total_plans": 51,
  "plans": [
    {
      "path": "docs/plans/2026-05-09_ao-12-cost-jump.md",
      "filename": "2026-05-09_ao-12-cost-jump.md",
      "has_existing_frontmatter": false,
      "title_line": "# AO-12 Cost Jump Enrichment",
      "body_head_200": "..."  // 첫 200줄
    },
    ...
  ]
}
```

### 18.2 출력 (각 plan)

```json
{
  "results": [
    {
      "plan_path": "docs/plans/2026-05-09_ao-12-cost-jump.md",
      "proposed_frontmatter": {
        "plan_id": "ao-12-cost-jump",
        "parent_phase": "P13",
        "sprint_id": "AO-12",
        "title": "Cost Jump Enrichment",
        "status": "in_progress"
      },
      "confidence": "high",
      "unsure_fields": [],
      "skip_reason": null
    },
    ...
  ]
}
```

### 18.3 Agent prompt 규칙

- `parent_phase`는 입력 `roadmap_phases[].id` 집합 중 하나여야 함 (다른 값 금지)
- 추정 불가 필드는 `unsure_fields[]`에 명시 + frontmatter 안에 `# ⚠️ unsure: ...` 주석
- 신뢰도 (confidence): high(파일명·본문에 phase 명시) / medium(추정) / low(추측)
- `skip_reason` 있는 경우 frontmatter 작성 X (예: "non-plan file", "session log 파일")

### 18.4 안전성 — Agent가 본문 건드리지 않음

Agent는 **frontmatter 제안만** 출력. 본문 변경 0. Python 스크립트가 정규식 prepend만 실행.

## 19) 정확도 측정 + 사용자 검수

### 19.1 정확도 측정 (Sprint S11)

```python
# planreview 51개 + swk-gc 13개 dogfooding
total = 64
high_conf  = 결정론적 매핑 (파일명 ↔ ROADMAP phase id 일치)
medium     = title/본문 키워드 매칭
low        = 추측 (사용자 검수 필수)

# 목표:
# - high ≥ 60% (절반 이상 자동)
# - low ≤ 10% (추측은 소수)
# - skip ≤ 20% (non-plan 파일)
```

### 19.2 dry-run 결과 형식

각 plan 옆에 `<plan>.frontmatter.draft` 생성:

```yaml
# Generated by enrich-plans (dry-run mode)
# Confidence: high
# Apply: cat <this file> <original> > <new>  또는 enrich-plans.sh --apply
---
plan_id: ao-12-cost-jump
parent_phase: P13
sprint_id: AO-12
title: Cost Jump Enrichment
status: in_progress
---
```

### 19.3 요약 리포트

`enrich-plans.sh` 실행 종료 시:

```
=== enrich-plans 완료 ===
  총 plan: 51
  high confidence: 38 (74%)
  medium: 9 (17%)
  low (검수 필수): 2 (3%)
  skip (frontmatter 있음): 2 (3%)
  draft 생성: 49 → docs/plans/*.frontmatter.draft

다음 단계:
  1. low confidence 2개 우선 검수:
     - docs/plans/2026-04-15_legacy-handoff.md.frontmatter.draft
     - docs/plans/2026-04-20_misc-todo.md.frontmatter.draft
  2. ./scripts/enrich-plans.sh --apply (전체 적용)
     또는 cherry-pick (개별 plan):
       cat docs/plans/<x>.md.frontmatter.draft docs/plans/<x>.md > /tmp/new.md && mv /tmp/new.md docs/plans/<x>.md
  3. git diff docs/plans/ → review → git add + commit
```

## 20) Phase 3 산출물 매핑 (Sprint S9)

| 설계 항목 | 산출물 | 비고 |
|----------|--------|-----|
| 3 모드 (dry-run/patch/apply) | 본 문서 §17 | Sprint S10 구현 기준 |
| Agent prompt 스키마 | 본 문서 §18 | Sprint S10 Agent 위임 흐름 |
| 정확도 측정 + 검수 흐름 | 본 문서 §19 | Sprint S11 dogfooding 기준 |
| 안전성 5중 가드 | 본 문서 §17.3 | 모든 sprint 공통 검증 항목 |

Sprint S10~S12는 본 문서 §17~§19 계약을 글자 그대로 따른다.

---

# Phase 4 — Claude 우회 차단 + 자동 부트스트랩

> Phase 1·2·3(§1~§20)은 그대로 유지. 본 섹션은 명령 흐름 강제·UX 회복 contract.
> 동기: v5.33.0 출시 후 실측에서 3 케이스 모두 Claude(메인)가 우리 표준을 우회.
>   - 케이스 #1 (frontmatter 없는 프로젝트): minimal HTML 만들고 멈춤 (가치 0)
>   - 케이스 #2 (md-template-compiler): 프로젝트 자체 build_static.py 자동 사용
>   - 케이스 #3 (swk-gc): 도구 실행 0, NOVA-STATE 직접 읽어 텍스트 요약 대체

## 21) 강제 흐름 contract (Claude 우회 차단)

### 21.1 commands/status.md 톤 전환

기존 (안내문, Phase 1~3):
> "이렇게 사용할 수 있어요" + 옵션 나열 → Claude가 자율 해석

신규 (강제, Phase 4):
> "다음 흐름을 순서대로 강제 실행한다. 자율 해석 금지."

### 21.2 명시적 금지 패턴 (commands/status.md 내)

```
다음 행동은 금지:
- NOVA-STATE.md만 읽고 텍스트 요약으로 대체 (사용자는 dashboard HTML 요청)
- 프로젝트 자체 dashboard 도구(build_static.py / Makefile dashboard 타겟 등)로 우회
- minimal mode HTML 만들고 멈춤 (자동 부트스트랩 §22 강제 진입)
- 사용자가 명시적으로 --use-project-tool 옵션 사용한 경우만 예외
```

### 21.3 강제 실행 절차

```
Step 1 (필수, skip 불가): ./scripts/render-status.sh --open 실행
Step 2: 결과 분류
  - mode=roadmap → 완료 (사용자에게 HTML 경로 + 요약 보고)
  - mode=phase1 minimal=true → §22 자동 부트스트랩 진입
  - 프로젝트 자체 도구 발견 → 무시. Nova 표준 사용
Step 3 (§22 자동 부트스트랩): init-roadmap --llm + Agent 위임 + build 재실행
```

## 22) 자동 부트스트랩 흐름 (minimal 자동 진화)

### 22.1 트리거 조건

`render-status.sh` 결과 JSON의 `minimal: true` AND `mode: phase1`.

### 22.2 자동 진행 순서

```
1. ./scripts/init-roadmap.sh --llm     # NOVA-STATE + git log + plans 수집
2. Agent(general-purpose) subagent 호출 → /tmp/ROADMAP-{slug}-draft.md
3. ./scripts/render-status.sh --roadmap /tmp/ROADMAP-{slug}-draft.md --open
4. 사용자 보고:
   "임시 ROADMAP draft로 풍부한 dashboard 생성.
    검수 후 채택: mv /tmp/... ROADMAP.md && git commit"
```

### 22.3 새 옵션 — `render-status.sh --auto-bootstrap`

명시적 옵션으로도 호출 가능 (commands가 자동 트리거하지만 사용자도 직접):

```bash
./scripts/render-status.sh --auto-bootstrap    # minimal 감지 시 자동 진화
./scripts/render-status.sh --no-bootstrap      # 자동 진화 비활성 (기존 동작 강제)
```

### 22.4 안전 가드

- Agent 위임 단계는 외부 API 호출 0 (Claude Code 세션 모델, visual-self-verify 패턴 일관)
- draft는 /tmp에 — swk-gc 등 사용자 레포 작업 트리 변경 0
- 사용자 명시적 commit이 있을 때까지 ROADMAP.md 변경 0

## 23) bin/ 진입점 — Claude 개입 없이 직접 호출

### 23.1 신규: `bin/nova-status`

```bash
#!/bin/bash
# bin/nova-status — 사용자 직접 호출. Claude 개입 0.
# 무조건 표준 흐름 강제.
exec "${CLAUDE_PLUGIN_ROOT}/scripts/render-status.sh" --auto-bootstrap --open "$@"
```

### 23.2 효과

- 사용자가 `nova-status` 타이핑 → bash가 직접 실행 → Claude 자율 해석 0
- `/nova:status` slash 커맨드는 Claude 경유 (commands/status.md 강제 톤이 가드)
- 두 진입점 모두 결국 동일 결과

### 23.3 메모리 일관성

- 메모리 `feedback_nova_universal_plugin` — Nova 범용 플러그인. SWK 색채 0
- 메모리 `feedback_api_key_optional_principle` — 외부 API 호출 0 유지
- 메모리 `feedback_no_manual_setup` — 사용자가 직접 호출만 하면 작동

## 24) Phase 4 산출물 매핑 (Sprint S13)

| 설계 항목 | 산출물 | 비고 |
|----------|--------|-----|
| 강제 톤 contract | 본 문서 §21 | S14 commands/status.md 재작성 기준 |
| 자동 부트스트랩 흐름 | 본 문서 §22 | S15 render-status.sh --auto-bootstrap 구현 |
| bin entrypoint | 본 문서 §23 | S14 bin/nova-status 신규 |
| 우회 차단 검증 | S16 R34 회귀 | 3 케이스 재검증 (nova/swk-gc/md-template) |

Sprint S14~S16은 본 문서 §21~§23 계약을 글자 그대로 따른다.
