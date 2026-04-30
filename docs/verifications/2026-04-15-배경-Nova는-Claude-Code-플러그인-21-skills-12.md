# X-Verification: 배경: Nova는 Claude Code 플러그인(21 skills, 12 commands, 5 agents, SessionStart hook, 

> 날짜: 2026-04-15
> 합의율: N/A
> 판정: agent_review
> AI: gpt

## 질문
배경: Nova는 Claude Code 플러그인(21 skills, 12 commands, 5 agents, SessionStart hook, stdio MCP 서버)이다. GitHub 이슈에서 "Codex에서도 Nova를 직접 사용 가능하게 해달라"는 요청이 있었다.

조사한 사실:
- Codex 플러그인 포맷은 `.codex-plugin/plugin.json` + skills/ + .mcp.json + .app.json 만 수용한다.
- Codex에는 slash command, agent type, SessionStart hook 개념이 없다.
- MCP는 `~/.codex/config.toml`의 `[mcp_servers.<name>]` 또는 플러그인 내 `.mcp.json`으로 등록된다.
- `${CLAUDE_PLUGIN_ROOT}` 같은 환경변수 확장이 Codex에서 지원되는지 공식 문서에 명시 없음.

질문: 다음 세 옵션 중 어느 것이 장기적으로 가장 타당한가?

A) 풀 Codex 지원 — commands/agents/hooks를 전부 skills로 재구성. Claude 플러그인 구조를 함께 개편.
B) 공존형 최소 지원 — Codex용에는 skills + MCP만 노출. commands/agents/hooks는 Claude 전용으로 유지.
C) 문서화만 — `~/.codex/config.toml`에 MCP 수동 추가 가이드만 README에 추가.

각 옵션의 트레이드오프(유지보수 부담, 사용자 혼란, Nova 정체성, 생태계 파편화)와 추천안을 근거와 함께 제시해달라. 한국어로, 800자 이내.

## gpt
**추천: B) 공존형 최소 지원**

가장 현실적이고 장기적으로도 균형이 좋습니다.

- **A 풀 지원**
  - 장점: Codex 사용자 경험 일관, “공식 지원” 메시지 강함
  - 단점: commands/agents/hooks를 skills로 억지 변환해야 해 **구조 왜곡**이 큼. Claude 중심 설계를 Codex 제약에 맞춰 재편하면 **유지보수 비용**과 **정체성 훼손**이 큼. 두 플랫폼 공통분모에 맞추다 기능 하향평준화 위험도 있음.

- **B 공존형 최소 지원**
  - 장점: Codex가 수용 가능한 **skills + MCP만 안정적으로 제공**해 진입장벽을 낮춤. Claude 고유 기능(commands/agents/hooks)은 유지해 **Nova의 본체 가치**를 보존. 플랫폼별 차이를 명확히 문서화하면 혼란도 관리 가능.
  - 단점: 기능 격차로 일부 사용자 혼란 가능. 다만 이는 “Codex Edition은 subset”으로 명시하면 해결 가능.

- **C 문서화만**
  - 장점: 구현 부담 최소
  - 단점: 사용성이 너무 낮아 사실상 “지원 안 함”에 가까움. 설치 실패·경로 이슈·환경변수 불확실성까지 사용자가 떠안아 **혼란과 이탈**이 큼.

**결론:** 지금은 **B**가 최선입니다. Codex는 **subset 지원**으로 명확히 포지셔닝하고, 향후 Codex가 commands/hooks/agents 유사 개념을 지원할 때만 A를 재검토하세요. C는 임시 대응으로는 가능하지만 장기 전략으로는 약합니다.

