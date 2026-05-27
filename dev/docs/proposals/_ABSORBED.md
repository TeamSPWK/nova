# Absorbed Patterns Ledger

`/nova:evolve`(또는 `/nova-dev:evolve`)가 외부 스캔에서 발견한 패턴 중 **Nova가 이미 흡수한 것**을 기록한다. Phase 2 Relevance Filter는 이 ledger를 매칭해 중복 제안을 차단한다.

## 운영 규칙

1. **append-only** — 항목 삭제 금지. 흡수 철회 시 `status: deprecated`로 표기 후 사유 컬럼에 기록.
2. **append 트리거** — evolve Phase 4가 minor/major 변경을 머지/PR 생성 시 자동 append. patch는 ledger 영향 없음(문서 보정 수준).
3. **매칭 키** — `pattern_slug` (kebab-case, 외부 도구 일반명) 또는 `source_url` 호스트 + 키워드.
4. **수동 추가 허용** — 이미 보유한 패턴을 retroactive로 등록 가능. `absorbed_in_version`이 모호하면 `pre-v5.x`로 표기.

## 시드 (retroactive, v5.48.0 기준)

| pattern_slug | source_url | absorbed_in_version | nova_artifact | status |
|---|---|---|---|---|
| anthropic-hooks | https://docs.anthropic.com/en/docs/claude-code/hooks | pre-v5.x | `hooks/session-start.sh`, `hooks/audit-teammates.sh`, `hooks/record-event.sh`, `hooks/pre-tool-use-record.sh`, `hooks/post-tool-use-record.sh`, `hooks/pre-edit-check.sh`, `hooks/pre-commit-reminder.sh`, `hooks/stop-event.sh`, `hooks/pre-compact.sh`, `hooks/worktree-setup.sh` | active |
| anthropic-sub-agents | https://docs.anthropic.com/en/docs/claude-code/sub-agents | pre-v5.x | `agents/*.md` (evaluator/qa-engineer/security-engineer/architect/refiner/senior-dev/devops-engineer), `skills/evaluator/SKILL.md` 독립 서브에이전트 패턴 | active |
| anthropic-mcp | https://docs.anthropic.com/en/docs/claude-code/mcp | pre-v5.x | `mcp-server/` (Nova MCP 서버 직접 구현) | active |
| anthropic-plan-mode | https://docs.anthropic.com/en/docs/claude-code/plan-mode | pre-v5.x | `/nova:plan`, `/nova:deepplan` (Plan Mode와 직접 매핑은 아니나 동일 의도) | active |
| anthropic-worktree | https://docs.anthropic.com/en/docs/claude-code/worktrees | pre-v5.x | `skills/worktree-setup/SKILL.md`, `hooks/worktree-setup.sh` | active |
| anthropic-claude-md-hierarchy | https://docs.anthropic.com/en/docs/claude-code/memory | pre-v5.x | `skills/claude-md/SKILL.md`, `docs/nova-rules.md §15` (Memory 라우팅) | active |
| anthropic-compact | https://docs.anthropic.com/en/docs/claude-code/context-management | pre-v5.x | `skills/strategic-compact/SKILL.md` (시점 판단 강화) | active |
| anthropic-parallel-tools | https://docs.anthropic.com/en/docs/claude-code/best-practices | pre-v5.x | 전역 적용 — `commands/*.md`에서 병렬 호출 권장, `skills/orchestrator/SKILL.md` Phase 병렬 spawn | active |
| anthropic-extended-thinking | https://docs.anthropic.com/en/docs/claude-code/settings | n/a | Claude Code 런타임 기능 — Nova 흡수 대상 아님 (런타임 토글) | n/a |
| anthropic-ide-integrations | https://docs.anthropic.com/en/docs/claude-code/ide-integrations | n/a | Claude Code 자체 기능 — Nova 흡수 대상 아님 | n/a |
| github-actions-release-dispatch | (Nova 자체) | v5.x | `.github/workflows/*` + `scripts/release.sh` landing dispatch 통합 | active |
| observability-jsonl-append-only | (Nova 자체, 외부 영감) | v5.20.0+ | `.nova/events.jsonl` + `hooks/record-event.sh` + `scripts/analyze-observations.sh` | active |
| measurement-closed-loop | (Nova 자체) | v5.24.0 | `scripts/publish-metrics.sh` + `docs/guides/publish-metrics.md` | active |
| visual-intent-verify-g1-g3 | (Nova 자체) | v5.26.0 | UI 변경 시 시각 의도 캡처(G1) + 자가 검증(G3) 페어 게이트 | active |
| audit-teammates-shutdown | (Nova 자체) | v5.47.9 | `hooks/audit-teammates.sh` — leader shutdown_request 누락 좀비 감지 | active |

## 매칭 알고리즘 (evolve Phase 2)

Scanner가 발견한 항목 `X`에 대해:

1. `X.source_url`의 호스트+path를 ledger의 `source_url`과 비교 (substring 매칭, status≠deprecated 한정)
2. 매칭되면 → "이미 흡수 (ledger row: {pattern_slug})" 표기 후 제안에서 제외
3. 매칭 안 되면 → `X.title/description`에서 키워드 추출해 ledger의 `pattern_slug`와 fuzzy 매칭 (단어 단위)
4. 키워드 매칭 시 → "잠재 중복 (ledger candidate: {pattern_slug})" 표기 후 사용자 확인 대기 (자동 폐기 X)

## 갱신 가이드

- 신규 흡수: evolve Phase 4가 minor/major 머지 직후 자동 append. AI는 별도 행동 불필요.
- 수동 보정: `status: deprecated` 또는 `nova_artifact` 컬럼 갱신은 PR로 처리. 시계열 추적 필요 시 `.nova/events.jsonl`의 `ledger_update` 이벤트 활용.
- 시드 신뢰성: 본 시드는 retroactive 자가 선언이며, 측정 의무 없음(slug 매칭표 용도). 정체성 주장이 아닌 중복 방지용 인덱스로만 운용한다.
