# Evolution Scan: 2026-05-23

> 날짜: 2026-05-23
> 모드: --scan (team agent 4-scanner parallel)
> 윈도우: 2026-05-16 ~ 2026-05-23 (Anthropic·생태계·하네스), 2026-04-23 ~ 2026-05-23 (AI 엔지니어링)
> 직전 스캔: 2026-05-18 (`docs/proposals/2026-05-18-evolve-scan.md`)

## Context

직전 스캔 이후 5일간 Claude Code는 v2.1.144→v2.1.149로 6회 패치가 누적됐다. v2.1.145에서 **Stop/SubagentStop hook input에 `background_tasks`+`session_crons` 필드**, **OTEL tool span에 `agent_id`/`parent_agent_id` 표준 attribute**, **`claude agents --json` 스크립팅 출력**이 한 번에 들어왔고, v2.1.147에서 **공식 `/code-review --comment` (구 /simplify) + 플러그인 agent `tools:` frontmatter 드롭 버그 수정**, v2.1.149에서 **`/usage` per-category(skills/subagents/plugins/MCP) breakdown**이 추가됐다.

외부에서는 **OpenHands 1.7.0**(Critic Result Display 인라인 + TaskToolSet 위임), **Cursor 3.5**(Multi-repo Automations + No-repo Marketplace Templates), **MCP 2026-07-28 RC 22-SEP 묶음**(SEP-2484 Conformance·SEP-2596 Deprecation Policy 포함)이 나왔고, AI 엔지니어링 쪽에서는 **Anthropic Managed Agents "Outcomes" 패턴**(grader rubric + max_iterations + structured feedback)과 **arXiv 2605.12280 AEGIS**(iterative audit convergence, scope-expansion ladder), **Eugene Yan "Working with AI"**(lazy-loaded guides + pair-programmer drift-watch + transcript mining)가 누적됐다.

Nova v5.47.6 기준 흡수 가치를 4 Pillar(Structured·Consistent·X-Verification·Adaptive) 관점에서 점검한다.

## 스캔 범위

| 소스 | 발견 | 관련 | 출처 |
|------|------|------|------|
| Anthropic CC changelog v2.1.144~149 | 5건 | 5건 | https://code.claude.com/docs/en/changelog |
| Claude Code 생태계 (MCP SEP + awesome-* + plugin frontmatter 버그) | 7건 | 4건 (3건 anthropic과 중복) | https://github.com/modelcontextprotocol/modelcontextprotocol , https://github.com/anthropics/claude-code |
| 외부 하네스 — OpenHands 1.7.0 / Cursor 3.5 | 4건 | 3건 | https://www.openhands.dev/blog/openhands-product-update---may-2026 , https://cursor.com/changelog/05-20-26 |
| AI 엔지니어링 — Anthropic Managed Agents / arXiv / Eugene Yan | 5건 | 5건 | https://platform.claude.com/cookbook/managed-agents-cma-verify-with-outcome-grader , https://arxiv.org/abs/2605.12280 , https://eugeneyan.com/writing/working-with-ai/ |

**스캔 총합 21건 → 중복 3건 제거 → 실효 18건 → 관련 10건 (필터율 56%, 흡수 후보 10)**

**외부 소스 다양성**: ✅ Anthropic 외 4개 외부 소스 (OpenHands · Cursor · MCP SEP repo · arXiv · Eugene Yan blog). P-7 가이드의 "최소 2개 외부 소스" 의무 충족.

**관련성 필터**: Nova 4 Pillar 또는 commands/skills/agents/hooks/scripts 직접 영향 항목만 통과. Nova가 이미 갖춘 패턴(Generator-Evaluator 분리, CPS, sub-agent spawn, NOVA-STATE 컨텍스트 체인, plugin SKILL.md 구조)은 재발견 항목으로 카운트하지 않음.

## Nova에 영향 없거나 이미 반영

| 변경 | Nova 상태 | 비고 |
|------|----------|------|
| `worktree.bgIsolation: "none"` (v2.1.143~145 후속) | ⊘ Nova는 사용자 worktree 정책에 위임 | skip |
| `claude agents --json` 멀티-세션 fleet 스크립팅 (v2.1.145) | ⊘ Nova `/nova:status`는 프로젝트 단위 진행률 — 직교 영역 | skip (직전 P-2 cross-ref로 이미 처리) |
| Cursor 3.5 — No-repo Marketplace Templates | ⊘ Nova "워크플로우 시드 hub" 미존재 — 흡수 비용 > 효용 | skip |
| MCP 2026-07-28 RC stateless transport (major) | ⏸ Nova는 MCP 서버 제공 X / 외부 MCP 호출 추적 필요 | watch |
| Anthropic "Dreaming" 자동 메모리 큐레이션 | ⏸ 자동 갱신은 STATE 드리프트 위험 — 사용자 검수 의무화 후 재검토 | defer |
| OpenHands TaskToolSet 1급 위임 도구 | ⏸ work-item registry 스키마 영향 — 디자인 결정 선행 필요 | defer (deepplan 후보) |
| MCP SEP-2596 12-month Deprecation Policy | ⏸ Nova 현재 폐기 항목 적음 — 폐기 항목 누적 시 재검토 | defer |
| Cursor 3.5 — Multi-repo Automations | ⏸ SWK 워크스페이스 사용자 워크플로우 영역 — Nova 자체 변경 아님 | defer |
| Eugene Yan — secondary pair-programmer drift-watch / transcript mining | ⏸ jury/evolution 스킬 결과를 강화하나 적용 비용 큼 — 단발 적용보다 measurement-closed-loop 연계로 재검토 | defer |

---

## 신규 관련 항목 (Nova에 흡수 가치 있음)

### [P-1] Stop/SubagentStop hook input에 `background_tasks` + `session_crons` 채택 — patch

#### 발견
- **CC v2.1.145**: Stop·SubagentStop 훅 stdin JSON에 진행 중 백그라운드 작업 목록과 등록된 cron 목록이 함께 전달됨.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.145), https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md

#### Nova 현재 상태
- `hooks/stop-event.sh`는 stdin payload를 읽지만 `background_tasks`·`session_crons` 미인지.
- `skills/checkpoint/SKILL.md`는 "완료 의심" 항목을 추측 기반으로 분류 — 백그라운드 잔존을 정확히 감지 못 함 (MEMORY: result_over_diagnosis).

#### Nova 적용 방안
1. `hooks/stop-event.sh`에서 stdin JSON의 `background_tasks[]`·`session_crons[]` 파싱 → `.nova/events.jsonl`에 `stop_with_background` 이벤트로 append (필드: `bg_count`, `cron_count`).
2. `skills/checkpoint/SKILL.md` Step 1에 "stop-event payload에 background_tasks 잔존 시 해당 work-item은 자동 `검증불가` 분류" 규칙 추가.
3. `tests/test-scripts.sh`에 회귀 가드: 시뮬레이션 stdin으로 background_tasks 주입 시 stop-event.sh가 해당 필드를 events.jsonl에 기록하는지 검증.

- 변경 파일: `hooks/stop-event.sh` 약 10줄, `skills/checkpoint/SKILL.md` 1 단락, `tests/test-scripts.sh` 회귀 가드 1개.

#### 영향 범위
- checkpoint 정직성 강화. NOVA-STATE 드리프트 진단 정확도 ↑.

#### 리스크
- stop-event payload 미주입 환경(Nova 단독 호출 시뮬레이션)에서 graceful skip 필요. safe-default(exit 0) 패턴 유지.

#### 자율 등급
**Semi Auto (PR)** — hook 로직 변경 + skill 규칙 변경 동반.

---

### [P-2] 플러그인 agent `tools:` frontmatter multi-Agent 드롭 버그 회귀 점검 — patch

#### 발견
- **CC v2.1.147**: `tools:` frontmatter에 여러 `Agent(...)` 타입을 선언하면 마지막 항목만 남고 나머지가 사라지던 회귀가 수정됨.
- 출처: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.147)

#### Nova 현재 상태
- Nova `agents/*.md` 6종 (v5.47.5/6 동기화 직후) — 다중 `Agent(...)` 선언 여부와 v2.1.146 이전 사용자에서의 작동 가능성을 직접 점검해야 함.
- `scripts/audit-agent-tools.sh`(v5.47.6에서 3축 동기화 게이트 완성)는 frontmatter ↔ plugin.json ↔ nova-meta.json 일관성은 검증하지만 "multi-Agent 선언이 실제로 다 살아있는가"는 검증하지 않음.

#### Nova 적용 방안
1. `agents/*.md` 6종에서 `Agent(...)` 다중 선언 사례 grep → 있으면 v2.1.146 이전 사용자에 reporting 필요 (changelog cross-ref).
2. `scripts/audit-agent-tools.sh`에 "frontmatter `tools:`에 동일 base type(Agent/Read/Edit 등)이 2회 이상 선언되면 plugin.json per_agent에도 동일 횟수 등장하는지" 회귀 가드 추가.
3. `docs/nova-rules.md`의 §plugin 동기화 항목에 "CC v2.1.146 이하 사용자: `tools:`에 동일 base type 중복 선언 금지" 한 줄.

- 변경 파일: `scripts/audit-agent-tools.sh` 회귀 가드 약 5줄, `docs/nova-rules.md` 1줄.

#### 영향 범위
- 직전 v5.47.5/6과 인접 영역 — 3축 동기화 게이트의 누락된 차원(중복 카운트) 보완.

#### 리스크
- v2.1.146 이하 사용자가 멀티-Agent 선언을 쓰지 않으면 동작 변경 0. 회귀 가드는 정상 케이스를 통과시킨다.

#### 자율 등급
**Full Auto** — 회귀 가드 + 문서 1줄.

---

### [P-3] OTEL `agent_id` / `parent_agent_id` 표준 attribute 채택 — minor

#### 발견
- **CC v2.1.145+147**: `claude_code.tool` OTEL span에 `agent_id`/`parent_agent_id` 표준 attribute가 추가되고, 백그라운드 subagent span이 dispatching Agent tool span 아래로 정확히 nest됨.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.145, v2.1.147)

#### Nova 현재 상태
- `hooks/record-event.sh`는 이미 `CLAUDE_AGENT_ID`·`CLAUDE_PARENT_AGENT_ID` 환경변수가 노출되면 top-level로 캡처하도록 v5.42.0+에서 정비됨 (`hooks/record-event.sh` 헤더 주석 참조).
- `scripts/publish-metrics.sh`와 `docs/guides/measurement-closed-loop.md`는 부모-자식 관계를 별도 필드로 노출하지 않음 — JSONL에는 들어가지만 dashboard에서 호출 트리를 그리지 못함.

#### Nova 적용 방안
1. `scripts/publish-metrics.sh`에서 events.jsonl 집계 시 `agent_id`·`parent_agent_id` 컬럼을 산출에 포함 → 부모-자식 호출 카운트.
2. `docs/guides/measurement-closed-loop.md`에 "OTEL 표준 attribute와 동일한 필드명 채택 — 외부 OTEL 백엔드와 호환" 한 절 추가.
3. `mcp__plugin_nova_nova__orchestration_update`가 phase 업데이트 시 `agent_id`를 메타로 받도록 옵션 필드 추가 검토(별도 minor).

- 변경 파일: `scripts/publish-metrics.sh` 약 15줄, `docs/guides/measurement-closed-loop.md` 1 단락.

#### 영향 범위
- measurement-closed-loop의 부모-자식 호출 트리 가시화. orchestrator/jury 디버깅 가능성 ↑.

#### 리스크
- OTEL 표준이 향후 변경되면 follow-up 필요. Nova는 표준 명칭 그대로 채택하므로 변경 시 동시 반영.

#### 자율 등급
**Semi Auto (PR)** — 스크립트 + 가이드 + 테스트 회귀 가드.

---

### [P-4] Evaluator verdict 메인 대화 인라인 강제 노출 — minor

#### 발견
- **OpenHands 1.7.0**: "renders critic/verification results inline within conversations" — Generator 출력과 Critic(=Evaluator) 결과를 동일 대화 흐름에 인라인 노출.
- 출처: https://www.openhands.dev/blog/openhands-product-update---may-2026

#### Nova 현재 상태
- Nova evaluator는 서브에이전트 응답으로 PASS/FAIL을 반환 — 메인 텍스트 출력은 사용자가 능동 검색해야 함.
- MEMORY(`feedback_evaluator_hallucination.md`): Evaluator verdict를 그대로 전달 X, 메인이 사실 검증 1회 후 보고 — 현재 규칙이 있지만 "verdict 표준 포맷"이 없음.

#### Nova 적용 방안
1. `skills/evaluator/SKILL.md`에 Evaluator 응답 표준 포맷 추가 — `verdict: PASS|FAIL|UNCERTAIN` / `evidence: [...]` / `risks: [...]` (구조화 JSON 가능).
2. `commands/check.md`·`commands/review.md`·`commands/run.md`에 "Evaluator PASS/FAIL을 메인 turn에 인라인 표시 (예: `✅ Evaluator PASS — evidence: ...` / `❌ Evaluator FAIL — risks: ...`)" 출력 의무 추가.
3. `tests/test-scripts.sh`에 evaluator 스킬 출력에 verdict 키워드 부재 시 FAIL하는 회귀 가드.

- 변경 파일: `skills/evaluator/SKILL.md` 출력 포맷 절, 3개 commands/* 1줄씩, 테스트 1개.

#### 영향 범위
- Evaluator 결과가 사용자에게 묻히지 않음. 자가 규칙 미준수 갭(MEMORY: `rule_self_enforcement_gap`) 완화.

#### 리스크
- 기존 evaluator 호출 스크립트가 verdict 키워드를 파싱하지 않는다면 우회 가능. 회귀 가드로 차단.

#### 자율 등급
**Semi Auto (PR)** — skill + commands + test.

---

### [P-5] Evaluator rubric + max_iterations + structured feedback 채택 — minor

#### 발견
- **Anthropic Managed Agents "Outcomes"**: writer turn마다 신규 grader 인스턴스가 rubric만 보고 artifact 검수 → explanation을 writer에 append → `max_iterations` (기본 3, 최대 20)까지 반복. rubric 설계 원칙: checkable criteria / concrete evidence / goals-over-steps / shortcut 차단 / feedback 포맷 강제 / ignore list. PowerPoint 10.1%·Word 8.4% 자사 벤치 품질 개선.
- 출처: https://platform.claude.com/cookbook/managed-agents-cma-verify-with-outcome-grader , https://claude.com/blog/new-in-claude-managed-agents

#### Nova 현재 상태
- `skills/evaluator/SKILL.md`는 적대적 검증 기준은 있지만 (1) rubric 스키마 미정 (2) 반복 상한 명시 없음 (3) 구조화 피드백 포맷 부재.
- Karpathy 규율(CLAUDE.md): "성공 기준을 테스트·빌드·스크린샷·curl 등으로 검증 가능하게 정의" — Outcomes의 checkable criteria 원칙과 일치.

#### Nova 적용 방안
1. `skills/evaluator/SKILL.md`에 rubric 섹션 추가 — 항목별 (a) check 가능 기준 / (b) 증거 형태 (c) ignore list. 최소 5항목 (compile / test / lint / state-drift / spec-mismatch).
2. `commands/run.md`·`commands/check.md`·`commands/review.md`에 "Evaluator는 동일 회 안에서 최대 3회 반복(`NOVA_EVAL_MAX_ITER` 환경변수, 기본 3, 상한 5). 매 회 신규 인스턴스(컨텍스트 분리). 3회 후 FAIL 잔존이면 사용자 결정 대기" 명시.
3. `docs/nova-rules.md` §4(검증)에 rubric/iteration 원칙 한 단락 흡수.

- 변경 파일: `skills/evaluator/SKILL.md` rubric 절, 3 commands/*, `docs/nova-rules.md` §4.

#### 영향 범위
- X-Verification Pillar 직접 강화. Evaluator 적중률·재현성 ↑. 자기 검증 무한 루프 명시적 차단(`max_iterations`).

#### 리스크
- 기존 evaluator 호출이 1회 PASS/FAIL에 익숙 — 3회 반복 시 비용 증가. 기본 3회·상한 5회 + `NOVA_EVAL_MAX_ITER` 환경변수로 사용자 제어.

#### 자율 등급
**Semi Auto (PR)** — 큰 변경. skill + 3 commands + rule.

---

### [P-6] Nova-rules § ↔ test traceability YAML 신설 — minor

#### 발견
- **MCP SEP-2484**: 스펙 SEP가 Final 되려면 `sep-NNNN.yaml` traceability 파일(각 MUST/MUST NOT → check 매핑)이 conformance repo에 머지돼야 함.
- 출처: https://github.com/modelcontextprotocol/modelcontextprotocol/pull/2484

#### Nova 현재 상태
- `docs/nova-rules.md` §1~§9 MUST/MUST NOT은 47+ 개. `tests/test-scripts.sh` 1031 케이스가 일부를 커버하지만 "규칙 ↔ 테스트" 매핑이 암묵적 — "규칙은 있는데 테스트는 없는" 갭이 침묵.
- 자가 규칙 미준수 갭(MEMORY: `rule_self_enforcement_gap`)이 이 갭의 발현 사례.

#### Nova 적용 방안
1. `docs/nova-traceability.yaml` 신설 — `rule_id: <§N.M>` → `test_ids: [<test_name>...]` 매핑. 모든 MUST/MUST NOT 강제 매핑.
2. `tests/test-scripts.sh`에 traceability 가드 추가 — YAML의 모든 `rule_id`가 실제 nova-rules.md에 있고 모든 `test_ids`가 실제 테스트 함수로 존재하는지 검증.
3. `scripts/audit-self.sh` 또는 `/nova:audit-self`에 traceability coverage 출력 추가.

- 변경 파일: `docs/nova-traceability.yaml` 신설, `tests/test-scripts.sh` 가드 약 30줄, `commands/audit-self.md` 출력 항목 1개.

#### 영향 범위
- Adaptive Pillar 강화. 규칙 추가 시 테스트 매핑 의무화 — 자가 규칙 미준수 갭 구조적 차단.

#### 리스크
- 초기 매핑 작업 1회 부담. 이후 신규 규칙 추가 시 1줄 매핑만.

#### 자율 등급
**Semi Auto (PR)** — 신규 YAML + 테스트 가드. 큰 가치 / 중간 비용.

---

### [P-7] `/usage` per-category 카테고리화를 measurement-closed-loop에 흡수 — minor

#### 발견
- **CC v2.1.149**: 공식 `/usage`가 skills, subagents, plugins, MCP 서버별로 토큰 한도 사용량 breakdown.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.149), https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md

#### Nova 현재 상태
- `scripts/publish-metrics.sh`는 events.jsonl 집계만 — "어느 스킬이 토큰을 얼마나 먹는가" 카테고리 분리 없음.
- `skills/status-dashboard/SKILL.md` HTML 대시보드는 Phase·Sprint·Drift 위주 — 비용 차원 없음.

#### Nova 적용 방안
1. `hooks/record-event.sh`의 PostToolUse 캡처 시 `category`(skill / subagent / plugin / mcp / command) 자동 분류 추가.
2. `scripts/publish-metrics.sh`에서 카테고리별 토큰·duration·횟수 집계 출력 (`metrics.csv` 컬럼 확장).
3. `skills/status-dashboard`에 "비용 무거운 스킬 Top 5" 패널 추가 — Adaptive Pillar 진화 후보 자동 발탁 입력.
4. `commands/evolve.md` Phase 1에 "최근 7일 비용 Top 5 스킬을 진화 후보로 자동 포함" 한 줄.

- 변경 파일: `hooks/record-event.sh` 약 10줄, `scripts/publish-metrics.sh` 카테고리 집계, `skills/status-dashboard/SKILL.md` 패널, `commands/evolve.md` 1줄.

#### 영향 범위
- 측정 → 효과 입증 → 후험적 정체성 승격(MEMORY: `evidence_first_identity`)의 정량 입력 확보. evolution 후보 선정 자동화.

#### 리스크
- 카테고리 분류는 events.jsonl 신규 필드 — 기존 데이터는 카테고리 unknown. forgiving reader 패턴 적용.

#### 자율 등급
**Semi Auto (PR)** — 측정 인프라 + 대시보드 + evolve 입력 4 파일 연쇄.

---

### [P-8] AEGIS scope-expansion ladder를 /nova:review에 도입 — minor

#### 발견
- **arXiv 2605.12280 (2026-05-12)**: AEGIS 7150줄 프롬프트 사양에 Claude sub-agent 9회 순차 audit → 결함 15·8·12·2·8·1·4·1·0 비단조 수렴. "single-file review가 놓친 결함 클래스는 expanded-scope round에서만 표면화".
- 출처: https://arxiv.org/abs/2605.12280

#### Nova 현재 상태
- `commands/review.md`·`commands/check.md`는 단일 패스 위주. `--strict` 옵션이 있지만 "scope round"(파일 → 모듈 → 스프린트 사양 일관성) 단계적 확장은 없음.
- Evaluator 편향(MEMORY: `feedback_evaluator_hallucination.md`) 완화에 직결.

#### Nova 적용 방안
1. `commands/review.md`에 scope ladder 옵션 추가:
   - `--scope=file` (기본, 변경 파일만)
   - `--scope=module` (변경 파일이 속한 모듈 전체)
   - `--scope=sprint` (현재 Active Tree work-item의 spec과 일관성 검증)
2. `--strict` 호출 시 자동 ladder (file → module → sprint) 3회 적용. 매 회 새 evaluator 인스턴스.
3. `skills/evaluator/SKILL.md`에 scope round 메타데이터 표준 추가 (P-5 rubric과 결합).

- 변경 파일: `commands/review.md` scope 절, `commands/check.md` scope 옵션, `skills/evaluator/SKILL.md` 메타데이터.

#### 영향 범위
- 누락 결함 탐지율 ↑. /nova:review --strict의 실효 보장.

#### 리스크
- scope=sprint는 토큰 비용 큼 — `--strict` 모드에만 자동 적용. 기본은 file scope.

#### 자율 등급
**Semi Auto (PR)** — commands 2개 + skill + 테스트.

---

### [P-9] /nova:review에 PR inline comment 게시 옵션 추가 — patch

#### 발견
- **CC v2.1.147**: 공식 `/code-review`(구 /simplify) 커맨드에 `--comment` 옵션으로 GitHub PR inline comment 자동 게시.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.147)

#### Nova 현재 상태
- `commands/review.md`·`scripts/release.sh`는 evaluator FAIL을 stdout으로만 출력 — PR로 영구 기록 안 됨.
- 자가 규칙 미준수 갭(MEMORY: `rule_self_enforcement_gap`)은 release.sh 게이트 통합 후에도 "보고 사라짐" 위험 잔존.

#### Nova 적용 방안
1. `commands/review.md`에 `--comment` 옵션 추가 — Evaluator 출력의 FAIL 항목을 `gh pr review --comment` 또는 `gh pr comment`로 현재 PR에 게시.
2. `scripts/release.sh`에 PR 컨텍스트가 있을 때 자동 `--comment` 호출 (게이트 FAIL 영구 기록).
3. PR이 없는 main 브랜치 직접 커밋은 게이트 통과 후만 — 변경 없음.

- 변경 파일: `commands/review.md` 옵션 1개, `scripts/release.sh` 약 10줄.

#### 영향 범위
- Evaluator FAIL의 영구성 확보. 자가 규칙 미준수의 후행 감사 가능.

#### 리스크
- PR이 없는 컨텍스트에서 `gh pr comment` 실패 → graceful skip 필요.
- `gh` 미설치 환경 → graceful skip.

#### 자율 등급
**Semi Auto (PR)** — commands + release.sh.

---

### [P-10] Orchestrator mid-workflow check-in 시점 권고 — patch

#### 발견
- **Anthropic Managed Agents — Multiagent Orchestration (2026-05-06)**: lead agent가 작업 분해 → specialist sub-agent들이 공유 파일시스템에서 병렬 실행, lead가 mid-workflow check-in 가능, Console에서 sub-agent별 trace 감사.
- 출처: https://claude.com/blog/new-in-claude-managed-agents

#### Nova 현재 상태
- `skills/orchestrator/SKILL.md`는 lead spawn + 병렬 sub-agent까지는 명시 — 중간 점검 시점은 암묵적.
- `mcp__plugin_nova_nova__orchestration_update`는 phase status를 갱신하지만 lead가 중간에 SendMessage로 sub-agent 진행 점검을 권장하지 않음.

#### Nova 적용 방안
1. `skills/orchestrator/SKILL.md`에 "Phase 절반 경과 시 또는 단일 sub-agent가 5분 이상 idle 없을 때 lead가 진행 점검 SendMessage 1회 권장" 한 단락.
2. `mcp__plugin_nova_nova__orchestration_update`에 `interim_checkin: true` 옵션 필드 추가 검토 (별도 minor).

- 변경 파일: `skills/orchestrator/SKILL.md` 1 단락.

#### 영향 범위
- 협업 Pillar 강화. 멀티 에이전트 흐름의 hang/drift 조기 탐지.

#### 리스크
- 너무 잦은 점검은 idle 패턴 방해. "5분 이상 idle 없을 때 1회" 가이드 명시.

#### 자율 등급
**Full Auto** — skill 1 단락 추가.

---

---

### [P-11] 다중 에이전트 워크플로우의 teammate shutdown 의무 코드화 — patch (자기-발견 갭, 본 스캔 중 즉시 패치)

#### 발견
- 본 스캔(/nova:evolve --scan, team agent 모드) 실행 중 사용자가 tmux 4 pane에 spawn된 스캐너 4명(`scan-anthropic` / `scan-ecosystem` / `scan-harness` / `scan-aieng`)이 보고 후 idle 상태에서 종료되지 않는 현상 보고 ("닫히지 않는 버그").
- 원인 분석: Claude Code Agent는 `idle_notification`을 보낼 뿐 process를 종료하지 않는다 — lead가 `SendMessage({type:"shutdown_request"})`를 명시적으로 발송해야 teammate가 approve 후 종료. MEMORY `feedback_shutdown_idle_agents.md`(2026-04-23 학습)에 같은 룰이 기록되어 있으나 **`skills/orchestrator/SKILL.md` · `skills/evolution/SKILL.md` · `commands/evolve.md` · `docs/nova-rules.md` 어디에도 shutdown 의무가 코드화되지 않았다** (grep 결과 `shutdown`·`TeamDelete` 키워드 0건).
- 출처: 본 세션 사용자 보고(2026-05-23), MEMORY `feedback_shutdown_idle_agents.md`.

#### Nova 적용 (본 스캔 중 즉시 패치 완료)
1. ✅ `skills/orchestrator/SKILL.md` Phase 7(결과 보고) 절에 "팀원 종료 의무 (idle ≠ shutdown)" CRITICAL 단락 추가 — Phase 7 결과 보고 직후 lead가 각 teammate에게 `SendMessage shutdown_request` 발송, 모든 응답 후 필요 시 `TeamDelete`.
2. ✅ `commands/evolve.md` Phase 1(Scanner) 끝에 "팀 에이전트 모드의 종료 의무" 절 추가 — 모든 스캐너 보고 수신 직후 lead의 shutdown 발송 의무 명시.
3. ✅ 본 세션의 4 스캐너에 shutdown_request 발송 완료(2026-05-23 23:52 UTC).
4. ✅ `tests/test-scripts.sh` 1031/1031 통과 확인.

#### 후속 권고 (별도 PR)
- `docs/nova-rules.md` §협업(또는 §2 검증 인접)에 "다중 에이전트 작업 완료 시 lead는 teammate에게 shutdown_request 발송 의무" 한 줄. 자동 적용 규칙 변경이므로 `hooks/session-start.sh` 동기화 + 동기화 테스트 케이스 추가 필요 → 별도 patch PR.
- `tests/test-scripts.sh`에 회귀 가드 추가: 다중 에이전트 패턴을 사용하는 commands(`commands/auto.md`, `commands/evolve.md`, `commands/check.md` 등) 마크다운에 `shutdown_request` 또는 `TeamDelete` 키워드 부재 시 FAIL.

#### 영향 범위
- 협업 Pillar 직접 강화. 자동 적용 규칙은 후속 PR에서 갱신.

#### 리스크
- 기존 사용자 영향 0 (문서 only, 동작 변경 X).
- shutdown_request 발송 후 teammate 미응답 시 lead가 stuck 가능성 — Claude Code 자동 timeout이 처리한다고 가정. 후속 측정 필요.

#### 자율 등급
**Full Auto** — 두 문서에 단락 추가. 본 스캔 중 적용 완료.

---

## 요약 — 자율 등급별

| 등급 | 항목 | 개수 |
|------|------|------|
| Full Auto (patch, 본 스캔에서 적용 완료) | **P-11 teammate shutdown 의무 코드화 (자기-발견)** | 1 |
| Full Auto (patch, 즉시 적용 가능) | P-2 multi-Agent frontmatter 회귀 가드, P-10 orchestrator check-in | 2 |
| Semi Auto (PR 필요) | P-1 background_tasks, P-3 OTEL agent_id, P-4 Evaluator verdict 인라인, P-5 Evaluator rubric, P-6 traceability YAML, P-7 /usage 카테고리, P-8 scope ladder, P-9 PR inline comment | 8 |
| Manual (제안만, 디자인 결정 선행) | 없음 (이번 스캔에선 major 없음) | 0 |

## 다음 단계 권고

1. **즉시 (Full Auto, /nova:evolve --apply 가능)**: P-2(multi-Agent frontmatter 회귀 가드), P-10(orchestrator check-in 한 단락).
2. **단기 (Semi Auto, deepplan 1개로 묶음)**: P-1 + P-4 + P-5 = "Evaluator/Checkpoint 정직성·구조화" 묶음 PR.
3. **중기 (Semi Auto, measurement-closed-loop 확장)**: P-3 + P-7 = "OTEL agent_id + per-category 카테고리화" 묶음 PR.
4. **중기 (Semi Auto, review 강화)**: P-8 + P-9 = "scope ladder + PR inline comment" 묶음 PR.
5. **중기 (Semi Auto, 단독)**: P-6 traceability YAML — 신규 파일 + 테스트 가드, 단독 PR 적합.
6. **추적 (당장 변경 X)**: MCP 2026-07-28 RC 22-SEP 묶음 — Final 진입 시 재스캔. Dreaming · TaskToolSet · Cursor multi-repo · Eugene Yan pair-programmer는 measurement-closed-loop 데이터 누적 후 재검토.

본 스캔의 흡수 우선순위는 **P-2 → P-1 → P-5 → P-4** 순. Evaluator/checkpoint Pillar(X-Verification·Consistent) 강화가 직전 v5.47.x dogfood 사고 경향과 가장 결이 맞는다.
