# Evolution Scan: 2026-06-02

> 모드: `--scan` (제안만 생성, 구현/머지 없음)
> 현재 버전: v5.51.0
> 스캐너: gh api 8/8 (정량) + curl(CHANGELOG·README, 529 우회) + grep(Nova 현재상태 전수 검증)
> Fallback: Not used (gh api 8/8 정상)
> ⚠ **WebSearch 채널 실패** — Anthropic API 529 Overloaded가 WebSearch/WebFetch/워크플로우 서브에이전트를 전 구간 차단. `gh api`(Bash)·`curl`(GitHub raw)은 Anthropic API를 거치지 않아 정상 → 서술 정보(CC CHANGELOG·README)는 curl로 직접 확보. **외부 소스 다양성은 gh api(ecosystem+harness)로 충족**, baseline fallback 트리거 조건(WebSearch 실패 AND gh api 전부 실패) 미충족.

## Context

ultracode 워크플로우로 4-카테고리 병렬 스캔을 시도했으나 **API 529 Overloaded**로 4 스캐너 전부 StructuredOutput 미호출 실패(+ 워크플로우 `args` 미바인딩). 메인 루프에서 직접 스캔으로 전환 — `gh api` 8/8 쿼리 정상, CC CHANGELOG·핵심 README는 curl로 우회 확보. **이번 사이클의 핵심 교훈: 529 과부하 시 gh api/curl이 529-내성 폴백 채널**(Anthropic API 비경유).

Nova는 CC **v2.1.152까지** 흡수됨(`anthropic-session-start-reload-skills`, `anthropic-mcp-claude-project-dir`). 따라서 **v2.1.153 ~ v2.1.160이 신규 스캔 영역**이고, 여기서 실제 갭을 추출했다.

2026-06-01 사이클의 핵심 교훈("synthesis의 'Nova 현재 상태' 주장 다수가 코드 현실과 어긋남, 독립 검증이 잡음")을 반영해 **모든 후보의 Nova 현재 상태를 grep으로 사전 검증**했다. 그 결과 후보 2건이 거짓-갭으로 사전 탈락했다(아래 명시).

## 스캔 범위

| 카테고리 | WebSearch | gh api | 발견(distinct) |
|---|---|---|---|
| Anthropic 공식 | ✗ 실패(529) | 2/2 정상 | CHANGELOG v2.1.153~160 신규 + repo 6 |
| Claude Code 생태계 | ✗ 실패(529) | 4/4 정상 | ~12 |
| 하네스 도구 | ✗ 실패(529) | 2/2 정상 | ~9 |
| AI 엔지니어링 | ✗ 실패(529) | n/a | 0 (WebSearch-only 채널 차단) |
| **외부 소스 다양성** | **OK** (ecosystem·harness gh api 통과) | | |

> AI 엔지니어링 카테고리는 WebSearch-only라 529로 0건. **이번 사이클은 고위험 출처(arxiv/블로그) 인용이 원천적으로 없음** → P-10 출처대조 대상 0건(역설적으로 환각 위험도 0). 모든 제안 근거는 Anthropic 공식 CHANGELOG(직접 read) 또는 gh-검증 GitHub 레포.

## grep 사전 검증으로 탈락한 거짓-갭 (2건)

| 후보 | 출처 | 검증(grep) | 판정 |
|---|---|---|---|
| grep이 read-before-edit 충족(v2.1.160) → Nova pre-edit-check 동기화 | CC 2.1.160 | `hooks/pre-edit-check.sh`는 read-before-edit를 **강제하지 않음**(편집 파일 수 카운트→3+ Plan 승격만). CC 변경과 무관 | **탈락** (거짓 전제) |
| plugin `defaultEnabled:false`(v2.1.154) → Nova plugin.json 적용 | CC 2.1.154 | Nova는 품질게이트 **always-on 목적** → opt-in(`defaultEnabled:false`)은 정면 역행 | **탈락** (철학 역행) |

## Nova에 이미 반영됐거나 갭 아님 (ledger 차단 / 잠재 중복 / 사용자 대기)

| 발견 (gh stars) | 분류 | 비고 |
|---|---|---|
| `thedotmack/claude-mem` (80k), `parcadei/Continuous-Claude-v3` (3.8k) | ledger 차단 | `external-context-chain-comparison` (v5.49.0) |
| Anthropic hooks/sub-agents/mcp/skills/plan-mode/worktree/memory docs | ledger 차단 | 각 `anthropic-*` row |
| `affaan-m/ECC` (202k) | 기존 분석 | 2026-04-23 competitive analysis 완료 (MEMORY) — 신규 아님 |
| `gsd-build/get-shit-done` (64k, spec-driven dev) | ⚠ 잠재 중복 | Nova CPS / `/plan` / `/design`과 개념 중첩 |
| `multica-ai/andrej-karpathy-skills` (165k), `JuliusBrussee/caveman` (67k, 토큰 65%↓) | ⚠ 잠재 중복 | session-start 토큰 예산(2026-06-01 P-4 "신중검토"와 동일 주제) |
| `LakshmanTurlapati/Review-Gate` (1.5k, "review gate rule") | ⚠ 잠재 중복 | Nova Evaluator/review 게이트 (README 529로 미확인 — 신호만) |
| `anthropics/claude-plugins-official` (29k) | 사용자 결정 대기 major | 5/27 P-4, 6/01, 6/02 재확인 — 미적용 major |
| MCP Elicitation 대화형 입력 채널 | 사용자 결정 대기 major | 5/27 P-2, 6/01 재확인 — 미적용 major |

## 직전 비채택 재제출 차단 (P-10, v5.51.0+)

ledger 미매칭이나 직전 사이클(2026-06-01/05-27) 비채택 항목과 **주제 동일 + 새 반박 근거 없음** → 제안 제외:

| 발견 (gh stars) | 직전 기각 | 새 근거 | 판정 |
|---|---|---|---|
| `anthropics/claude-code-security-review` (4.9k, 재등장) | P-5 2026-06-01 **defer** (스코프 불일치: application 취약점 vs Nova 메타파일) | 없음 | **차단** |
| `safishamsi/graphify` (58k) / `pdavis68/RepoMapper` (173) | P-9 2026-06-01 **drop** + graphify 2026-05-27 비채택 (tree-sitter+그래프 랭킹 의존성 무게) | 없음 (stars만 54k→58k) | **차단** |
| effort-aware gate (CHANGELOG `$CLAUDE_EFFORT`/`/effort ultracode` 신규 항목 존재) | P-2 2026-06-01 **defer** (NOVA_PROFILE 자산, low effort→--fast는 Generator-Evaluator 약화) | 없음 (이 세션이 ultracode여도 기각 사유 불변) | **차단** (선제) |

> P-10 작동 확인: 이번 스캔에 security-review·RepoMapper·effort 항목이 재등장했으나 **직전 기각 사유를 반박하는 새 근거가 없어** 자동 제외. 동일 논점 반복 재제출 차단 루프가 닫혔다.

---

## 신규 관련 항목 (grep 검증 통과)

### [P-1] §5/§9 환경안전 — "코드 실행 권한 부여 설정 파일 쓰기" 위험 클래스 보강 — patch

#### 발견
- 출처: CC CHANGELOG **v2.1.160** (https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — curl 직접 read, 견고)
- CC 2.1.160: `acceptEdits` 모드가 **코드 실행을 부여하는 빌드툴 설정 파일** 쓰기 전 확인 프롬프트 추가 — `.npmrc`, `.yarnrc*`, `bunfig.toml`, `.bazelrc`, `.pre-commit-config.yaml`, `.devcontainer/` 등. + shell 시작 파일(`.zshenv`/`.zlogin`/`.bash_login`)·`~/.config/git/` 쓰기 전 별도 확인. 이 파일들 쓰기 = 다음 셸/빌드 시 임의 코드 실행 경로.

#### Nova 현재 상태 (grep 검증됨)
- `docs/nova-rules.md:227` §9 "설정 파일 직접 수정 금지"는 `database.yml`, `config/*.yml` 등 **환경 전환** 관점만 예시. session-start.sh §5도 "설정 파일 직접 수정 금지. 환경변수/CLI 플래그"로 동일 환경전환 프레임.
- **갭**: "설정 파일 쓰기 = 임의 코드 실행 = 보안 위험" 각도가 부재. `docs/security-rules.md`는 Nova **자기 코드** 감사 전용(plugin/hooks/agents 카테고리)이라 사용자 프로젝트 편집 규율과 별개 — 이 갭을 커버 안 함.

#### Nova 적용 방안
§9(또는 §5)에 1줄: "코드 실행 권한을 부여하는 설정 파일(`.npmrc`/`.yarnrc`/`bunfig.toml`/`.bazelrc`/`.pre-commit-config.yaml`/`.devcontainer/`/shell 시작 파일)은 환경 전환 외에도 **임의 코드 실행 위험**이 있어 명시 확인 없이 쓰지 않는다." Anthropic이 v2.1.160에서 동일 위험을 런타임 가드로 강화한 것은 Nova §9 원칙의 수렴 검증.

#### 영향 범위
`docs/nova-rules.md` §9 문구 + 예시 보강. session-start.sh §5 한 줄 동기화 시 minor 경계. 로직 변경 없음.

#### 리스크
낮음 — 규칙 예시 보강. 과도 나열 시 token-tax. 핵심 목록만 간결히.

#### 자율 등급
Full Auto (patch) — session-start 동기화 포함 시 Semi (PR)

---

### [P-2] Nova MCP 서버 `CLAUDE_CODE_SESSION_ID` 채택 — 세션 상관 — minor

> ⚠ ledger 잠재 중복: `observability-jsonl-append-only` (기존 자산 **강화**, 중복 아님)

#### 발견
- 출처: CC CHANGELOG **v2.1.154** (curl 직접 read, 견고)
- CC 2.1.154부터 stdio MCP 서버 subprocess가 환경변수 `CLAUDE_CODE_SESSION_ID` + `CLAUDECODE=1` 수신.

#### Nova 현재 상태 (grep 검증됨)
- `mcp-server/src/util/project-dir.ts`는 `CLAUDE_PROJECT_DIR`(v2.1.141)만 사용. `CLAUDE_CODE_SESSION_ID` 미사용.
- `hooks/record-event.sh:68-86`은 **자체 생성 session.id**(`events/session.id`) 관리 → CC canonical 세션 id와 불일치.

#### Nova 적용 방안
MCP 서버가 `CLAUDE_CODE_SESSION_ID`를 읽어 작업을 태깅하고, `events.jsonl`의 session_id를 (가용 시) CC canonical id로 정렬 → CC native OTEL 텔레메트리와 교차 상관 가능. `CLAUDECODE=1`로 Nova 외부 호출과 CC-내부 호출 구분.

#### 영향 범위
`mcp-server/src/util/`, 선택적으로 `hooks/record-event.sh` session.id 소스. CC<2.1.154 graceful fallback(자체 id 유지) 필수.

#### 리스크
가치 modest — Nova는 이미 자체 session.id+tool_input 캡처 보유. 델타는 "CC canonical id 정렬로 native OTEL과 join" 한정. 과투자 금지.

#### 자율 등급
Semi Auto (PR)

---

### [P-3] orchestrator의 dynamic workflows(Workflow 도구) 활용 검토 — major

#### 발견
- 출처: CC CHANGELOG **v2.1.154** (curl 직접 read, 견고)
- CC 2.1.154 "dynamic workflows" 신설 — `Workflow` 도구가 `pipeline`/`parallel`/`loop` 결정적 제어흐름으로 수십~수백 에이전트를 백그라운드 오케스트레이션. `/workflows`로 진행 확인.

#### Nova 현재 상태 (grep 검증됨)
- `skills/orchestrator/SKILL.md`는 `Workflow` 도구 **미언급**. Architect/Dev 에이전트를 **수동 spawn**(`run_in_background:true`) + 산문 지시로 fan-out. (orchestrator는 dynamic workflows보다 먼저 설계됨)

#### Nova 적용 방안
orchestrator의 결정적 fan-out(병렬 Architect 평가, pipeline 구현→검증)을 Workflow 스크립트로 구조화 검토 — Nova "구조 > 자연어" 원칙(MEMORY `feedback_structured_over_natural_language`)과 정합. **Generator-Evaluator 독립성·CPS 구조 유지가 전제.**

#### 영향 범위
`skills/orchestrator/SKILL.md` 아키텍처. **외부 런타임 기능 의존(ultracode/dynamic-workflows 활성 시만)** → 호환성·major.

#### 리스크
- dynamic workflows 미활성 환경 → 기존 수동 spawn fallback 필수.
- **이번 스캔 자체가 Workflow 도구 dogfooding 사례** — `args` 미바인딩 + 529 과부하로 4 스캐너 전부 실패. 통합 전 신뢰성/실패모드 검증 필요.
- CPS 구조·Evaluator 독립성 손실 시 Nova 최강 기둥 약화(MUST NOT 근접).

#### 자율 등급
Manual (제안만) — 사용자 결정 대기

---

### [P-4] Generator 문서 출력 근거/slop 게이트 — evolve P-10의 일반 문서 확장 — minor

> ⚠ ledger 잠재 중복: `evolve-source-verification` (evolve 한정 → 일반 문서로 확장 각도)

#### 발견
- 출처: `github.com/athola/claude-night-market` (**299 stars, README curl 검증됨**) + Nova 자체 evolve P-10(v5.51.0)
- night-market `scribe:slop-detector`: 문서 ship 전 4층 검사 — P0 critical patterns / document economy / sentence-level slop / **evidence-backed claims**. CONSTITUTION.md가 충돌 스킬 오버라이드(PreToolUse 훅 강제).

#### Nova 현재 상태 (grep 검증됨)
- `skills/evaluator/SKILL.md`는 코드 중심 + arXiv 2404.13076 self-bias 인지(이미 보유). `eval-checklist`에 "대안 근거"(:338) 있으나 **일반 문서 산출물(가이드/README/proposal)**의 근거 없는 단정·과장·미인용 게이트는 없음.
- evolve P-10(v5.51.0 `evolve-source-verification`)은 **evolve 한정** evidence 게이트 — 일반 문서로는 미확장. (2026-06-01 arxiv 3/3 환각이 바로 evidence-backed claims 실패였음)

#### Nova 적용 방안
Evaluator/`/review`에 문서 산출물 대상 경량 체크 1항 검토: "근거 없는 단정·과장 표현·미인용 외부 주장 플래그". night-market처럼 별도 무거운 detector 신설이 아니라 **기존 eval-checklist 1항 추가** 수준으로 보수적 흡수.

#### 영향 범위
`docs/eval-checklist.md`, `skills/evaluator/SKILL.md`. 코드 게이트와 혼선·과검출 주의.

#### 리스크
가치 modest — evolve P-10과 부분 중복. 일반 문서 slop 검출은 false positive·노이즈 위험. "1항 경량 추가" 경계 엄수.

#### 자율 등급
Semi Auto (PR)

---

## 요약

| # | 제안 | 수준 | 출처 | 출처 검증 | 권고 |
|---|---|---|---|---|---|
| P-1 | §9 코드실행 설정파일 쓰기 위험 보강 | patch | CC v2.1.160 | ✅ 견고 | **채택 1순위** (가장 깨끗한 갭) |
| P-2 | MCP `CLAUDE_CODE_SESSION_ID` 세션 상관 | minor | CC v2.1.154 | ✅ 견고 | 검토 (가치 modest, ⚠잠재중복) |
| P-3 | orchestrator의 Workflow 도구 활용 | major | CC v2.1.154 | ✅ 견고 | 사용자 결정 대기 (런타임 의존) |
| P-4 | 문서 근거/slop 게이트 확장 | minor | night-market 299⭐ + 자체 | ✅ 견고 | 검토 (⚠잠재중복 evolve P-10) |

> **발견(distinct) ~30 → 신호 통과 ~20 → ledger 차단 7 + 직전 비채택 차단 3 + 거짓-갭 탈락 2 → MUST 통과 4**
> `--scan` 모드 종료. 구현/머지 없음. **P-1 patch가 즉시 채택 1순위** (Anthropic 공식 수렴 검증, 거짓-갭 아님 확정).
> Ledger: `dev/docs/proposals/_ABSORBED.md` (채택·머지 시 `release.sh` `NOVA_LEDGER_APPEND`로 자동 append).
