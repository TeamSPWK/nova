# Anthropic Baseline (evolve fallback)

`/nova-dev:evolve` Scanner Phase가 외부 호출(WebSearch + `gh api`)에 모두 실패하거나 rate-limit으로 결과를 못 받았을 때 참조하는 **정적 큐레이션 baseline**이다.

## 운영 규칙

1. **수동 갱신** — Anthropic이 새 기능을 발표할 때마다 본 파일을 PR로 갱신한다. 자동 갱신 없음.
2. **Nova 적용 여부 컬럼 필수** — `nova_applied: true/false/n/a`. `false` 항목만 fallback 시 제안 후보로 승격.
3. **Fallback 트리거** — Scanner Phase 1에서 (WebSearch 0건 AND `gh api` 실패) 시 본 baseline에서 `nova_applied=false` 항목을 제안으로 변환.
4. **자가 환각 방지** — 모든 항목에 `doc_url` 필수. URL 검증 안 된 항목은 추가 금지.

## 핵심 기능 인덱스 (v5.48.0 기준)

| feature | doc_url | category | nova_applied | nova_artifact / 미적용 사유 |
|---|---|---|---|---|
| Hooks 시스템 (PreToolUse/PostToolUse/Stop/SessionStart) | https://docs.anthropic.com/en/docs/claude-code/hooks | new-feature | true | `hooks/*.sh` 11개 — session-start, audit-teammates, record-event 등 |
| Sub-agents & Task 도구 (병렬 위임) | https://docs.anthropic.com/en/docs/claude-code/sub-agents | new-feature | true | `agents/*.md` + evaluator/jury/orchestrator 스킬 |
| MCP 서버 통합 | https://docs.anthropic.com/en/docs/claude-code/mcp | new-feature | true | `mcp-server/` 직접 구현 |
| Extended Thinking | https://docs.anthropic.com/en/docs/claude-code/settings | improvement | n/a | Claude Code 런타임 토글 — 흡수 대상 아님 |
| Plan Mode | https://docs.anthropic.com/en/docs/claude-code/plan-mode | new-feature | true | `/nova:plan`, `/nova:deepplan` — 직접 매핑은 아니나 동일 의도 충족 |
| Git Worktree 격리 | https://docs.anthropic.com/en/docs/claude-code/worktrees | new-feature | true | `skills/worktree-setup`, `hooks/worktree-setup.sh` |
| CLAUDE.md 계층형 메모리 | https://docs.anthropic.com/en/docs/claude-code/memory | tip | true | `skills/claude-md` + `docs/nova-rules.md §15` |
| /compact 컨텍스트 최적화 | https://docs.anthropic.com/en/docs/claude-code/context-management | tip | true | `skills/strategic-compact` (시점 판단 강화) |
| IDE 통합 (VS Code/JetBrains) | https://docs.anthropic.com/en/docs/claude-code/ide-integrations | improvement | n/a | Claude Code 자체 기능 — 흡수 대상 아님 |
| 병렬 도구 호출 | https://docs.anthropic.com/en/docs/claude-code/best-practices | tip | true | `commands/*.md` 전역 권장, `skills/orchestrator` Phase 병렬 spawn |
| Skills (description-triggered) | https://docs.anthropic.com/en/docs/claude-code/skills | new-feature | true | `skills/*/SKILL.md` 13개 + `dev/skills/*` 2개 |

## 미적용(nova_applied=false) 항목

현재 본 baseline 내 `nova_applied=false` 항목은 **0건**이다. 신규 Anthropic 기능 추가 시 본 표에 행을 추가하고 `false`로 시작, 흡수 완료 후 `true` + `nova_artifact` 갱신한다.

## Scanner Fallback 절차

```
Scanner Phase 1
  ├─ WebSearch (Anthropic + 외부 2 소스)
  ├─ gh api search/repositories?q=... (8개 쿼리 병렬)
  └─ 둘 다 결과 0건 또는 실패
        ↓
     Fallback: evolve-baseline.md 로드
        ↓
     nova_applied=false 항목만 추출
        ↓
     Phase 2 (Relevance Filter) 입력으로 전달
        ↓
     보고서 헤더에 `⚠ Baseline fallback — Live scan failed` 명시
```

## 갱신 책임

- Anthropic 신기능 발표 시: `feat(evolve-baseline): {기능명} 추가` PR로 행 추가.
- Nova가 흡수 완료 시: `update(evolve-baseline): {기능명} nova_applied=true` PR로 컬럼 갱신.
- Baseline은 **정체성 선언이 아닌 인덱스**다 — `feedback_evidence_first_identity.md`와 충돌하지 않는다.
