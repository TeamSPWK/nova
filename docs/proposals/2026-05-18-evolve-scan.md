# Evolution Scan: 2026-05-18

> 날짜: 2026-05-18
> 모드: --scan
> 출처: Anthropic CC changelog v2.1.136~143, Anthropic engineering (Effective Harnesses), Multi-Agent Production 2026 (niteagent), cursor.com blog, code.claude.com

## Context

지난 스캔(2026-05-08) 이후 10일간 Claude Code는 v2.1.136부터 v2.1.143까지 **8회 패치**가 누적됐다. 그중 v2.1.139에서 **`claude agents` 뷰 + `/goal` 커맨드 + hook exec form + PostToolUse `continueOnBlock` + subagent OTEL 헤더**가 한 번에 추가됐고, v2.1.143에서 **Stop hook block cap(8) + 백그라운드 세션 모델 유지**가 들어왔다. Nova v5.43.3 기준으로 흡수 가치를 점검한다.

또한 외부에서는 Anthropic engineering 블로그 "Effective Harnesses for Long-Running Agents"와 niteagent의 "Multi-Agent in Production 2026" 분석이 발행됐다. Nova 5기둥(환경·맥락·품질·협업·진화) 관점에서 다관점 비교한다.

## 스캔 범위

| 소스 | 발견 | 관련 | 출처 |
|------|------|------|------|
| Anthropic CC changelog v2.1.136~143 | 22건 | 6건 | https://code.claude.com/docs/en/changelog |
| Anthropic engineering — Effective Harnesses for Long-Running Agents | 4건 | 1건 | https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents |
| niteagent — Multi-Agent in Production 2026 (3 patterns + P2 prompt) | 3건 | 1건 | https://niteagent.com/blog/multi-agent-production-2026/ |
| cursor.com — Agent best practices 2026 | 5건 | 1건 | https://cursor.com/blog/agent-best-practices |

**외부 소스 다양성**: ✅ Anthropic 외 3개 외부 소스 (P-7 가이드 2개 이상 충족).
**관련성 필터**: Nova 5 Pillar(환경/맥락/품질/협업/진화) 또는 commands/skills/agents/hooks/scripts 직접 영향 항목만 통과.

## Nova에 영향 없거나 이미 반영

| 변경 | Nova 상태 | 비고 |
|------|----------|------|
| `worktree.bgIsolation: "none"` (v2.1.143) | ⊘ 영향 없음 — Nova는 사용자 worktree 정책에 위임 | skip |
| Fast mode → Opus 4.7 (v2.1.142) | ⊘ 자동 — `/review --fast` 옵션 그대로 동작 | acknowledge |
| Plugin root-level `SKILL.md` 발견 (v2.1.142) | ⊘ Nova는 `skills/<name>/SKILL.md` 구조 — 변경 불필요 | skip |
| Plugin dependency enforcement (v2.1.143) | ⊘ Nova는 단일 monolithic plugin — 의존성 선언 불필요 | skip |
| MCP OAuth 동시 refresh 수정 (v2.1.136) | ⊘ Nova 코드에 OAuth flow 없음 | skip |
| `ANTHROPIC_WORKSPACE_ID` workload identity (v2.1.141) | ⊘ 엔터프라이즈 인증, Nova 영향 없음 | skip |
| `subagent_type` case/separator-insensitive (v2.1.140) | ⊘ 호환성 강화만, Nova agent 호출 정상 | acknowledge |
| P2 prompt pattern (multi-agent 2026) | ✅ Nova 이미 적용 — skill 호출 시 system prompt + structured brief + summary return | acknowledge |
| Orchestration hub-and-spoke (multi-agent 2026) | ✅ Nova `/nova:auto` 이미 이 패턴 | acknowledge |
| Effective Harness "Initializer + Coding" 분리 | ✅ Nova `/nova:setup` vs `/nova:auto` 이미 분리 | acknowledge |
| Cursor "Start simple, iterate rules" | ✅ Nova 5기둥의 진화 기둥과 일치 | acknowledge |

## 신규 관련 항목 (Nova에 흡수 가치 있음)

---

### [P-1] Stop hook block cap 인지 및 문서화 — patch

#### 발견
- **CC v2.1.143**: Stop hook이 반복 블록할 경우 8회 연속 후 강제 종료(turn 종료). 환경변수 `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`로 조정 가능.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.143)

#### Nova 현재 상태
- `hooks/stop-event.sh`는 **항상 `exit 0`** (검증: grep 결과 `exit 0` 3회만). 블로킹 안 함. 안전.
- `hooks/pre-commit-reminder.sh`는 `exit 2`로 블록하지만 **PreToolUse(Bash git\*) 타입** — Stop hook block cap 적용 대상 아님.

#### Nova 적용 방안
1. `docs/nova-rules.md`의 §훅 안전 항목에 "Stop hook은 절대 블록 금지 (exit 0 only). v2.1.143 cap=8 환경변수 인지" 한 줄 추가.
2. `tests/test-scripts.sh`에 회귀 가드 추가: `hooks/stop-event.sh`에 `exit 2` 또는 `decision.*block` 패턴이 등장하면 FAIL.

- 변경 파일: `docs/nova-rules.md` 1줄, `tests/test-scripts.sh` 회귀 가드 1개

#### 영향 범위
- 신규 회귀 가드만 추가, 동작 변경 없음.

#### 리스크
- 없음. 방어적 가드만 추가.

#### 자율 등급
**Full Auto** — 문서 1줄 + 테스트 가드.

---

### [P-2] `claude agents` 뷰 + `/goal` 커맨드 cross-reference — patch

#### 발견
- **CC v2.1.139**: `claude agents` CLI 명령으로 모든 세션(running/blocked/done) 단일 대시보드 진입. `/goal` 커맨드로 완료 조건 명시 후 다중-턴 자동 진행. **Research Preview** 등급.
- 출처:
  - https://code.claude.com/docs/en/changelog (v2.1.139)
  - https://www.buildfastwithai.com/blogs/claude-code-agent-view-guide

#### Nova 현재 상태
- `/nova:status`는 stand-alone HTML 대시보드(`skills/status-dashboard`) 제공 — Nova 진행률(Phase·Sprint·드리프트).
- `/nova:auto`는 자연어 → 설계→구현→검증 전체 사이클 — `/goal`과 의도가 유사하지만 5기둥 통합.

#### Nova 적용 방안
1. `commands/status.md` "관련" 섹션에 "단일 세션 fleet 대시보드는 `claude agents` (Anthropic 공식). Nova `/nova:status`는 프로젝트 진행률 dashboard로 직교 영역" 한 줄 추가.
2. `commands/auto.md` "관련" 섹션에 "단일 완료 조건 자동 진행은 `/goal` (CC v2.1.139+). Nova `/nova:auto`는 CPS 구조 + Generator-Evaluator 분리 + 5기둥 통합" 한 줄 추가.

- 변경 파일: `commands/status.md` 1줄, `commands/auto.md` 1줄

#### 영향 범위
- 사용자가 Anthropic 공식 도구를 발견할 수 있게 함. Nova 차별점 명확화.

#### 리스크
- 없음. 사용자 발견 가능성 ↑.

#### 자율 등급
**Full Auto** — 문서 cross-reference만.

---

### [P-3] PostToolUse `continueOnBlock` 옵션 인지 — patch

#### 발견
- **CC v2.1.139**: PostToolUse 훅에 `continueOnBlock: true` 옵션 추가. 훅이 거부 사유를 반환하면 Claude에게 피드백되어 다음 턴에 반영됨.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.139)

#### Nova 현재 상태
- Nova의 evaluator 흐름은 `agents/evaluator.md` + `skills/evaluator/SKILL.md` 기반 — **별도 서브에이전트 호출**로 PASS/FAIL 판정. 훅이 아니라 명시적 agent 호출.
- `hooks/post-tool-use-record.sh`는 metric 기록 only — 블록 안 함.

#### Nova 적용 방안
- 현재는 단순 인지만 — Nova evaluator는 hook 기반이 아니라 agent 기반이므로 즉시 적용 X.
- 향후 minor 트랙: `post-tool-use-record.sh`에서 특정 패턴(예: secret leak) 감지 시 `continueOnBlock` 활용해 Claude에 직접 피드백 가능 → 별도 deepplan 필요.
- 본 patch는 `docs/nova-rules.md`의 §훅 안전에 "PostToolUse `continueOnBlock` 옵션 인지 — 향후 자동 피드백 루프 가능성" 한 줄 메모만 추가.

- 변경 파일: `docs/nova-rules.md` 1줄

#### 영향 범위
- 문서 메모만. 동작 변경 없음.

#### 리스크
- 없음.

#### 자율 등급
**Full Auto** — 인지 문서화.

---

### [P-4] 백그라운드 세션 모델·effort 영속성 인지 — patch

#### 발견
- **CC v2.1.143**: 백그라운드 세션이 idle 후 wake할 때 model + effort level 유지. `/bg` 커맨드가 `--mcp-config`, `--settings`, `--add-dir`, `--plugin-dir`, `--strict-mcp-config`, `--fallback-model`, `--allow-dangerously-skip-permissions` 모두 보존.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.143)

#### Nova 현재 상태
- Nova `/nova:auto`는 메인 세션 또는 서브에이전트 호출 흐름. 백그라운드 세션 미사용.
- 다만 `nova:status-dashboard` 등 향후 백그라운드 폴링 기능 추가 시 영향 있음.

#### Nova 적용 방안
- `docs/specs/`(있으면) 또는 `docs/nova-rules.md` 백그라운드 정책 섹션에 "v2.1.143+ 백그라운드 세션은 model/effort 보존 — Nova가 백그라운드 호출 시 명시 지정 불요" 한 줄.

- 변경 파일: `docs/nova-rules.md` 1줄

#### 영향 범위
- 향후 백그라운드 활용 시 디자인 단순화.

#### 리스크
- 없음.

#### 자율 등급
**Full Auto** — 향후 reference용 문서화.

---

### [P-5] Auto mode `hard_deny` 정책 인지 — patch

#### 발견
- **CC v2.1.136**: `settings.autoMode.hard_deny` 옵션 추가. auto mode 분류기에서 무조건 거부할 규칙 정의 가능.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.136)

#### Nova 현재 상태
- Nova `/nova:auto`는 사용자 의도를 LLM이 분류 — 명시적 deny 규칙 미설정.
- `.env`, `*.pem`, `*accessKeys*` 등은 `CLAUDE.md` Credentials 섹션에 명시 — auto mode와 무관한 일반 가드.

#### Nova 적용 방안
- `docs/guides/auto-mode-safety.md`(신규, 작은 cheatsheet) 또는 `commands/auto.md` 끝에 "위험한 자동 실행 방지: `settings.autoMode.hard_deny`로 패턴 차단 — 예: `Bash(rm -rf*)`, `Bash(git push --force*)`" 한 섹션 추가.

- 변경 파일: `commands/auto.md` 1섹션 (~5줄)

#### 영향 범위
- 사용자가 auto mode 안전 가드를 발견하게 함.

#### 리스크
- 없음. 정보 제공.

#### 자율 등급
**Full Auto** — 문서 섹션 추가.

---

### [P-6] Hook exec form (`args: string[]`) 보안 강화 인지 — patch

#### 발견
- **CC v2.1.139**: hook 정의에 `args: string[]` 필드 추가 — 셸 없이 직접 spawn. 셸 메타문자 인젝션 위험 차단.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.139)

#### Nova 현재 상태
- `hooks/hooks.json` 모든 hook은 `command: "bash ..."` 형태(shell form). 일부는 `${CLAUDE_PLUGIN_ROOT}` 변수 보간만 사용 — 외부 입력 직접 보간 없음.
- 보안 위험은 낮음, 그러나 향후 사용자 입력이 hook 인자로 흐를 경우 exec form 전환 권장.

#### Nova 적용 방안
- `docs/nova-rules.md` §훅 안전에 "신규 hook 추가 시 인자 입력이 외부 데이터일 때 `args: string[]` exec form 사용 (CC v2.1.139+)" 한 줄.
- 본 patch는 **기존 hook 마이그레이션은 하지 않음** — 현재 안전 + 동작 검증 비용 회피.

- 변경 파일: `docs/nova-rules.md` 1줄

#### 영향 범위
- 향후 hook 작성 가이드 강화.

#### 리스크
- 없음.

#### 자율 등급
**Full Auto** — 가이드 문서화.

---

### [M-1] Subagent agent-id / OTEL 메트릭 캡처 — minor

#### 발견
- **CC v2.1.139**: 서브에이전트 API 요청에 `x-claude-code-agent-id` / `x-claude-code-parent-agent-id` 헤더 자동 부여. OTEL spans `claude_code.llm_request`에 `agent_id` / `parent_agent_id` 속성 포함.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.139)

#### Nova 현재 상태
- `hooks/record-event.sh`는 events.jsonl에 metric 기록. 현재 캡처 필드: tool, duration, error 등. **agent_id 미캡처**.
- Nova는 Generator-Evaluator 분리가 핵심 — agent 호출 체인 추적이 본질적으로 가치 있음.

#### Nova 적용 방안
1. `hooks/record-event.sh`에 `$CLAUDE_AGENT_ID` / `$CLAUDE_PARENT_AGENT_ID` 환경변수가 있으면 jsonl payload에 nullable 캡처.
2. `scripts/analyze-observations.sh`에 `--agent-chain` 옵션 (선택) — 같은 task에서 어떤 agent들이 협업했는지 시각화.
3. 회귀 가드: 신규 필드 null 허용 검증.

- 변경 파일: `hooks/record-event.sh` 1곳, `scripts/analyze-observations.sh` 1곳 (옵셔널), `tests/test-scripts.sh` 회귀 가드 1개

#### 영향 범위
- events.jsonl 스키마 확장 (nullable, 기존 분석 영향 없음).
- 사용자가 Generator-Evaluator 분리 효과를 메트릭으로 검증 가능.

#### 리스크
- jsonl 크기 약간 증가 (~80 bytes/event). 무시 가능.
- 환경변수가 모든 CC 버전에서 노출되지 않을 가능성 → nullable로 처리.

#### 자율 등급
**Semi Auto (PR)** — 신규 데이터 수집 트랙. Plan 후 별도 스프린트 권장.

---

### [M-2] Terminal sequence hook output 활용 — minor

#### 발견
- **CC v2.1.141**: hook JSON 출력에 `terminalSequence` 필드 추가 — desktop notification / window title / bell 등 컨트롤 시퀀스 emit 가능 (controlling terminal 없어도).
- 출처: https://code.claude.com/docs/en/changelog (v2.1.141)

#### Nova 현재 상태
- Nova는 `claude-notifications-go` 플러그인이 있지만 별도 — Nova 자체 notification 미보유.
- 블로커/PASS/FAIL 등 중요 이벤트에서 사용자 주의 환기 기회.

#### Nova 적용 방안
1. `hooks/stop-event.sh`에 옵셔널: `evaluator FAIL` 또는 `commit_blocked` 이벤트에 `terminalSequence`로 bell + title 변경 (`Nova: BLOCKED`).
2. 사용자 설정으로 on/off (`NOVA_DESKTOP_NOTIFY=1`).

- 변경 파일: `hooks/stop-event.sh` 1곳, `docs/nova-rules.md` 1줄 (env 명시)

#### 영향 범위
- UX 강화. 사용자가 백그라운드 작업 중 블록 상태 즉시 인지.

#### 리스크
- 일부 터미널은 bell/title escape 미지원 → 옵트인 정책으로 안전.

#### 자율 등급
**Semi Auto (PR)** — UX 개선, 사용자 테스트 후 머지.

---

### [MA-1] Effective Harness "Browser-based E2E" → ux-audit 통합 — major

#### 발견
- **Anthropic engineering**: 장기 실행 에이전트의 핵심 안티패턴은 "테스트 없이 완료 선언". 해결책으로 **Puppeteer MCP 브라우저 자동화 e2e**를 명시. 세션 시작 시 기존 기능 검증 → 단일 우선순위 feature 구현 → e2e 검증 → commit 사이클.
- 출처: https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents

#### Nova 현재 상태
- `skills/ux-audit/SKILL.md`는 5인 적대적 평가자 — 코드 기반 분석 (WCAG, Core Web Vitals 등). **브라우저 실행 검증 미포함**.
- 현재 사용 가능: `mcp__puppeteer__*` 도구 (puppeteer_navigate, screenshot, click 등) — Nova 환경에 이미 로드됨.

#### Nova 적용 방안
1. `skills/ux-audit/SKILL.md`에 G3(시각 게이트) 옵션으로 Puppeteer 검증 단계 추가:
   - URL/로컬 서버 명시 → navigate → screenshot → 5인 평가자가 코드 + 스크린샷 cross-check
2. `commands/ux-audit.md`에 `--with-browser <url>` 플래그 추가.
3. `hooks/session-start.sh` Nova 환경 확인에 puppeteer 가용성 1줄 명시 (optional).

- 변경 파일: `skills/ux-audit/SKILL.md` 1곳, `commands/ux-audit.md` 1곳, deepplan 문서 신규 1곳

#### 영향 범위
- 광범위 — 새 검증 트랙. 기존 코드 기반 분석과 직교(둘 다 유지).
- `--with-browser` 사용 시 로컬 서버 기동 가정 — 사용자가 직접 dev server 띄워야 함.

#### 리스크
- 자동 dev server 기동 시도 시 환경 변경(§3 실행 검증) 위험. **명시적 URL 요구로 회피**.
- Puppeteer 의존 — 일부 사용자 환경 미보유 시 graceful skip 필요.

#### 자율 등급
**Manual (제안만)** — 새 의존성 + 사용자 워크플로 변경. **deepplan 후 사용자 결정 필요**.

---

## 적용 우선순위 (사용자 결정용)

| Track | 항목 | 등급 | 예상 작업 |
|-------|------|------|----------|
| 1 | P-1 ~ P-6 일괄 patch (문서 메모 + 회귀 가드 1개) | Full Auto | 30분 |
| 2 | M-1 agent-id / OTEL 메트릭 캡처 | Semi Auto | 2시간 + 검증 |
| 3 | M-2 desktop notification 옵트인 | Semi Auto | 1시간 + 검증 |
| 4 | MA-1 ux-audit Puppeteer 통합 | Manual (deepplan) | 별도 스프린트 |

## 메타 평가 (Nova 5기둥 관점)

- **환경**: P-4(백그라운드 세션 영속성), P-5(auto hard_deny) — Nova 안전성 강화 가능
- **맥락**: M-2(desktop notify), P-2(`claude agents` cross-ref) — 사용자 인지 강화
- **품질**: P-1(Stop hook 가드), P-6(exec form), P-3(continueOnBlock) — 훅 안전 강화
- **협업**: M-1(agent-id 메트릭) — Generator-Evaluator 효과 측정 강화
- **진화**: MA-1(ux-audit 브라우저 통합) — Adaptive 트랙 확장

## Next Action

- 사용자 결정 1: P-1~P-6 일괄 patch 적용 여부 (예/아니오) — 적용 시 `/nova:evolve --apply` 또는 직접 patch
- 사용자 결정 2: M-1/M-2 PR 생성 여부 — minor 트랙이라 사용자 검토 후 머지
- 사용자 결정 3: MA-1 deepplan 진행 여부 — 별도 스프린트 필요

---

## 참조 출처

- [Claude Code Changelog](https://code.claude.com/docs/en/changelog)
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Multi-Agent in Production 2026 — 3 patterns](https://niteagent.com/blog/multi-agent-production-2026/)
- [Best practices for coding with agents (cursor.com)](https://cursor.com/blog/agent-best-practices)
- [Claude Code Agent View Guide](https://www.buildfastwithai.com/blogs/claude-code-agent-view-guide)
- [Claude Code v2.1.139 Release](https://claude-world.com/articles/claude-code-21139-release/)
