# Evolution Proposal: PostToolUse 훅 + `duration_ms` 도구별 캡처

> 날짜: 2026-05-07
> 수준: minor
> 출처: Claude Code v2.1.119 (2026-04-23) — https://code.claude.com/docs/en/changelog
> 자율 등급: Semi Auto (PR)

## Context

Claude Code v2.1.119에서 `PostToolUse` 및 `PostToolUseFailure` 훅 stdin 페이로드에 `duration_ms` 필드(권한 프롬프트/PreToolUse 훅 시간 제외, 순수 도구 실행 시간)가 추가됐다.

Nova는 measurement-closed-loop(v5.24.0 ~ v5.25.0)를 통해 KPI/이벤트 텔레메트리 인프라를 갖췄으며 `docs/measurement-spec.md`에 `duration_ms` 필드 자체는 정의되어 있다. 그러나:

- 현재 수집 경로는 **`Stop` 훅** 1개 — 턴 전체 단위 duration_ms만 기록 (`hooks/stop-event.sh`)
- **도구별 실행 시간은 미수집** — `record-event.sh`의 `duration_ms` 인자는 호출자가 직접 계산해 넘겨야 함

## Problem

도구별 실행 시간이 없으면 다음 측정이 불가능하다:
- "어떤 도구가 가장 시간을 소비하는가" (Bash vs Edit vs Agent vs WebSearch)
- "검증 단계(/nova:review, evaluator agent)에서 Agent 도구 평균 응답 시간"
- "Nova 워크플로우의 도구 비용 핫스팟" — 측정 인프라(Phase 0 spec)가 약속한 KPI 후보 중 일부 보류 상태

PostToolUse 훅 + `duration_ms`로 이 갭을 채울 수 있다.

## Solution

### 1. 새 훅 `hooks/post-tool-use-record.sh` 추가

```bash
#!/usr/bin/env bash
# stdin: { tool_name, tool_input, tool_response, duration_ms, ... }
read -r PAYLOAD 2>/dev/null || PAYLOAD="{}"
TOOL=$(jq -r '.tool_name // ""' <<<"$PAYLOAD")
DUR=$(jq -r '.duration_ms // 0' <<<"$PAYLOAD")
SUCCESS=$(jq -r '.tool_response.error // empty' <<<"$PAYLOAD" | { read -r e; [ -z "$e" ] && echo true || echo false; })

EXTRA=$(jq -cn --arg t "$TOOL" --argjson d "${DUR:-0}" --argjson ok "$SUCCESS" \
  '{tool_name:$t, duration_ms:$d, ok:$ok}')

bash "${CLAUDE_PLUGIN_ROOT}/hooks/record-event.sh" tool_use_post "$EXTRA"
exit 0
```

### 2. `hooks/hooks.json`에 PostToolUse 등록

```json
"PostToolUse": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use-record.sh\""
      }
    ]
  }
]
```

### 3. `docs/measurement-spec.md`에 신규 이벤트 명시

```
event: tool_use_post
fields:
  - tool_name (string, 필수)
  - duration_ms (number, 필수)
  - ok (boolean, 필수)
경로: PostToolUse 훅 → record-event.sh
용도: 도구별 비용/실패율 KPI 산출
```

### 4. `nova-metrics --json` 결과에 도구 통계 KPI 추가 (선택, 후속 sprint)

```json
{
  "kpi.tool_duration_ms_p50_by_tool": { "Bash": 120, "Edit": 30, "Agent": 8400 },
  "kpi.tool_failure_rate_by_tool": { "Bash": 0.02, "Edit": 0.0 }
}
```

(이 부분은 본 제안 채택 후 별도 sprint에서 진행)

### 5. 회귀 가드

`tests/test-scripts.sh`에 다음 테스트 추가:
- `post-tool-use-record.sh` 파일 존재 + 실행 권한
- `hooks.json`에 `PostToolUse` 키 존재 + 매처 ""
- record-event.sh가 `tool_use_post` 이벤트를 거부하지 않음 (whitelist 통과)

## Impact

| 영역 | 영향 |
|------|------|
| 텔레메트리 | `.nova/events.jsonl`에 도구별 1라인 append (every tool call). 볼륨 증가 — 대략 세션당 +30~100 라인 |
| 디스크 | events.jsonl rotation 정책 점검 필요 (현재 정책은 .nova/events.jsonl만 측정) |
| 프라이버시 | tool_response 본문은 기록 X — tool_name + duration_ms + ok만. `_privacy-filter.py` 영향 없음 |
| 회귀 테스트 | 3건 추가 |

## Risk

- **중간**: events.jsonl 볼륨 증가. publish-metrics 4주 윈도우 처리 시간에 영향 가능. 대량 Bash 세션은 라인 1000+ 가능.
- **완화**: tool_use_post 이벤트는 publish-metrics aggregation 단계에서 **count + percentile**만 추출. JSONL은 append-only이므로 회전 정책(`scripts/rotate-events.sh`)으로 1주 이상 보관 X 정책 검토.

## 비채택 시 대안

duration_ms를 안 쓰고 PostToolUse 자체만 도입하면 "tool counts per session" 정도만 측정 가능. 그래도 가치는 있으나, duration_ms와 동반 채택이 효율적.

## Open Questions (Apply 시 해소)

- PostToolUseFailure 별도 훅 필요한가? — `tool_response.error` 필드로 PostToolUse에서 통합 처리 가능 (제안 채택)
- 모든 도구를 매처 ""로 받는가, 특정 도구만? — 시작은 모든 도구. 비용 문제 발견 시 high-volume 도구만 제외 매처 도입.

## 채택 시 적용 후속

- nova-rules.md §3(measurement) 또는 §6(observation)에 PostToolUse 수집 명시
- docs/guides/measurement.md에 도구별 KPI 사용 시나리오 추가
- v5.30.0 minor 릴리스로 묶음
