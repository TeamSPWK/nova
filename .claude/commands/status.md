---
description: "프로젝트 현황(Phase·Sprint·그룹 진행률) + drift 알람을 stand-alone HTML로 한 눈에 본다. 노션/wiki sync 불필요 — git이 진실원. — MUST TRIGGER: AI에게 위임 후 점검, 멀티 프로젝트 상태 확인, 로드맵 drift 점검 필요 시."
description_en: "View project status (Phase/Sprint/group progress) + drift alerts as a stand-alone HTML. No notion/wiki sync — git is the source of truth. — MUST TRIGGER: after delegating work to an agent, checking multi-project status, or auditing roadmap drift."
---

`/nova:status`는 Plan frontmatter(SOT) + git log를 결정론적으로 파싱하여 토스식 카드 HTML 대시보드를 만든다.
하드코딩 진행률 X. 사용자가 손으로 갱신할 필드 0개.

# Role
너는 프로젝트 현황과 AI 위임 결과를 사용자에게 5초 안에 전달하는 가시화 도구다.

# Execution

## Step 1 — 빠른 호출

```bash
# Plan frontmatter가 작성되어 있다면 (docs/designs/status-dashboard.md §4)
./scripts/render-status.sh --plan docs/plans/<your-plan>.md --open
```

자동으로 docs/plans/*.md 중 첫 frontmatter 발견 시:

```bash
./scripts/render-status.sh --open
```

산출물: `.nova/status/index.html` — file:// 로 열어도 작동, 의존성 0.

## Step 2 — ROADMAP.md 없을 때 (init wizard, Phase 2)

`ROADMAP.md`가 없으면 자동 wizard로 부트스트랩 제안. 3 모드:

```bash
./scripts/init-roadmap.sh --blank   # 빈 템플릿 (1초, 레거시 docs 0건 참조)
./scripts/init-roadmap.sh --scan    # docs/plans/*.md parent_phase 추출 (5초, 결정론)
./scripts/init-roadmap.sh --llm     # NOVA-STATE + git log + plans 자료 수집 → Agent subagent
```

자동 commit 0건. 모든 모드는 파일만 생성 후 사용자 검수 + 명시적 commit 안내.

### LLM 모드 흐름 (Agent subagent, API 키 0)

1. `init-roadmap.sh --llm` → `.nova/init-input.json` 자료 수집 (NOVA-STATE + git log 30d + plans frontmatter + non-archived docs)
2. Claude(메인)가 Agent(general-purpose) subagent 호출:
   - prompt: "docs/designs/status-dashboard.md §12 + .nova/init-input.json 기반 ROADMAP.md.draft 작성. ⚠️ unsure rule 준수."
3. Agent가 `ROADMAP.md.draft` 작성 → 사용자 검수 → `mv ROADMAP.md.draft ROADMAP.md && git add && git commit`
4. visual-self-verify와 동일 패턴 — 외부 API 호출 0건 (Claude Code 세션 모델)

## Step 2.5 — 기존 plans 자동 enrich (Phase 3)

ROADMAP.md frontmatter v1.0 완료된 후, `docs/plans/*.md`에 `parent_phase`·`sprint_id`를 일괄 자동 추가:

```bash
./scripts/enrich-plans.sh --collect      # Stage 1: ROADMAP + plans → .nova/enrich-batches/*
# (메인 Claude가 Agent subagent에게 batch별 위임 → output-N.json)
./scripts/enrich-plans.sh --dry-run      # Stage 3 (default): drafts 생성, 원본 변경 0
./scripts/enrich-plans.sh --patch         # unified diff 1개
./scripts/enrich-plans.sh --apply --force # 원본 prepend + .bak 자동 백업
```

### 5중 안전 가드

1. 본문 0 byte 변경 (frontmatter 위에 prepend만)
2. 기존 frontmatter 있는 plan 자동 skip
3. `--apply` 시 `.bak` 자동 백업
4. batch 10 (LLM context 폭증 방지)
5. 자동 git commit 0건

dogfooding 결과 (Sprint S11): 2개 프로젝트 / 69 plans → high confidence 74%, low 1.4%.

## Step 3 — Phase 1 vs Phase 2 모드

| 조건 | 동작 |
|------|------|
| ROADMAP.md 없음 | Phase 1 — plan frontmatter SOT (§4) |
| ROADMAP.md 있음 | Phase 2 — ROADMAP + docs/plans/*.md 멀티 통합 (§12~§15) |
| `--no-roadmap` 플래그 | Phase 2 무시, Phase 1 강제 |

Phase 1은 100% 호환 (기존 사용자 무손상).

## Step 4 — frontmatter 미작성 시 (minimal mode)

plan에 frontmatter v1.0 스키마가 없으면 graceful degradation으로 minimal mode HTML이 생성된다.
가이드: `docs/guides/status-dashboard.md` § 부트스트랩.

## Step 5 — 결과물 5섹션

1. **헤더** — Plan 제목 / 현재 Phase·Sprint / 생성 시각
2. **Phase 시계열 progress bar** — done(녹색 체크) / in_progress(파란 점) / pending(빈 원)
3. **그룹별 진행률** — 큰 숫자 "30/42 화면 완료" + 각 그룹 bar (count/target/%)
4. **Sprint 리스트** — 현재 Phase의 sprint들 (체크 / 화살표 / 빈 원)
5. **Drift 카드** — 5분류 (aligned / drifted / unspecced / unverifiable / conflict / tag_missing) + verdict 배지 (green/amber/red/unknown)

## Step 6 — commit convention (drift 추적 활성화)

drift를 추적하려면 commit 본문에 tag 명시:

```
feat: <subject>

Plan: <plan_id>
Goal: <goal_id>   # 선택
```

tag 누락은 차단 안 됨 — `tag_missing` 버킷에 분리 카운트 (drift 오인 X).
CLAUDE.md 룰 1줄로 AI(Claude/Codex/Cursor)도 자동 동참 가능.

# Outputs

| 산출물 | 위치 | 용도 |
|--------|------|------|
| HTML | `.nova/status/index.html` (default) | 사용자가 브라우저에서 본다 |
| JSON | `--data` 옵션으로 분리 가능 | CI, 외부 도구 연동 |

# 관련 자산

- 데이터 계약: `docs/designs/status-dashboard.md` §4-§7
- 사용자 가이드: `docs/guides/status-dashboard.md`
- Skill: `skills/status-dashboard/SKILL.md`
- Build: `scripts/build-status.sh` (frontmatter + glob + git → JSON)
- Render: `scripts/render-status.sh` (JSON → HTML, build와 chain 가능)
