# Evolution Proposal: MCP Tasks로 Orchestrator 장시간 작업 관리

> 날짜: 2026-04-14
> 수준: major
> 출처: https://blog.modelcontextprotocol.io/posts/2026-mcp-roadmap/
> 자율 등급: Manual

## 발견
MCP v2.1 사양에 Tasks (SEP-1686)가 추가됨. 장시간 실행 작업에 대해:
- 작업 상태 폴링 (pending/running/completed/failed)
- 재시도 의미론
- 결과 만료 정책

## Nova 적용 방안
Nova Orchestrator의 멀티 에이전트 구현→검증 사이클을 MCP Tasks로 관리:
- 현재: 에이전트를 순차/병렬로 실행하고 결과를 직접 수집
- 개선: 각 Phase(설계→구현→검증)를 MCP Task로 등록하여 상태 추적

```
orchestrate "기능 구현"
  → Task 1: Architect (설계) — status: completed
  → Task 2: Developer (구현) — status: running
  → Task 3: QA (검증) — status: pending
```

## 영향 범위
- `mcp-server/src/tools/orchestrate.ts` — Task 생성/상태 관리 로직
- `mcp-server/src/index.ts` — MCP Tasks 프로토콜 지원
- `mcp-server/package.json` — MCP SDK 버전 업그레이드 필요
- `.claude/skills/orchestrator/SKILL.md` — Task 기반 워크플로우 설명

## 리스크
- MCP SDK가 Tasks를 아직 완전 지원하지 않을 수 있음 (사양은 확정, SDK 구현 확인 필요)
- 기존 에이전트 기반 오케스트레이션과 호환성 유지 필요
- 복잡도 증가 — 현재 방식이 충분히 작동하므로 ROI 검토 필요
