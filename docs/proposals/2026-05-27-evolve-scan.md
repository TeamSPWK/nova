# Evolution Scan: 2026-05-27

> 날짜: 2026-05-27
> 모드: --scan (8 gh api 병렬 + 4 WebSearch)
> 윈도우: 2026-05-23 ~ 2026-05-27 (Anthropic·생태계·하네스), 2026-05-23 ~ 2026-05-27 (AI 엔지니어링 + 미흡수 잔존)
> 직전 스캔: 2026-05-23 (`docs/proposals/2026-05-23-evolve-scan.md`)
> Nova 현재 버전: v5.48.1

## Context

직전 스캔(05-23) 이후 4일 동안 Claude Code는 v2.1.149→v2.1.152로 패치가 누적됐다. v2.1.152에서 **SessionStart hook에 `reloadSkills: true` + `sessionTitle` 동적 설정**이 들어왔고, 이전 스캔이 다루지 않은 **MCP Elicitation(v2.1.117)**, **MCP `CLAUDE_PROJECT_DIR` 환경변수(v2.1.141)** 두 미흡수 잔존 항목을 함께 점검한다.

외부 생태계에서는 **anthropics/claude-plugins-official** 공식 디렉토리(28k stars)가 활발히 갱신되고, **thedotmack/claude-mem**(79k stars)와 **parcadei/Continuous-Claude-v3**(3.8k stars)가 Nova context-chain·ledger 패턴과 직접 경쟁 영역을 형성했다.

Nova v5.48.1 기준 흡수 가치를 4 Pillar(Structured·Consistent·X-Verification·Adaptive) 관점에서 점검한다.

## 스캔 범위

| 채널 | 발견 | 신호 통과 | ledger 차단 | 관련 | 출처 |
|------|------|----------|------------|------|------|
| Anthropic 공식 (gh api 2 + WebSearch) | 16건 | 16건 | 8건 | 3건 | `anthropics/claude-plugins-official`, CHANGELOG v2.1.117~152 |
| 생태계 (gh api 4 + WebSearch) | 40건 | 28건 | 5건 | 3건 | `claude-mem`, `Continuous-Claude-v3`, `claude-plugins-official` |
| 하네스 (gh api 2 + WebSearch) | 20건 | 6건 | 0건 | 0건 | aider/cursor — Nova 직접 영향 없음 |
| AI 엔지니어링 (WebSearch) | 4건 | 4건 | 1건 | 1건 | Anthropic 3-feedback 패턴 (rules/visual/judge) |

**스캔 총합 80건 → 신호 통과 54건 → ledger 차단 14건 → 관련 7건 (필터율 91%, 흡수 후보 5건)**

**외부 소스 다양성**: ✅ Anthropic 외 3개 외부 소스 (claude-mem · Continuous-Claude-v3 · awesome-claude-skills 리뷰). MUST 2개 충족.

**Fallback**: Not used — Live scan 정상 (HTTP 200 + 결과 ≥1건, 모든 8 gh api 쿼리).

## Nova에 이미 반영됐거나 갭 아님

| 변경 | Nova 상태 | 비고 |
|------|----------|------|
| Stop/SubagentStop `background_tasks`+`session_crons` (v2.1.145) | ✅ 이전 스캔 P-1로 다룸 | `docs/proposals/2026-05-23-evolve-scan.md` |
| OTEL `agent_id`/`parent_agent_id` (v2.1.145+147) | ✅ 이전 스캔 P-3로 다룸 | 동일 |
| `/code-review --comment` (v2.1.147) | ✅ 이전 스캔 P-9로 다룸 | 동일 |
| multi-Agent frontmatter 버그 (v2.1.147) | ✅ 이전 스캔 P-2로 다룸 | 동일 |
| `/usage` per-category breakdown (v2.1.149) | ✅ 이전 스캔 P-7로 다룸 | 동일 |
| PostToolUse `duration_ms` (v2.1.147) | ✅ 2026-05-07 스캔에서 적용 검토 완료 (record-event.sh 캡처) | measurement-spec.md |
| Anthropic 3-feedback 패턴(rules/visual/judge) | ✅ 모두 흡수 — tests + visual-intent-verify-g1-g3 + evaluator | ledger anthropic-sub-agents + visual-intent-verify-g1-g3 |
| `affaan-m/ECC` (195k stars) | ✅ 이전 분석 완료 (MEMORY: `project_nova_competitive_analysis_2026_04_23`) | 추가 분석 보류 |
| `andrej-karpathy-skills` (158k stars) | ✅ Nova CLAUDE.md AI Coding Discipline 절에 흡수 | global CLAUDE.md |

## 신규 관련 항목 (Nova에 흡수 가치 있음)

### [P-1] SessionStart `reloadSkills: true` + `sessionTitle` 채택 — patch

#### 발견
- **CC v2.1.152**: SessionStart hook이 `hookSpecificOutput`에 `reloadSkills: true` 반환 시 세션 시작/재개마다 스킬 디렉토리를 동적 재로드, `sessionTitle` 필드로 tmux pane/터미널 제목 동적 설정.
- 출처: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.152)

#### Nova 현재 상태
- `hooks/session-start.sh`는 additionalContext만 반환 — `reloadSkills` 미사용.
- Nova 플러그인 업데이트 시 사용자가 `/reload-plugins` 또는 `claude` 재시작 없으면 신규 스킬이 자동 인덱스되지 않음 (MEMORY: `reference_claude_code_hooks_mechanics.md`).
- `sessionTitle` 미사용 — 멀티 프로젝트 동시 세션 시 어느 창이 어느 프로젝트인지 식별 어려움.

#### Nova 적용 방안
1. `hooks/session-start.sh`에 `hookSpecificOutput.reloadSkills=true` 옵션 추가 — 사용자 환경변수 `NOVA_AUTO_RELOAD_SKILLS=1` 시에만 켜짐 (기본 off, 호환성 보존).
2. `sessionTitle`을 "Nova: {project_name}" 형식으로 동적 설정 — `git rev-parse --show-toplevel | xargs basename` 결과 활용.
3. `tests/test-scripts.sh`에 회귀 가드: session-start.sh JSON 출력에 `reloadSkills`/`sessionTitle` 키 부재 시 통과 (기본 off), `NOVA_AUTO_RELOAD_SKILLS=1` 시 정확히 포함되는지 검증.
4. `docs/nova-rules.md`에 "신규 스킬 추가 시 사용자가 `claude` 재시작 없이 자동 인덱스 (NOVA_AUTO_RELOAD_SKILLS=1 환경)" 한 줄.

- 변경 파일: `hooks/session-start.sh` 약 10줄, `tests/test-scripts.sh` 회귀 가드 1개, `docs/nova-rules.md` 1줄.

#### 영향 범위
- Adaptive Pillar 강화. 플러그인 업데이트 발견성 ↑. 사용자가 신규 Nova 기능을 "재시작 후" 발견하는 갭 해소.
- 자가 진화(`/nova-dev:evolve --auto`)가 적용한 신규 스킬이 즉시 활성화.

#### 리스크
- `reloadSkills=true`는 매 세션 시작/재개마다 스킬 디렉토리 스캔 → I/O 비용. 환경변수 opt-in으로 회피.
- CC v2.1.151 이하 사용자는 무시됨 (필드 미지원) — graceful no-op.

#### 자율 등급
**Full Auto** — hook 출력 옵셔널 필드 추가 + 환경변수 opt-in.

---

### [P-2] MCP Elicitation 흡수 — Nova MCP 대화형 입력 채널 — major

#### 발견
- **CC v2.1.117**: MCP 서버가 `elicitation/create` 요청으로 도구 호출 중간에 사용자에게 구조화 입력 요청 가능. Anthropic Elicitation/ElicitationResult hooks로 응답 인터셉트 가능.
- 출처: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.117), https://docs.anthropic.com/en/docs/claude-code/mcp

#### Nova 현재 상태
- `mcp-server/src/` Nova MCP는 9개 도구 제공(orchestrate/orchestration_start/orchestration_status/orchestration_update/get_rules/get_state/get_commands/repo_preflight/x_verify). 모두 **단방향 query/update** — 도구 호출 중간에 사용자 결정을 요청할 수 없음.
- `/nova:plan` Phase 중간에 "이 결정 사용자 확인 필요" 시점이 있어도 `AskUserQuestion` 도구 우회만 가능 (Nova MCP가 직접 요청 불가).
- ledger `anthropic-mcp` 매칭: ⚠ **잠재 중복** — Nova MCP 서버 자체는 흡수했지만 elicitation 서브패턴은 미흡수. 본 제안서에서 신규 흡수로 명시.

#### Nova 적용 방안
1. `mcp-server/src/` 신규 도구 `interactive_decision` 추가 — `elicitation/create` 요청으로 사용자에게 구조화 input 요청 (예: "MCP alwaysLoad: true|false", "rubric 항목 우선순위 1-5").
2. `commands/plan.md` Phase 2(설계 분기)에 "분기 결정 시 `mcp__plugin_nova_nova__interactive_decision` 호출 권장 — 사용자 답변 즉시 plan 문서에 기록" 한 절.
3. `commands/auto.md` Phase 4(자율 범위 결정)에 동일 패턴.
4. `skills/orchestrator/SKILL.md`에 "lead agent가 major 변경 직전 `interactive_decision` 호출로 사용자 결정 명시 받기" 추가.

- 변경 파일: `mcp-server/src/index.ts` 또는 `mcp-server/src/tools/` 신규 약 80줄, `commands/plan.md`+`commands/auto.md`+`skills/orchestrator/SKILL.md` 각 1 단락, `tests/test-scripts.sh` MCP tool 회귀 가드.

#### 영향 범위
- Consistent Pillar 강화. "AI는 제안, 인간은 결정" 원칙(CLAUDE.md)을 도구 수준에서 강제.
- /nova:auto의 major 변경 자동 통과 위험을 도구 수준에서 차단.

#### 리스크
- MCP 서버 코드 변경은 plugin update만으로 자동 적용 (✅ MEMORY `feedback_no_manual_setup.md` 부합).
- elicitation 지원 안 하는 MCP 클라이언트(non-Claude-Code)에서 graceful fallback 필요 — capability negotiation 패턴 적용.
- CC v2.1.116 이하 사용자는 도구 호출 시 error — Nova MCP 도구 등록 시 minimum CC version 명시 (`mcp-server/package.json` engines).

#### 자율 등급
**Manual** — MCP 서버 코드 변경 + 도구 신설 = 호환성 영향. 사용자 결정 후 디자인 → 구현 → 머지.

---

### [P-3] MCP 서버 stdio 환경변수에 `CLAUDE_PROJECT_DIR` 활용 — patch

#### 발견
- **CC v2.1.141**: stdio MCP 서버 시작 시 `CLAUDE_PROJECT_DIR` 환경변수 자동 주입 — hook과 동일 동작.
- 출처: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.141)

#### Nova 현재 상태
- `mcp-server/src/`의 `mcp__plugin_nova_nova__get_state`·`repo_preflight`는 `project_path` 인자가 미지정이면 `process.cwd()`를 사용 — 사용자가 worktree 또는 다른 디렉토리에서 호출 시 `process.cwd()`가 의도와 다를 수 있음.
- `mcp__plugin_nova_nova__get_state`에 `advisory`로 "project_path 미지정 시 cwd 사용" 경고 있지만 실제 프로젝트 루트가 아닐 수 있음.

#### Nova 적용 방안
1. `mcp-server/src/tools/get-state.ts`(또는 동등 파일)의 `project_path` 기본값을 `process.env.CLAUDE_PROJECT_DIR || process.cwd()` 순서로 변경.
2. `repo_preflight` 동일 적용.
3. `docs/guides/mcp-server.md`(또는 inline 주석)에 "CC v2.1.141+ 사용자는 worktree 진입 직후 호출해도 본래 프로젝트 루트 기준으로 동작" 한 줄.

- 변경 파일: `mcp-server/src/tools/*.ts` 2개 파일 약 2줄씩, doc 1줄.

#### 영향 범위
- worktree 사용자(`skills/worktree-setup`)에서 MCP 호출 정확성 ↑.
- 사용자 보고 "STATE.md 못 찾음·get_state 빈 결과" 갭 차단.

#### 리스크
- CC v2.1.140 이하 사용자는 환경변수 미주입 → `process.cwd()` fallback. graceful.

#### 자율 등급
**Full Auto** — 환경변수 우선순위 변경 + 문서 1줄.

---

### [P-4] anthropics/claude-plugins-official 디렉토리 등록 검토 — major

#### 발견
- **anthropics/claude-plugins-official** (28k stars, 활발히 갱신): "Official, Anthropic-managed directory of high quality Claude Code Plugins". 등록 방식은 PR로 plugin 메타데이터 추가.
- 추가 채널: **anthropics/claude-plugins-community** (131 stars): "Community plugin marketplace ... submit plugins at clau.de/plugin-directory-submission".
- 출처: https://github.com/anthropics/claude-plugins-official , https://github.com/anthropics/claude-plugins-community

#### Nova 현재 상태
- Nova는 `TeamSPWK/nova` 단독 배포 — 사용자가 `/plugin add TeamSPWK/nova` 직접 호출해야 발견 가능.
- README.md에 등록 채널 노출 없음. nova-landing(클라우드 dispatch 동기화)은 자체 채널.
- ledger 매칭 없음 — 신규 항목.

#### Nova 적용 방안
1. **공식 디렉토리(anthropics/claude-plugins-official) 등록**: clau.de/plugin-directory-submission 가이드 검토 후 PR. Anthropic 큐레이션 기준 충족 점검 (품질 게이트 통과, 문서 완비, 호환성 명시).
2. **커뮤니티 디렉토리 동시 등록**: anthropics/claude-plugins-community에 동시 등록 (낮은 기준).
3. README.md(영문)에 "Available via Anthropic Plugin Directory: `/plugin install nova`" 추가 (등록 후).
4. nova-landing 푸터에 동일 배지.

- 변경 파일: 외부 PR 1~2건, README.md 1줄, nova-landing 1줄.

#### 영향 범위
- 노출 채널 확대 — Nova 사용자 발견 경로 다양화.
- Anthropic 큐레이션 통과 = Nova 품질 외부 검증 (Adaptive Pillar 외부 시그널).

#### 리스크
- Anthropic 큐레이션 기준이 명시되지 않음 — PR 거절 시 사유 분석 후 갭 보완 필요.
- 디렉토리 등록 후 갱신 lag(공식 디렉토리가 Nova 최신 버전을 늦게 반영) 가능.
- 외부 PR이므로 자율 머지 X — 사용자 결재 후 진행.

#### 자율 등급
**Manual** — 외부 PR + 노출 정책 결정. 사용자 결재 필수.

---

### [P-5] 외부 ledger 패턴 도구와 차별점 명시 (claude-mem / Continuous-Claude-v3) — minor

#### 발견
- **thedotmack/claude-mem** (79k stars): "Persistent Context Across Sessions for Every Agent — captures everything ... compresses ... injects relevant context". ChromaDB·SQLite·mem0·supermemory 등 외부 vector DB 활용.
- **parcadei/Continuous-Claude-v3** (3.8k stars): "Context management for Claude Code. **Hooks maintain state via ledgers and handoffs.** MCP execution without context pollution. Agent orchestration with isolated context windows."
- 출처: https://github.com/thedotmack/claude-mem , https://github.com/parcadei/Continuous-Claude-v3

#### Nova 현재 상태
- Nova `skills/context-chain` + NOVA-STATE.md + `.nova/events.jsonl`이 **동일 영역**을 다른 방식으로 해결: append-only JSONL + 본문 스냅샷 손편집 + Stop hook auto-render (v5.44.0+).
- Nova는 외부 vector DB 의존성 0 — MEMORY `feedback_api_key_optional_principle.md` 부합.
- ledger 매칭: `observability-jsonl-append-only` 부분 매칭 → ⚠ 잠재 중복 표기, 단 비교 분석 결과물(차별점 문서)은 신규.

#### Nova 적용 방안
1. `docs/comparison/context-chain-vs-external.md` 신설 — Nova context-chain vs claude-mem vs Continuous-Claude-v3 차별점 표 (의존성, 시계열 모델, 압축 전략, lock-in 위험).
2. README.md "Why Nova?" 절에 "외부 vector DB 의존성 0 — events.jsonl append-only + Stop hook 자동 렌더" 한 줄.
3. `skills/context-chain/SKILL.md`에 "외부 대안: claude-mem(vector DB)·Continuous-Claude-v3(ledger+handoffs). Nova 선택 사유는 docs/comparison/ 참조" 한 줄.

- 변경 파일: `docs/comparison/context-chain-vs-external.md` 신설(약 80줄), README.md 1줄, `skills/context-chain/SKILL.md` 1줄.

#### 영향 범위
- 사용자 발견 시 차별점 즉시 확인 가능. 경쟁 대안 인지 → Nova 선택 사유 명확화.
- evidence-first 정체성(MEMORY: `feedback_evidence_first_identity.md`) 강화 — 어휘 주장이 아닌 차이점 명시.

#### 리스크
- 비교 문서는 시간이 지나면 stale — 분기마다 갱신 필요. 갱신 의무를 `commands/evolve.md`에 흡수.
- 외부 도구 평가가 주관적일 수 있음 — 객관 기준(의존성/lock-in) 위주로 작성.

#### 자율 등급
**Semi Auto (PR)** — 신규 비교 문서 + 2 파일 1줄씩.

---

## 비채택 / 보류

| 항목 | 판단 |
|------|------|
| `LakshmanTurlapati/Review-Gate` (1.5k stars, single-request 5x) | ⊘ 비채택 — Nova Generator-Evaluator 분리 약화 위험. /nova:review의 multi-pass 철학과 충돌 |
| `ciembor/agent-rules-books` (1.6k stars, Clean Code/DDD rules) | ⏸ 보류 — Nova `skills/claude-md` 영역과 직교, 사용자 가이드 보강 후보 (낮은 우선순위) |
| `gsd-build/get-shit-done` (63k stars, meta-prompting/spec-driven) | ⏸ 보류 — /nova:design CPS와 영역 중복, 직접 흡수 가치는 낮음 (디자인 결정 분기 비교만) |
| `athola/claude-night-market` TDD enforcement hooks (291 stars) | ⏸ 보류 — Nova 품질 게이트는 일반 TDD가 아닌 5차원 검증. TDD-only는 별도 사용자 워크플로우 |
| `zilliztech/claude-context` (11k stars, semantic code search MCP) | ⏸ 보류 — Nova MCP는 9개 도구로 충분, 코드 검색은 Claude Code 내장 Grep으로 커버 |
| `nextlevelbuilder/ui-ux-pro-max-skill` (83k stars, UI/UX 디자인) | ⊘ 비채택 — Nova는 visual-intent-verify-g1-g3로 검증 영역만 담당, 디자인 생성은 직교 |
| `safishamsi/graphify` (54k stars, knowledge graph from code) | ⊘ 비채택 — 외부 의존성(tree-sitter, graphrag) 큼. MEMORY `feedback_api_key_optional_principle.md` 위배 |
| Hook `updatedToolOutput` 전 도구 확장 (v2.1.144) | ⏸ 직전 스캔에서 다룸 — Generator-Evaluator 약화 위험 |

## 리스크 요약

- P-1(SessionStart reloadSkills) · P-3(MCP CLAUDE_PROJECT_DIR) · P-5(비교 문서)는 **plugin update만으로 자동 적용** — MEMORY `feedback_no_manual_setup.md` 부합.
- P-2(MCP Elicitation) · P-4(공식 디렉토리 등록)는 사용자 결재 필수 — Manual 등급.
- API 키 추가 의존성 없음 (MEMORY `feedback_api_key_optional_principle.md` 부합).
- 기존 회귀 테스트(1031)에 영향: P-1에 가드 추가 필요 (1개 신규 테스트).

## Apply 모드 진행 시

`/nova:evolve --apply`로 호출 시 권장 순서:
1. **P-3** (MCP CLAUDE_PROJECT_DIR) — 가장 단순, 환경변수 fallback 추가만.
2. **P-1** (SessionStart reloadSkills) — opt-in 환경변수, 회귀 영향 0.
3. **P-5** (비교 문서) — 새 파일 1개, 기존 파일 1줄씩.

각 적용마다 Gate 1(tests) → Gate 2(/nova:review --fast) 통과해야 다음 진입.

## 다음 단계 권고

1. **즉시 (Full Auto)**: P-1(SessionStart reloadSkills), P-3(MCP CLAUDE_PROJECT_DIR). 두 항목 묶음 PR.
2. **단기 (Semi Auto, 단독 PR)**: P-5(비교 문서) — 신규 docs/comparison/ 디렉토리 + README 갱신.
3. **중기 (Manual, 사용자 결재 필요)**: P-4(공식 디렉토리 등록) — 외부 PR + 노출 정책.
4. **중기 (Manual, 디자인 결정 필요)**: P-2(MCP Elicitation) — Nova MCP 도구 신설 = 호환성 영향. deepplan 후보.
5. **추적**: ciembor/agent-rules-books · gsd-build/get-shit-done — 분기 1회 비교 재평가.

본 스캔의 흡수 우선순위는 **P-3 → P-1 → P-5 → P-4 → P-2** 순. **즉시 흡수 가능한 P-3/P-1은 Adaptive Pillar 직접 강화** (플러그인 업데이트 발견성 + worktree 호환성). P-4는 외부 노출 채널, P-2는 협업 Pillar 장기 강화.

## ledger 갱신 (--apply/--auto 머지 시)

minor/major 머지 직후 `dev/docs/proposals/_ABSORBED.md`에 행 추가 예정:
- P-1 머지 시: `| anthropic-session-start-reload-skills | https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md | v5.49.0 | hooks/session-start.sh | active |` (단, P-1은 patch라 ledger 영향 0 — 정책상 skip)
- P-2 머지 시: `| anthropic-mcp-elicitation | https://docs.anthropic.com/en/docs/claude-code/mcp | v6.0.0 | mcp-server/src/tools/interactive-decision.ts | active |`
- P-3 머지 시: patch — ledger 영향 0.
- P-4 머지 시: `| anthropic-plugin-directory-registration | https://github.com/anthropics/claude-plugins-official | v5.49.0+ | external PR | active |`
- P-5 머지 시: `| external-context-chain-comparison | https://github.com/thedotmack/claude-mem , https://github.com/parcadei/Continuous-Claude-v3 | v5.49.0 | docs/comparison/context-chain-vs-external.md | active |`
