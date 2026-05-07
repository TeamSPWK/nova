# Evolution Proposal: Plugin `bin/` 실행 가능 진입점

> 날짜: 2026-05-07
> 수준: minor
> 출처: Claude Code v2.1.91 (2026-04-02) — https://code.claude.com/docs/en/changelog
> 자율 등급: Semi Auto (PR)

## Context

CC v2.1.91에서 플러그인이 `bin/` 디렉터리에 실행 파일을 ship할 수 있게 됐고, Bash 도구에서 **bare command**로 호출 가능하다. 즉 사용자/AI가 `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh` 풀 경로 대신 `foo` 한 단어로 실행 가능.

## Problem

Nova는 사용자 직접 호출이 의도된 스크립트가 다수다:
- `scripts/publish-metrics.sh` — 4주 KPI 발행 (사용자 가이드: `docs/guides/measurement.md`)
- `scripts/analyze-observations.sh` — 행동 패턴 분석 (`/nova:evolve --from-observations`가 호출)
- `scripts/capture-visual-intent.sh` — UI 의도 캡처 (G1 게이트)
- `scripts/visual-self-verify.sh` — UI 자가 검증 (G3 게이트)
- `scripts/release.sh` — 릴리스 자동화

현재는 모두 `bash scripts/foo.sh` 또는 `bash "${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh"`로 호출해야 한다. 사용자 가이드에 풀 경로를 노출하면 가독성·기억성이 떨어지고, AI가 매번 정확한 경로를 추적해야 한다.

## Solution

Nova가 사용자에게 **공식 노출**하는 스크립트를 `bin/`에 thin wrapper로 등록한다.

### 후보 (5종)

| bin 이름 | 위임 대상 | 사용자 가이드 |
|----------|----------|--------------|
| `nova-publish-metrics` | `scripts/publish-metrics.sh` | docs/guides/measurement.md |
| `nova-analyze-observations` | `scripts/analyze-observations.sh` | /nova:evolve --from-observations |
| `nova-capture-intent` | `scripts/capture-visual-intent.sh` | docs/guides/ui-quality-gate.md |
| `nova-self-verify-visual` | `scripts/visual-self-verify.sh` | docs/guides/ui-quality-gate.md |
| `nova-release` | `scripts/release.sh` | CLAUDE.md release workflow |

> 기준: 사용자/AI가 명시적으로 호출하는 진입점만. 내부 헬퍼(`bump-version.sh`, `init-nova-state.sh` 등)는 제외.

### bin/ wrapper 형식

```bash
#!/usr/bin/env bash
# Nova bin wrapper — delegates to scripts/publish-metrics.sh
exec bash "${CLAUDE_PLUGIN_ROOT}/scripts/publish-metrics.sh" "$@"
```

### 회귀 가드

`tests/test-scripts.sh`에:
- `bin/` 5개 파일 존재 + 실행 권한
- 각 wrapper가 `${CLAUDE_PLUGIN_ROOT}/scripts/` 경로를 참조

### 문서 갱신

다음 가이드의 호출 예제를 bin 이름으로 우선 표기:
- `docs/guides/measurement.md`
- `docs/guides/ui-quality-gate.md`
- `commands/evolve.md` (--from-observations 섹션)
- README.md / README.ko.md "Quickstart"

기존 `bash scripts/foo.sh` 표기는 fallback으로 유지(과거 가이드 링크 호환).

## Impact

| 영역 | 영향 |
|------|------|
| 사용자 UX | 짧은 명령어로 호출 가능 — 가이드 가독성 ↑, AI 호출 신뢰성 ↑ |
| 디스크 | bin/ 디렉토리 5 파일 추가 (~1KB) |
| 호환성 | CC v2.1.91 미만에서는 PATH 등록 안 됨 → 사용자가 풀 경로 fallback 사용. 가이드에 두 형식 모두 표기 |
| 보안 | wrapper는 단순 exec — 주입 표면 X |

## Risk

- **낮음**: 기존 `scripts/*.sh`는 그대로 유지. bin/은 alias 레이어.
- **고려**: bin 이름 충돌 — 사용자 시스템에 `nova-release` 같은 이름의 다른 도구가 있으면 충돌 가능. `nova-` prefix로 충돌 가능성 매우 낮음.

## Open Questions (Apply 시 해소)

- CC가 `bin/` 디렉토리를 자동 PATH 등록하는 시점은? — 공식 문서: "invokable as bare commands from Bash tool". 즉 Bash 도구 한정. 일반 터미널은 영향 없음.
- 사용자가 비활성화 가능한가? — `disableSkillShellExecution` 설정과 무관. bin 자체 disable 옵션 미확인 → Apply 시 검증.

## 비채택 / 일부 채택 시 대안

5개 모두 일괄 도입이 부담스러우면 단계 도입:
- 1차: `nova-publish-metrics` (사용자 가이드 가장 두드러짐)
- 2차: visual G1+G3 페어 (사용자 마찰 가장 큰 두 스크립트)
- 3차: 나머지

## 채택 시 적용 후속

- `commands/evolve.md` --from-observations 섹션에 bin 이름 표기
- v5.30.0 minor 릴리스 — 제안 1·2와 묶음
- 후속: `claude plugin tag` 채택 시 nova-release를 plugin tag로 점진 이관 검토 (별 제안)
