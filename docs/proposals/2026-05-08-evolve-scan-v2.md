# Evolution Scan: 2026-05-08 (보완 — 생태계 중심)

> 날짜: 2026-05-08
> 모드: --scan (보완 스캔)
> 출처: Anthropic CC changelog v2.1.128~133, AGENTS.md 표준, Aider/Cline/Continue.dev 공식

## Context

오늘 1차 스캔(`docs/proposals/2026-05-08-evolve-scan.md`)에서 P-7(외부 소스 다양성 강제)이 적용된 직후(`f1a37fe`), 1차에서 다루지 않은 **CC changelog 누락분(v2.1.128/129/132 일부) + 외부 생태계 표준(AGENTS.md, Aider Watch, Cline rules, Continue.dev)**을 보완 스캔한다. 1차와의 중복 없음.

## 스캔 범위

| 소스 | 발견 | 관련 | 출처 |
|------|------|------|------|
| Anthropic CC changelog v2.1.128~133 (1차 누락분) | 4건 | 3건 | https://code.claude.com/docs/en/changelog |
| **AGENTS.md 표준 (agents.md/agentsmd) — Cross-tool spec** | 3건 | 1건 | https://agents.md/ |
| **Aider 공식 (Watch Mode, repo map)** | 3건 | 1건 | https://aider.chat/docs/ |
| **Cline 공식 (Plan/Act, .clinerules)** | 4건 | 1건 | https://docs.cline.bot/features/plan-and-act |
| **Continue.dev (.continue/rules/, AGENTS.md issue #6716)** | 2건 | 1건 | https://docs.continue.dev/customize/rules |

**외부 소스 다양성**: ✅ Anthropic 외 4개 외부 소스 (목표 2개 이상 충족, P-7 가이드 따름).

**관련성 필터**: Nova 4 Pillar 또는 commands/skills/agents/hooks/scripts 직접 영향 항목만 통과.

## 1차 스캔과의 중복 회피

- P-1 (effort.level 캡처) — 1차에서 다룸. 본 스캔에서 제외.
- P-2 (CC SESSION_ID) — 1차에서 다룸. 본 스캔에서 제외.
- P-5 (TDD-first) — 적용 완료 (`f1a37fe`). 제외.
- P-7 (소스 다양성) — 적용 완료 (`f1a37fe`). 제외.

## 신규 관련 항목

### [Q-1] `worktree.baseRef` 설정 명시 — patch

#### 발견
- **CC v2.1.133**: `worktree.baseRef` setting (`fresh` | `head`) — `--worktree`/`EnterWorktree`/agent-isolation 워크트리가 `origin/<default>` vs 로컬 `HEAD` 어디서 분기할지 결정.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.133)

#### Nova 현재 상태
`skills/worktree-setup/SKILL.md`와 `commands/worktree-setup.md`는 `.env`/시크릿/설정 파일 심볼릭 링크에 집중. **분기 시점**(어떤 ref에서 워크트리를 만들지)에 대한 가이드 없음.

v2.1.128에서 `EnterWorktree`가 default-branch가 아닌 HEAD에서 분기하도록 수정됨. v2.1.133에서 사용자가 명시 선택 가능. 즉 **사용자가 unpushed 로컬 커밋을 워크트리에서 보고 싶다 vs 깨끗한 origin 기반에서 시작** 결정이 명시화됨.

#### Nova 적용 방안
`skills/worktree-setup/SKILL.md`에 "분기 ref" 섹션 추가:
- `head` (기본 권장, v2.1.128+) — 로컬 미푸시 커밋 포함, Nova의 incremental 작업 흐름과 일치
- `fresh` — release-track 검증, hot-fix 분기에 권장

`commands/worktree-setup.md`에 한 줄 안내 + 설정 예시 (settings.json 스니펫).

#### 영향 범위
- `skills/worktree-setup/SKILL.md` (~15줄)
- `commands/worktree-setup.md` (~5줄 설정 예시)
- 회귀 가드: tests/test-scripts.sh — "worktree.baseRef" 키워드 grep

#### 리스크
- 설정 자체는 사용자 settings.json 책임이므로 Nova가 강제하지 않음. 가이드만 제공 → 리스크 거의 없음.

#### 자율 등급
**Full Auto** — 가이드 문서 추가만, 동작 변경 없음.

---

### [Q-2] `--plugin-url`로 Nova zip 배포 채널 — minor

#### 발견
- **CC v2.1.129**: `--plugin-url <url>` 플래그로 zip 아카이브 직접 로드 가능.
- 사용 예: CI build artifact URL을 직접 사용자에게 전달하여 검증.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.129), https://claude-world.com/articles/claude-code-21129-release/

#### Nova 현재 상태
Nova는 marketplace 플러그인으로 배포(`.claude-plugin/marketplace.json`). 사용자가 특정 커밋/버전을 검증하려면:
1. clone 후 `--plugin-dir` 사용 (기존 방식)
2. release zip 다운로드 후 `--plugin-dir` (간접)

`--plugin-url` 채널이 새로 열렸지만 Nova는 활용 안 함.

#### Nova 적용 방안

**Phase 1 (간단 적용 — patch 수준)**: 릴리스 zip URL을 README/release notes에 명시 → 사용자가 `--plugin-url` 직접 사용 가능.

```
claude --plugin-url https://github.com/TeamSPWK/nova/archive/refs/tags/v5.30.2.zip
```

GitHub release tag zip은 자동 생성되므로 추가 작업 없음. README 한 섹션 추가만.

**Phase 2 (확장 — 별도 minor 스프린트)**: `scripts/release.sh`가 zip 빌드를 검증/공지에 포함 (CI artifact를 evolve 워크플로에 활용).

#### 영향 범위
- Phase 1: `README.md` + `README.ko.md` (각 ~10줄)
- Phase 2: `scripts/release.sh` (선택, 별도 스프린트)
- 회귀 가드: tests/test-scripts.sh — README에 `--plugin-url` 키워드 존재 확인

#### 리스크
- 사용자가 zip 무결성 보장을 받지 않으면 위험. GitHub tag zip은 commit-pinned이므로 안전.
- Phase 2는 release.sh 변경이므로 별도 검증 필요.

#### 자율 등급
**Phase 1: Full Auto** (README 문서 추가)
**Phase 2: Manual** (release.sh 변경은 PR 필요)

---

### [Q-3] `skillOverrides` 사용자 가이드 — patch

#### 발견
- **CC v2.1.126~131**: `skillOverrides` 설정 동작 — `off`(완전 비활성), `user-invocable-only`(`/` 전용, 자동 트리거 차단), `name-only`(description 숨김).
- 출처: https://code.claude.com/docs/en/changelog

#### Nova 현재 상태
Nova는 18+ 스킬을 ship한다. 사용자에 따라:
- 일부 스킬(예: `figma-*`, 본인이 안 쓰는 도메인)이 자동 트리거되어 컨텍스트 점유
- 메타-스킬(`evaluator`, `jury`)을 일시 비활성화하고 싶을 수 있음

현재 docs/guides/에 `skillOverrides` 관련 안내 없음 → 사용자 마찰.

#### Nova 적용 방안
`docs/guides/skill-governance.md` (신규, ~80줄):
- skillOverrides 3가지 모드 설명
- Nova 스킬 카테고리별 권장 설정 (예: ux-audit는 backend-only 작업에서 `off` 권장)
- settings.json 예시 스니펫

`README.md`에 "Skill 비활성화" 섹션 1줄 + 가이드 링크.

#### 영향 범위
- `docs/guides/skill-governance.md` (신규)
- `README.md` + `README.ko.md` (~3줄 링크)
- `tests/test-scripts.sh` — 신규 가이드 파일 존재 + 핵심 키워드 회귀 가드 (CLAUDE.md "신규 스크립트 / Workflow" 체크리스트 따름)

#### 리스크
- 가이드만 추가. 설정 자체는 사용자 책임 → 리스크 없음.

#### 자율 등급
**Full Auto** — 신규 가이드 추가, Nova 동작 변경 없음.

---

### [Q-4] AGENTS.md 표준 정렬 점검 — minor (메타-감사)

#### 발견
- **agents.md/agentsmd 오픈 표준 (2026 cross-tool 수렴)**: AGENTS.md는 README 형식의 에이전트 전용 가이드 파일. **OpenAI Codex, Continue.dev, Augment, Factory, Builder, Kilo** 등이 동시 채택.
- Continue.dev issue #6716는 root AGENTS.md를 표준 진입점으로 통합 진행 중.
- 출처: https://agents.md/, https://github.com/agentsmd/agents.md, https://www.augmentcode.com/guides/how-to-build-agents-md

#### Nova 현재 상태
Nova는 `commands/claude-md.md` + `skills/claude-md/SKILL.md`로 CLAUDE.md/AGENTS.md 양쪽을 다룬다. 하지만:
1. claude-md skill은 **CLAUDE.md 우선, AGENTS.md fallback** 구조 (Claude Code 중심)
2. agents.md 표준이 명시한 **uppercase 의무 / 중첩 디렉토리 closest-wins** 동작이 Nova guide에서 명시적이지 않을 수 있음

#### Nova 적용 방안
3단계 점검:
1. `skills/claude-md/SKILL.md`의 AGENTS.md 섹션이 agents.md 표준의 다음 4 요소를 모두 다루는지 grep 검증:
   - "uppercase filename" (대소문자)
   - "closest in directory tree" (중첩 우선순위)
   - "complement README" (README 보완 관계)
   - "build/test/conventions" (4종 권장 섹션)
2. 누락 항목이 있으면 `skills/claude-md/SKILL.md`에 보완 (~30줄 이내)
3. `docs/guides/claude-md.md` (이미 존재)에 표준 출처 링크 1줄 추가

#### 영향 범위
- `skills/claude-md/SKILL.md` (보완 시 ~30줄)
- `docs/guides/claude-md.md` (~5줄)
- 회귀 가드: 4 키워드 grep (uppercase / closest / complement / build·test·conventions 중 영어/한국어 변형)

#### 리스크
- claude-md skill은 사용자 마이그레이션을 다루는 핵심 entry point. 변경은 신중. **점검 결과 누락이 없으면 변경 없이 종료** 가능.
- 표준 자체가 빠르게 진화 중 → 출처 링크는 versioned URL 권장.

#### 자율 등급
**Semi Auto (PR)** — claude-md는 사용자 가시성 높음. 점검 결과를 PR로 리뷰 후 머지.

---

### [Q-5] 복잡도 heuristic 보강 — duration signal — patch

#### 발견
- **Cline 공식 (2026)**: "break any task estimated at more than 30 minutes into discrete steps". Plan/Act mode가 5+ 파일 OR 30분+ 예상 작업에 강제 발동.
- 출처: https://www.deployhq.com/guides/cline, https://cline.bot/blog/plan-smarter-code-faster-clines-plan-act-is-the-paradigm-for-agentic-coding

#### Nova 현재 상태
복잡도 트리거(session-start.sh + docs/nova-rules.md):
- 간단 1~2 파일 → 바로
- 보통 3~7 파일 → Plan
- 복잡 8+ → Plan→Design→스프린트
- 인증/DB/결제 +1

**Nova는 "파일 수"와 "도메인 가중치"만 사용.** Cline의 "예상 시간" 시그널 없음. 사용자가 1~2 파일이지만 30분 이상 걸릴 작업(예: 복잡한 알고리즘 단일 함수)을 시작할 때 Plan 승격 트리거 누락 가능.

메모리 `feedback_nova_bypass_patterns.md`("소규모로 시작한 작업이 3파일+로 커질 때 승격 안 됨")와 직접 연결 — duration signal이 있으면 미리 차단 가능.

#### Nova 적용 방안
`docs/nova-rules.md` §1 복잡도 룰에 **soft signal 추가**:

> "**Duration heuristic (옵션)**: 1~2파일이라도 단일 함수 구현이 30분 이상 예상되거나(복잡 알고리즘/외부 시스템 연동/마이그레이션 로직), 사용자가 '시간이 걸릴 것 같다'는 신호를 주면 Plan 승격을 권고한다. 강제 아니며 사용자 합의 우선 (`feedback_sprint_checkpoint.md`)."

`hooks/session-start.sh` additionalContext §1에 한 줄 mirror.

#### 영향 범위
- `docs/nova-rules.md` (~5줄)
- `hooks/session-start.sh` (~2줄)
- `tests/test-scripts.sh` — duration heuristic 키워드 동기화 회귀 가드

#### 리스크
- "30분 예상"은 주관적 → soft signal로 둠. 강제 트리거 X.
- 메모리에 기록된 사용자의 "사용자 확인 후 진행" 원칙 위배 안 함.

#### 자율 등급
**Full Auto** — 가이드 문구 추가, 동작 강제 없음. session-start 동기화 필수.

---

### [Q-6] Aider Watch Mode 관찰 (out-of-scope 권장) — manual

#### 발견
- **Aider Watch Mode (2026)**: 코드 주석에 `# AI: <요청>` 마커를 두면 Aider가 백그라운드에서 변경 → 커밋 → 마커 제거. 사용자는 에디터 안에서만 작업.
- 출처: https://aider.chat/docs/, https://www.deployhq.com/guides/aider

#### Nova 현재 상태
Nova는 슬래시 커맨드 + 자연어 요청 (`/nova:auto`) 방식. 인라인 마커 driven flow 없음.

#### 평가 (제안 X, 관찰만)
- Aider Watch는 **에디터 일급 통합** 전제 — Claude Code는 백그라운드 마커 watch 메커니즘 부재.
- Nova는 Generator-Evaluator 분리 + 사용자 체크포인트(`feedback_sprint_checkpoint.md`)가 핵심 — 인라인 자동 적용은 철학과 충돌.
- **결론: out-of-scope.** Nova 철학상 흡수하지 않음. 본 항목은 향후 Claude Code가 watch primitive를 제공할 때 재검토.

#### 자율 등급
**관찰 only** — 제안 생성 X.

---

## 정리 (최종)

- **patch (3건)**: Q-1 worktree.baseRef 가이드, Q-3 skillOverrides 가이드, Q-5 duration heuristic
- **minor (2건)**: Q-2 --plugin-url 배포 채널, Q-4 AGENTS.md 표준 정렬 점검
- **major (0건)**
- **관찰 only (1건)**: Q-6 Aider Watch Mode

### 우선 적용 추천 순서

1. **Q-1 (patch)** — `worktree.baseRef` 가이드. CC v2.1.133 직접 매칭, 사용자 즉시 효용.
2. **Q-3 (patch)** — `skillOverrides` 가이드. Nova 18+ 스킬 사용자 마찰 해소.
3. **Q-5 (patch)** — duration heuristic. 메모리 `feedback_nova_bypass_patterns.md` 직결.
4. **Q-2 (minor) Phase 1** — `--plugin-url` 배포 채널 README. Phase 1만 patch 수준.
5. **Q-4 (minor)** — AGENTS.md 표준 정렬. 점검 후 누락 없으면 변경 없이 종료.

### Out-of-scope / 다음 스캔 후보

- Aider Watch (Q-6) — Claude Code primitive 부재로 보류
- Continue.dev `.continue/rules/` 모듈러 패턴 — Nova `.claude/rules/` 구조와 비교, 별도 트랙
- AGENTS.md spec versioning — 표준이 빠르게 진화 중, quarterly 재점검 권장
- 1차 스캔 P-3/P-4/P-6 (SKILL.md 분리, review phased, Re-plan 룰) — 별도 스프린트 진행 중

## 참고: 1차 스캔과의 보완 관계

| 영역 | 1차 (`2026-05-08-evolve-scan.md`) | 본 스캔 (보완) |
|------|-------------------------------|----------------|
| CC changelog | v2.1.132~133 핵심 (effort, SESSION_ID) | v2.1.128/129/133 worktree·plugin-url·skillOverrides |
| Anthropic 가이드 | Agent Skills (progressive disclosure) | — |
| 외부 생태계 | Trail of Bits, Cursor (1차 보강에서) | AGENTS.md 표준, Aider, Cline duration, Continue |
| 메타-evolve | P-7 소스 다양성 (적용 완료) | — |
| Nova 메모리 결합 | feedback_evaluator_rerun | feedback_nova_bypass_patterns (Q-5 직결) |
