# `/nova:status` — 프로젝트 현황 + drift 대시보드

> AI에게 위임한 작업이 원래 계획에서 얼마나 벗어났는지를 git 기록만으로 5초 안에 보여주는 도구.

## TL;DR (3줄 요약)

1. `docs/plans/<your>.md`에 frontmatter v1.0(`plan_id`, `phases`, `sprints`, `groups`, `goals`) 작성
2. `./scripts/render-status.sh --plan docs/plans/<your>.md --open` 호출 → `.nova/status/index.html` 자동 생성 + 브라우저 열림
3. commit 본문에 `Plan: <plan_id>` `Goal: <goal_id>` 한 줄씩 — drift 자동 추적

진행률은 git/파일시스템에서 자동 파생. 노션·wiki sync 부담 0. file:// 작동, 의존성: python3 + PyYAML + git.

---

## 1) 빠른 시작

### 한 번에 (build + render + 브라우저)

```bash
./scripts/render-status.sh --plan docs/plans/<your>.md --open
```

### 단계별

```bash
./scripts/build-status.sh --plan docs/plans/<your>.md --out .nova/status/data.json
./scripts/render-status.sh --data .nova/status/data.json --out .nova/status/index.html
open .nova/status/index.html
```

### plan 자동 발견

`--plan` 생략 시 `docs/plans/*.md` 중 첫 frontmatter 발견 파일 사용.

```bash
./scripts/render-status.sh --open
```

---

## 2) Plan frontmatter — 5분 부트스트랩

플랜 파일 상단에 YAML frontmatter 추가. 진행률·drift 추적의 SOT(Single Source of Truth).

```yaml
---
plan_id: my-feature                    # 필수. URL-safe slug
title: 내 기능 한 줄 설명               # 필수
current_phase: P2                      # 선택 (없으면 첫 in_progress 자동 선택)
current_sprint: S1                     # 선택

phases:                                # Phase 시계열 (상단 progress bar)
  - {id: P1, title: 설계,  status: done}
  - {id: P2, title: 구현,  status: in_progress, summary: "Sprint 4개"}
  - {id: P3, title: 검증,  status: pending}
  - {id: P4, title: 릴리스, status: pending}

sprints:                               # phase별 sprint 리스트 (중간 카드)
  P2:
    - {id: S1, title: API 스키마,    status: done}
    - {id: S2, title: 핵심 로직,     status: in_progress}
    - {id: S3, title: 통합 테스트,   status: pending}
    - {id: S4, title: 문서·릴리스,  status: pending}

groups:                                # 화면/기능 단위 진행률 (좌 큰 숫자 + 우 bar)
  - {id: H1, title: 회상 흐름,   target: 6,  paths: ['app/h1/**/page.tsx']}
  - {id: H2, title: 매칭,        target: 5,  paths: ['app/h2/**/page.tsx']}
  - {id: public, title: 공개,    target: 14, paths: ['app/public/**/page.tsx', '!**/_*.tsx']}

goals:                                 # drift 추적 단위 (commit tag와 매핑)
  - {id: G1, title: 매칭 정확도 90%, paths: ['src/matching/**'], status: in_progress}
  - {id: G2, title: 결제 모듈,        paths: ['src/payment/**'], status: pending}
---
```

### 스키마 규칙

| 필드 | 필수 | 비고 |
|------|------|------|
| `plan_id` | ✓ | 없으면 minimal mode |
| `phases[].status` | ✓ | `done` / `in_progress` / `pending` / `blocked` 중 하나 |
| `groups[].target` | ✓ | 양의 정수. ≤0이면 해당 group 표시 X |
| `groups[].paths` | ✓ | fast-glob 패턴. `**` 재귀, `!prefix` negation |
| `goals[].paths` | ✓ | drift 매칭용. 없으면 unspecced로 분류 |

전체 스키마: [docs/designs/status-dashboard.md §4](../designs/status-dashboard.md).

---

## 3) Commit Convention — drift 추적 활성화

drift를 추적하려면 commit 본문에 tag 명시:

```
feat: 매칭 알고리즘 v2

Plan: my-feature
Goal: G1
```

- `Plan:` 누락 → `tag_missing` 버킷 (drift 아님)
- `Goal:` 누락 + paths 매칭 → `aligned` (선언 안 했지만 잘 한 경우)
- `Goal: <존재하지 않음>` → `conflict`

### CLAUDE.md 룰 1줄 (AI 에이전트 자동 동참)

프로젝트 CLAUDE.md 또는 AGENTS.md에 추가:

```markdown
## Commit Convention
- 의도된 작업은 commit 본문에 `Plan: <plan_id>` 명시. goal 단위 추적 시 `Goal: <goal_id>` 추가.
- tag 누락은 차단 안 됨 (Nova는 tag_missing 버킷으로 분리만)
```

Claude Code / Codex / Cursor 등 모든 AI가 이 룰을 읽고 자동 동참.

---

## 4) 결과 5섹션 해석

| 섹션 | 의미 | 데이터 출처 |
|------|------|------------|
| **헤더** | Plan 제목 + 현재 Phase·Sprint + 생성 시각 | frontmatter |
| **Phase bar (상단)** | 7단(또는 N단) progress — 완료(✓) / 진행 중(•) / 대기(○) | `phases[].status` |
| **screens-total + 그룹 bar (중단)** | 좌측 "30 / 42 화면 완료" + 우측 그룹별 bar | `groups[].paths` 매칭 파일 수 / target |
| **Sprint 리스트** | 현재 Phase의 sprint들 | `sprints[current_phase][]` |
| **Drift 카드 (하단)** | 5분류 + verdict | git log + commit tag 정규식 매핑 |

### Drift verdict

| verdict | 의미 | 다음 행동 |
|---------|------|----------|
| 🟢 green | drift < 30% | 진행 |
| 🟡 amber | 30~70% | drifted commits 검토 |
| 🔴 red | 70%+ | 즉시 작업 중단, drift 원인 분석 |
| ⚫ unknown | tag_missing 100% | CLAUDE.md 룰 추가 (§3) |

---

## 5) FAIL / 문제 해결

### "minimal mode" 카드만 나옴

- frontmatter에 `plan_id` 누락 → §2 부트스트랩으로 추가

### `groups[H1].target ≤ 0 — 표시 X` 경고

- `target`을 양의 정수로 (목표 화면 수)

### 모든 commit이 `tag_missing`

- §3 commit convention 적용. 과거 commit은 어쩔 수 없음 (앞으로만)
- `--since "30 days ago"` 같이 보고 싶은 기간 명시

### `PyYAML required` 에러

```bash
pip3 install PyYAML
```

### file:// 로 열었는데 빈 화면

- 외부 fetch 0 보장됨 (Tailwind CDN script tag만). 빈 화면이면 build/render 산출물 손상 가능성. 재실행:
  ```bash
  rm -rf .nova/status && ./scripts/render-status.sh --plan docs/plans/<your>.md --open
  ```

### 진행률이 실제와 다름

- `groups[].paths` glob 패턴 확인. `find . -path './app/h1/**/page.tsx'`로 실제 매칭 검증
- `target`과 실제 화면 수 차이 검토

---

## 6) Cheatsheet

```bash
# 한 번에 (가장 흔한 사용)
./scripts/render-status.sh --plan docs/plans/<your>.md --open

# JSON만 (CI / 외부 도구 연동)
./scripts/build-status.sh --plan docs/plans/<your>.md --out status.json

# 7일이 아닌 기간으로
./scripts/render-status.sh --since "30 days ago" --plan ...

# 다른 위치에 출력
./scripts/render-status.sh --out docs/status.html --plan ...

# 도움말
./scripts/build-status.sh --help
./scripts/render-status.sh --help
```

## 7) Phase 2 — ROADMAP.md + 멀티 plan 통합 (선택)

### 언제 쓰나?

- Phase 시계열(12·13·14...)이 명확한 프로젝트
- Sprint가 여러 파일(`docs/plans/ao-12.md` 등)로 나뉘어 있음
- NOVA-STATE.md 50줄로는 전체 진행 흐름 표현 불가

### 빠른 시작

```bash
# ROADMAP.md 없으면 init wizard
./scripts/init-roadmap.sh --scan    # docs/plans/* frontmatter 자동 추출 (5초)
./scripts/init-roadmap.sh --blank   # 빈 템플릿 (1초, 사용자가 손으로 채움)
./scripts/init-roadmap.sh --llm     # 자료 수집 + Claude Agent가 초안 작성

# ROADMAP 검토 + commit
git add ROADMAP.md && git commit -m "feat: ROADMAP.md initial"

# 통합 dashboard 생성
./scripts/render-status.sh --open
```

### ROADMAP.md frontmatter 예시

```yaml
---
roadmap_id: my-project
title: My Project Roadmap
current_phase: P13
phases:
  - {id: P12, title: v1.0 Foundation, status: done}
  - {id: P13, title: 인프라 + 비용, status: in_progress}
  - {id: P14, title: 자율 조치 + 협업, status: pending}
external_pending:
  - {id: EXT-1, title: 관리자 권한 승인, blocker: IT 승인 대기, phase: P13}
---
```

### plan.md frontmatter 확장 (멀티 plan 통합)

각 `docs/plans/<id>.md`에 `parent_phase` 추가:

```yaml
---
plan_id: ao-12
parent_phase: P13      # ← ROADMAP의 phases[].id 중 하나
sprint_id: AO-12
title: S2 흡수형 Cost Jump Enrichment
status: in_progress
---
```

`/nova:status` 호출 시 자동 그룹핑:
- ROADMAP `phases[]` = phase bar
- `docs/plans/*.md` `parent_phase` = sprint 리스트
- 결정론 95%+ 보장

### init wizard 3 모드 선택 가이드

| 상황 | 권장 모드 |
|------|----------|
| 신규 프로젝트, 아무것도 없음 | `--blank` |
| 기존 `docs/plans/*.md` 있음 + frontmatter `parent_phase` 추가 가능 | `--scan` |
| 레거시 docs 많음, NOVA-STATE는 풍부 | `--llm` (Agent가 정제) |
| **레거시 docs 회피 원함** | `--blank` (기존 docs 0건 참조) |

### Stale 검증

ROADMAP.md commit이 N일+ 전이면 자동 ⚠️ 배지:

```bash
./scripts/build-status.sh --stale-threshold 14    # 임계 조정 (default 7)
```

### Phase 2 ↔ Phase 1 호환성

- **ROADMAP 없으면** → Phase 1 그대로 (plan frontmatter SOT)
- **`--no-roadmap` 플래그** → ROADMAP 있어도 Phase 1 강제
- 기존 Phase 1 사용자 무손상

## 8) Phase 3 — 기존 plans 자동 enrich (대량 마이그레이션)

### 언제 쓰나?

이미 `docs/plans/*.md` 다수 존재 + frontmatter v1.1 (`parent_phase`/`sprint_id`/`status`)을 손으로 추가하기 부담스러울 때.

### 빠른 시작 (3 단계)

```bash
# Stage 1: 자료 수집 + skip 분류 (frontmatter 있는 plan 자동 제외)
./scripts/enrich-plans.sh --collect

# Stage 2: 메인 Claude(또는 사용자)가 Agent subagent에 batch별 위임
#   - 각 .nova/enrich-batches/batch-N.json → output-N.json
#   - Agent prompt 스키마: docs/designs/status-dashboard.md §18

# Stage 3: dry-run으로 안전 검수 (default)
./scripts/enrich-plans.sh --dry-run
# → 각 plan 옆에 <plan>.frontmatter.draft 생성, 원본 변경 0
```

### 3 적용 모드

| 모드 | 변경 대상 | 안전성 |
|------|----------|--------|
| `--dry-run` (default) | `<plan>.md.frontmatter.draft` 생성 (원본 변경 0) | 🟢 100% |
| `--patch` | `.nova/enrich-plans.patch` 1개 (unified diff → `git apply`) | 🟢 git 친화 |
| `--apply --force` | 원본 prepend + `.bak` 자동 백업 | 🟡 사용자 명시 |

### 5중 안전 가드

1. **본문 0 byte 변경** — frontmatter만 prepend
2. **기존 frontmatter 자동 skip** — 첫 줄 `---` 매치 시 그대로 두고 warning
3. **`.bak` 자동 백업** (`--apply` 시) — 손쉬운 복구
4. **batch 10** (default) — LLM context 폭증 방지
5. **자동 git commit 0건** — 모든 모드

### dogfooding 실측 (Sprint S11)

| 프로젝트 | plans | high | medium | low | skip |
|---------|-------|------|--------|-----|------|
| Project A | 24 | 66% | 29% | 4% | 4% |
| Project B | 45 | 77% | 22% | 0% | 2% |
| **합계** | **69** | **74%** | **25%** | **1.4%** | **2.9%** |

목표 (high≥60%, low≤10%, skip≤20%) 모두 충족.

### 흐름 예시 (45 plans 프로젝트)

```bash
cd /path/to/your-project
./scripts/enrich-plans.sh --roadmap /path/to/ROADMAP-draft.md --collect
# → .nova/enrich-batches/batch-{000..004}.json (5 batches × 10 plans)

# Agent에게 위임 (Claude Code 세션 모델, 외부 API 키 0)
# → output-{000..004}.json 작성

./scripts/enrich-plans.sh --dry-run
# → docs/plans/*.frontmatter.draft (44개) + low confidence 리포트

# 검수 후
./scripts/enrich-plans.sh --apply --force
# → 원본에 frontmatter 추가 + .bak 자동 백업

git diff docs/plans/   # review
git add docs/plans/    # commit
```

### Cheatsheet

```bash
./scripts/enrich-plans.sh --collect                    # 자료 수집
./scripts/enrich-plans.sh --dry-run                    # drafts 생성
./scripts/enrich-plans.sh --patch                       # unified diff
./scripts/enrich-plans.sh --apply --force               # 원본 prepend
./scripts/enrich-plans.sh --collect --batch-size 5      # batch 크기 조정
./scripts/enrich-plans.sh --roadmap /tmp/draft.md ...   # 외부 ROADMAP

# 복구 (--apply 후 되돌리기)
for f in docs/plans/*.md.bak; do mv "$f" "${f%.bak}"; done
```

## 9) 관련 자산

- 데이터 계약 (frontmatter / JSON / HTML 템플릿 / ROADMAP / 멀티 plan / stale / init wizard): `docs/designs/status-dashboard.md` §1~§16
- Plan: `docs/plans/status-dashboard.md`
- 커맨드: `commands/status.md`
- 스킬: `skills/status-dashboard/SKILL.md`
- 회귀 가드: `tests/test-scripts.sh` R31a~R31q (Phase 1) + R32 (Phase 2)
