# Evolution Proposal: Nova MCP `alwaysLoad: true`

> 날짜: 2026-05-07
> 수준: minor
> 출처: Claude Code v2.1.121 (2026-04-28) — https://code.claude.com/docs/en/changelog
> 자율 등급: Semi Auto (PR)

## Context

Claude Code v2.1.121에서 MCP 서버 설정에 `alwaysLoad: true` 옵션이 추가됐다. 이 옵션이 켜지면 해당 서버의 모든 도구가 ToolSearch deferral을 건너뛰고 세션 시작과 동시에 즉시 사용 가능 상태가 된다.

Nova는 자체 MCP 서버(`@nova/mcp-server`)를 ship하며 다음 도구를 노출한다:
- `mcp__plugin_nova_nova__get_commands`
- `mcp__plugin_nova_nova__get_rules`
- `mcp__plugin_nova_nova__get_state`
- `mcp__plugin_nova_nova__orchestrate`
- `mcp__plugin_nova_nova__orchestration_start` / `_status` / `_update`
- `mcp__plugin_nova_nova__repo_preflight`
- `mcp__plugin_nova_nova__x_verify`

## Problem

현재(v5.29.1) Nova MCP 도구는 모두 **deferred** 상태로 등록된다. 메인 컨텍스트에서 호출하려면:

1. 도구 이름은 system reminder의 deferred 목록에 표시되지만 schema는 없음
2. `ToolSearch query="select:..."` 호출로 schema 로드 필수
3. 그 다음 도구 호출 가능

이는 모든 Nova MCP 도구 호출마다 1회 추가 round-trip을 강제한다. `/nova:next`, `/nova:run`, `/nova:auto` 같은 진입점은 첫 호출에서 `get_state`/`get_commands`를 거의 항상 사용하므로 **체감 지연 + 캐시 미스 가능성**이 매번 발생한다.

deferred는 "자주 안 쓰는 도구를 컨텍스트 밖으로 밀어내는" 메커니즘인데, Nova MCP 도구는 **Nova 워크플로우 핵심 진입점**이므로 deferral 자체가 부적절하다.

## Solution

Nova MCP 서버 등록 시 `alwaysLoad: true`를 명시한다. CC가 세션 시작에서 즉시 모든 Nova MCP 도구의 schema를 로드하므로 ToolSearch round-trip이 사라진다.

### 변경 위치

**1차 후보**: `.claude-plugin/plugin.json` 의 MCP server 선언부 (별도 파일이면 해당 파일)

```json
{
  "mcpServers": {
    "nova": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/mcp-server/dist/index.js"],
      "alwaysLoad": true
    }
  }
}
```

### 검증

1. `bash hooks/session-start.sh | python3 -m json.tool` — JSON 유효성
2. CC 세션 재시작 → 시스템 리마인더에 `mcp__plugin_nova_nova__*` 도구가 **첫 화면 함수 정의**(deferred 아님)로 노출되는지 확인
3. `/nova:next` 1회 실행 → 첫 메시지에서 `get_state` 호출이 ToolSearch 없이 성공하는지 실측
4. 회귀 테스트: tests/test-scripts.sh 통과

### 회귀 가드 추가

`tests/test-scripts.sh`에:
```bash
test_mcp_alwaysload() {
  grep -q '"alwaysLoad"[[:space:]]*:[[:space:]]*true' .claude-plugin/plugin.json
}
```

## Impact

| 영역 | 영향 |
|------|------|
| 사용자 UX | Nova MCP 첫 호출 지연 제거 — 매 세션 1회 round-trip 절약 |
| 컨텍스트 비용 | 도구 schema가 항상 로드 — 약 ~10 도구 schema 토큰 상시 점유 (예상 < 2KB) |
| 호환성 | CC v2.1.121 미만에서 알 수 없는 키로 무시될 가능성. **검증 필요** |
| 회귀 테스트 | 1건 추가 (alwaysLoad 키 존재 확인) |

## Risk

- **낮음**: 옵션 키 추가만으로 끝나는 변경. CC 구버전이 키를 무시하면 기존 deferred 동작으로 자연 폴백.
- **검증 포인트**: CC v2.1.121 미만 사용자에서 `/mcp validate` 또는 `claude plugin validate`가 unknown-key 경고를 띄우는지 확인. 경고만 나오고 동작 영향 없으면 채택.

## Open Question (Apply 시 해소)

- `alwaysLoad: true`가 도구 8개 전부에 적용되는지, 도구별 선택 가능인지. 공식 문서가 "all tools from that server"라 명시 → 서버 단위. Nova는 서버 1개라 문제 없음.

## 채택 시 적용 후속

- README.md / README.ko.md "Quick Start" 섹션에 "MCP 도구 즉시 사용 가능" 한 줄 추가
- nova-rules.md §0 또는 §1에 MCP 즉시 활성화 보장 명시 (선택)
