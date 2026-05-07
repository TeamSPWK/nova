# Plan: Competitive Evolution Roadmap (Tier 1~4)

**작성일**: 2026-04-23
**현재 버전**: v5.16.1
**근거**: `memory/project_nova_competitive_analysis_2026_04_23.md` (ECC + superpowers 정밀 비교)

## Context

everything-claude-code(affaan-m)와 obra/superpowers 두 메가히트 플러그인을 실제 파일 기반으로 적대적 비교한 결과, Nova의 **검증된 P0 약점 3가지**가 식별됨:

1. SKILL description 9개 중 5개가 workflow 요약 포함 → Jesse 실측(writing-skills/SKILL.md): "description에 workflow가 요약되면 Claude가 본문을 스킵한다"
2. 스킬 트리거 회귀 테스트 부재 — superpowers의 `tests/skill-triggering/prompts/*.txt`에 해당하는 검증 없음
3. Adaptive 기둥이 외부 스캔(`/evolve`)에만 머물고 **사용자 행동 학습** 없음 — ECC `continuous-learning-v2`와 가장 큰 격차

## Problem

추가로 중장기 구조 격차:

| 격차 | 경쟁자 근거 | Nova 영향 |
|------|-------------|-----------|
| 사전 차단 게이트 부재 | ECC `gateguard-fact-force` | 30분 오구현 후 커밋 시점에만 되돌림 |
| 훅 강도 런타임 조절 부재 | ECC `ECC_HOOK_PROFILE` | `--emergency` 예외 외 빠른 hotfix 경로 없음 |
| 방법론 A/B 측정 문화 부재 | superpowers v5.0.6 "25분 오버헤드 제거" | 규칙 추가만 하고 제거 기전 없음 |
| 메타-스킬 부재 | superpowers `writing-skills` | 새 스킬 작성 규약 없음 |
| 합리화 차단 리스트 부재 | superpowers Red Flags 12가지 | "이렇게 하지 말라"가 명시되지 않음 |
| GAN 3단 루프 부재 | ECC gan-planner/generator/evaluator | Plan 단계는 deepplan 4단, 구현 단계는 1패스 |
| 서브에이전트 bootstrap 격리 없음 | superpowers `<SUBAGENT-STOP>` | session-start 1200자+를 서브에이전트도 받음 |
| Cross-harness 미지원 | superpowers references/*-tools.md | Claude Code 전용 (정체성 결정 필요) |

## Solution

### Tier 1 — v5.17.0 (즉시 반영, 저비용·고가치)

**1.1 SKILL description 리팩터** — `"When to use" 트리거 조건만` 규약 적용
- 대상: deepplan, evolution, orchestrator, ux-audit, 기타 workflow 요약 포함 스킬
- 원칙: description에 `→`, `파이프라인`, 단계 열거 제거 → "언제 발동하는가"만
- 검증: `tests/test-scripts.sh`에 description lint 추가 (workflow 키워드 금지 grep)

**1.2 tests/skill-triggering/ 신설**
- `tests/skill-triggering/prompts/*.txt` 10~15개 (각 Nova 스킬별 positive + negative 프롬프트)
- `tests/test-skill-triggering.sh` — 스킬별 "이 프롬프트에서 이 스킬이 발동해야 한다" 의도 문서화
- 실제 실행 검증은 nova:field-test와 연동 (수동)

**1.3 writing-nova-skill 메타-스킬**
- `skills/writing-nova-skill/SKILL.md` — "description = When to use, workflow는 본문, MUST TRIGGER 명시, 트리거 fixture 제출"
- `/nova:plan` + `/nova:design`과 연계

**릴리스**: v5.17.0 "Skill Discipline — description lint + trigger fixture + meta-skill"

### Tier 2 — v5.18.0 (중기 진화)

**2.1 pre-edit-check.sh 강화**: 편집 전 NOVA-STATE 또는 최근 CPS 설계 기록 탐지. 없으면 경고(블로킹 아님) + CPS 선행 권장
**2.2 NOVA_PROFILE=lean|standard|strict**: `session-start.sh` 런타임 분기. `--emergency`를 `lean` 프로파일의 한 케이스로 재정의
**2.3 릴리스 "제거 리포트" 섹션 의무화**: `scripts/release.sh`에 체크리스트 추가 — "이번 릴리스에서 제거/비활성한 규칙·단계와 근거"
**2.4 docs/nova-antipatterns.md**: 에이전트 합리화 12가지 + Nova 특화 회피 패턴. session-start.sh에 "Antipatterns 요약" 링크

**릴리스**: v5.18.0 "Adaptive Control — profile + pre-edit + removal report + antipatterns"

### Tier 3 — v5.19.0 or v6.0.0 (장기 진화)

**3.1 Behavior-Learning 엔진**: PreToolUse 이벤트를 `§10 관찰성 JSONL`로 확장 → `/nova:evolve`가 외부 스캔뿐 아니라 **사용자 행동 패턴**을 CPS Problem 초안으로 제안. 자동 승격 금지(사용자 승인 필수) — "AI는 제안, 인간은 결정" 원칙 유지
**3.2 Evaluator GAN 3단 확장**: `agents/evaluator` 1패스 → `generator → evaluator → refiner` 사이클. `skills/evaluator/SKILL.md` 계약 확장
**3.3 <SUBAGENT-STOP> bootstrap 격리**: `hooks/session-start.sh`에 서브에이전트 감지 분기. 토큰 즉시 절감

**릴리스**: v5.19.0(호환 유지) or v6.0.0(evaluator 계약 변경 시) — 범위 확정 후 결정

### Tier 4 — 정체성 결정 필요

**Cross-harness 진출 여부**: Nova = Claude Code 전용 vs 방법론 보편. superpowers `references/*-tools.md` 저비용 진입점. **사용자 판단 후 진행**.

## Verification (각 Tier 공통)

1. `tests/test-scripts.sh` 전체 통과
2. `bash hooks/session-start.sh | python3 -m json.tool` JSON 유효
3. `/nova:review` Evaluator PASS
4. `scripts/release.sh <patch|minor|major>` 자동 체인 통과

## Out of Scope

- ECC의 "180 스킬" 같은 수평 확장 — Nova의 격자형 구조 유지
- SQLite state store — NOVA-STATE.md 단일 파일 유지
- ECC_HOOK_PROFILE 이름 그대로 복제 — NOVA_PROFILE로 독자 네이밍
