# Nova Context Chain vs External Tools

> Nova v5.49.0 / 2026-05-27
> 비교 대상: thedotmack/claude-mem · parcadei/Continuous-Claude-v3
> 목적: Nova `context-chain` + NOVA-STATE.md + `.nova/events.jsonl` 패턴이 외부 대안과 어떻게 다른지 명시한다. 우월성 주장이 아닌 **선택 기준 제공**.

## TL;DR

| 기준 | Nova | claude-mem | Continuous-Claude-v3 |
|---|---|---|---|
| 외부 의존성 | **0** (jq + python3 + bash) | ChromaDB / SQLite / mem0 / supermemory 중 택 1 | hooks + ledger 파일 (낮음) |
| 시계열 모델 | append-only JSONL + 본문 스냅샷 | vector embedding + 압축 | ledger + handoff 파일 |
| 데이터 위치 | `.nova/events.jsonl` (텍스트, git 친화) | 별도 DB 파일 (binary 가능) | ledger 파일 |
| lock-in 위험 | 낮음 (텍스트 → 어디서나 grep) | 중간 (vendor DB schema 변경 영향) | 낮음 (텍스트 ledger) |
| AI API 키 필요 | **❌ 불필요** | embedding API 키 필요 (사용 모델별) | ❌ 불필요 |
| 호환 도구 | Claude Code (현재) — 표준 Anthropic hooks/skills/agents 기반 | Claude Code / OpenClaw / Codex / Gemini / Hermes / Copilot / OpenCode | Claude Code (hooks + MCP 종속) |
| 학습 곡선 | 1 파일 + 1 디렉토리 (NOVA-STATE.md + .nova/) | DB 설치 + embedding 구성 | hooks + ledger 설계 학습 |

## 1. Nova Context Chain — JSONL Append-Only

### 구조
- **본문 스냅샷 손편집**: `NOVA-STATE.md`의 Current/Phase/Refs/Risks 본문만 사용자가 손편집 (v5.44.0+).
- **시계열 자동 캡처**: `.nova/events.jsonl`에 `hooks/record-event.sh`가 PostToolUse/Stop/SessionStart 이벤트를 append.
- **v3 marker 영역 자동 렌더**: Stop hook이 `scripts/registry-render-state.sh`로 work-item registry를 NOVA-STATE.md의 marker 영역에 자동 갱신.
- **분석**: `scripts/analyze-observations.sh`가 패턴/신뢰도를 집계 → `/nova:evolve --from-observations`로 진화 후보 제안.

### 강점
- **텍스트만**: `grep`/`jq`로 어디서나 분석. git 충돌 시 텍스트 머지.
- **외부 의존성 0**: API 키 없음, DB 설치 없음 (MEMORY `feedback_api_key_optional_principle.md`).
- **AI는 제안, 인간은 결정**: 자동 승격 금지 — `--from-observations` 결과는 사용자 명시 `--accept`/`--reject` 후에만 신뢰도 반영.

### 약점
- 본문 스냅샷 손편집은 드리프트 위험 — Stop hook auto-render + `/nova:checkpoint`로 보완.
- vector 기반 의미 검색 X — 정확 일치/패턴 기반.
- 데이터 누적 시 events.jsonl 파일 크기 증가 — 분기별 archive 권장.

## 2. claude-mem (thedotmack)

> 출처: https://github.com/thedotmack/claude-mem (79k stars)

### 구조
- **Vector embedding 기반 압축 + 주입**: 세션 중 모든 활동을 캡처 → AI 압축 → 다음 세션에 관련 컨텍스트 자동 주입.
- **DB 선택**: ChromaDB / SQLite / mem0 / supermemory 중 사용자 환경에 맞게.

### 강점
- 의미 기반 검색 (vector similarity) — "auth 관련 결정 모두" 같은 fuzzy query 가능.
- 다중 코딩 도구 호환 — Claude Code / OpenClaw / Codex / Gemini / Hermes / Copilot / OpenCode.
- 압축 자동 — 사용자가 NOVA-STATE처럼 손편집 불필요.

### Nova 관점 약점
- **외부 의존성**: embedding 모델 API 키 필요 (사용 DB별).
- **lock-in**: vendor DB schema 변경 시 마이그레이션 비용.
- **자동 압축 → 정보 손실 위험**: 사용자가 무엇이 압축됐는지 직관적으로 확인하기 어려움. Nova의 NOVA-STATE.md는 시각적 손편집 가능.
- **binary DB**: git 친화도 낮음 — 다중 머신 동기화는 별도 sync 메커니즘 필요.

### 선택 기준
- **claude-mem 적합**: 다중 코딩 도구 사용, 의미 검색 필수, embedding 비용 감내 가능.
- **Nova context-chain 적합**: Claude Code 단독 사용, git-친화 텍스트 우선, 외부 의존성 0 원칙.

## 3. Continuous-Claude-v3 (parcadei)

> 출처: https://github.com/parcadei/Continuous-Claude-v3 (3.8k stars)

### 구조
- **Hooks-driven ledger**: hook이 ledger 파일에 활동을 append, 다음 세션에 handoff 파일로 전달.
- **MCP execution without context pollution**: MCP 호출 결과를 메인 컨텍스트에 직접 넣지 않고 별도 ledger로 분리.
- **Isolated context windows per agent**: 에이전트별 컨텍스트 격리.

### 강점
- Nova와 가장 유사한 영역 — hooks + ledger + MCP 결합.
- 에이전트 오케스트레이션의 컨텍스트 격리 패턴 명시.
- 외부 DB 의존성 없음.

### Nova 관점 약점
- **Nova와 영역 중첩**: Nova가 이미 `.nova/events.jsonl` + `skills/orchestrator` + `mcp-server/`로 동일 영역 해결. 동시 사용 시 ledger 중복.
- **품질 게이트 통합 부재**: Continuous-Claude는 context management만. Nova는 검증 게이트(Evaluator, /nova:review --fast, exit 2 차단)와 통합.
- **자동 적용 규칙 없음**: SessionStart hook으로 매 세션 규칙 주입하는 Nova 패턴 미보유.

### 선택 기준
- **Continuous-Claude-v3 적합**: context management만 필요, 품질 게이트는 별도 도구로 해결.
- **Nova 적합**: context + 품질 게이트 + 진화(evolve) 통합. "AI Agent Ops" 5기둥 한 번에.

## 4. 동시 사용은 권장되지 않음

세 도구 모두 같은 영역(세션 간 맥락 보존)을 다룬다. 동시 사용 시:
- 데이터 중복: 같은 활동이 events.jsonl과 vector DB와 ledger에 3번 기록.
- 메인 컨텍스트 압박: 3개 도구가 SessionStart에 각자 컨텍스트 주입 → 토큰 비용 증가.
- 충돌 가능성: hooks 우선순위가 불명확.

권장: **하나만 선택**. Nova는 외부 의존성 0 + 품질 게이트 통합이 강점이지만, vector 검색이 필수면 claude-mem이 적합.

## 5. Migration

### Nova → claude-mem
- `.nova/events.jsonl` → claude-mem 입력 형식으로 변환 가능 (텍스트 → embedding).
- NOVA-STATE.md 본문은 별도 보관 — claude-mem은 자유 텍스트 컨텍스트로 처리.

### claude-mem → Nova
- vector DB는 직접 마이그레이션 어려움 — 원본 활동 로그가 있으면 events.jsonl로 재구성.
- 압축된 요약은 NOVA-STATE.md Current 절에 수동 이관.

### Continuous-Claude-v3 → Nova
- ledger 파일 → `.nova/events.jsonl` 변환 (스키마 매핑 필요).
- handoff 파일 → NOVA-STATE.md Current 절.

## 6. 결론

Nova의 선택은 **"외부 의존성 0 + 품질 게이트 통합 + 텍스트 우선"** 트레이드오프다. 이 트레이드오프가 사용자 환경에 맞지 않으면 위 대안을 고려한다.

비교 갱신 주기: **분기 1회** (3, 6, 9, 12월). `commands/evolve.md` Phase 1 스캔 결과에 따라 동기 갱신.

## 참조

- [Nova context-chain SKILL](../skills/context-chain/SKILL.md)
- [Nova events.jsonl 스펙](../specs/measurement-spec.md)
- [Nova measurement-closed-loop 가이드](../guides/publish-metrics.md)
- [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem)
- [parcadei/Continuous-Claude-v3](https://github.com/parcadei/Continuous-Claude-v3)
