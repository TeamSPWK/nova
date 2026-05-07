# Evolution Scan: 2026-05-07

> 날짜: 2026-05-07
> 모드: --scan
> 출처: Anthropic 공식 changelog (CC v2.1.89~v2.1.132)

## Context

지난 스캔(2026-04-29) 이후 Claude Code v2.1.121~v2.1.132 릴리스가 누적되며 hook API · plugin 시스템 · MCP 설정에서 Nova가 흡수할 수 있는 변경이 발생했다. Nova 현재 상태(v5.29.1)에 대한 영향과 적용 가능성을 정리한다.

## 스캔 범위

| 소스 | 발견 | 관련 | 출처 |
|------|------|------|------|
| Anthropic 공식 changelog | ~30건 | 8건 | https://code.claude.com/docs/en/changelog |
| Claude Code 생태계 | 5건 | 1건 | claudemarketplaces.com / buildwithclaude.com |
| 하네스 도구 (aider/cursor) | 8건 | 0건 | dev.to 비교 자료 |
| AI 엔지니어링 | 4건 | 0건 | 일반 트렌드 |

**관련성 필터**: Nova 4 Pillar(Structured/Consistent/X-Verification/Adaptive) 또는 commands/skills/agents/hooks 직접 영향 항목만 통과.

## Nova에 이미 반영됐거나 갭 아님

| 변경 | Nova 상태 | 비고 |
|------|----------|------|
| PreCompact hook (v2.1.105) | ✅ 적용 — `hooks/pre-compact.sh` 작동 중 | Stop event도 이미 운영 |
| `/ultrareview` 내장 (v2.1.111) | ✅ 문서화 — `commands/review.md` Related, run.md/check.md 참조 | 보완재 정책 명시 |
| Plugin manifest `themes`/`monitors` → `experimental` (v2.1.129) | ✅ 영향 없음 — Nova plugin.json은 두 키 미사용 | 사후 채택 시 새 위치 사용 |
| `claude project purge` (v2.1.126) | ✅ 영향 없음 — Nova는 NOVA-STATE.md 자체 트림 | guide 갱신 후보(낮음) |
| `defer` PreToolUse decision (v2.1.89) | ⊘ 비채택 — Nova 게이트는 즉시 차단(exit 2) 정책 | 의도와 충돌, 도입 X |
| Hook `type: "mcp_tool"` (v2.1.118) | ⊘ 비채택 — Nova hooks는 bash 단일 진입점 유지 (단순성 우선) | 복잡도 증가 대비 이득 미미 |

## 채택 제안 (3건)

| # | 제목 | 수준 | 근거 |
|---|------|------|------|
| 1 | Nova MCP 서버 `alwaysLoad: true` | minor | Nova MCP 도구가 deferred — 사용자가 매번 ToolSearch 거쳐야 호출. CC v2.1.121 신기능 직접 해소 |
| 2 | PostToolUse 훅 + `duration_ms` 캡처 | minor | measurement-spec.md에 duration_ms 스펙은 있으나 **수집 경로 없음**(현재 stop-event 턴 단위만). 도구별 실측 가능 |
| 3 | Plugin `bin/` 실행 가능 스크립트 노출 | minor | publish-metrics/analyze-observations 등 사용자 직접 호출 진입점 단순화. CC v2.1.91 신기능 |

각 제안의 상세 문서:
- `docs/proposals/2026-05-07-mcp-alwaysload.md`
- `docs/proposals/2026-05-07-posttooluse-duration-capture.md`
- `docs/proposals/2026-05-07-plugin-bin-executables.md`

## 비채택 / 보류

| 항목 | 판단 |
|------|------|
| `monitors` manifest 키 (v2.1.105) | 보류 — Phase 2 nova-metrics가 trigger 미도달(NOVA-STATE 명시). 동반 도입 시 함께 검토 |
| Hook `updatedToolOutput` 활용 (v2.1.121) | 보류 — Evaluator 결과 메인 주입 우회로로 매력적이나 Generator-Evaluator 분리 약화 위험. X-Verification Pillar 침해 가능성 |
| `claude plugin tag` (v2.1.118) | 보류 — release.sh 검증 단계 대체 후보. 시멘버 검증 실측 후 v6.x 마이그레이션 검토 |
| Skill description 1,536자 확장 (v2.1.105) | 보류 — 현 description 명확. 늘리는 것이 가독성 손해 가능 |

## 리스크 요약

- 제안 1·2·3 모두 **plugin update만으로 자동 적용**(수동 설정 금지 원칙 부합).
- API 키 추가 의존성 없음.
- 기존 회귀 테스트(681)에 영향 가능 — 제안별 회귀 가드 추가 필요.

## Apply 모드 진행 시

`/nova:evolve --apply`로 호출 시 다음 순서 권장:
1. 제안 1 (MCP alwaysLoad) — 단일 키 추가, 가장 단순
2. 제안 2 (PostToolUse duration_ms) — hooks.json + record-event.sh 확장
3. 제안 3 (bin/ 노출) — scripts/ 일부를 bin/ 심볼릭 링크 또는 분리

각 제안마다 Gate 1(tests) → Gate 2(/nova:review --fast) 통과해야 다음 진입.
