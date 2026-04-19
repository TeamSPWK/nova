---
description: "Explorer→Synth→Critic→Refiner 4단 파이프라인으로 깊이 있는 Plan 문서를 생성한다."
---

# Nova DeepPlan

스킬 `deepplan`을 실행한다.

사용자 입력을 그대로 스킬에 전달한다.

예시:
- /nova:deepplan "인증 미들웨어 교체"
- /nova:deepplan "멀티 테넌트 스키마 마이그레이션" --iterations=3
- /nova:deepplan "결제 모듈 리팩토링" --jury

## 언제 사용하나

| 상황 | 권장 커맨드 |
|------|------------|
| 일반 기능 추가, 버그 수정 | `/nova:plan` |
| 아키텍처 전환, 대형 마이그레이션, 보안 경계 변경 | **`/nova:deepplan`** |
| 실패 시 비용이 높은 판단 (DB 스키마, 인증 구조, 외부 API 연동) | **`/nova:deepplan`** |
| 사전에 대안을 충분히 탐색하고 싶을 때 | **`/nova:deepplan`** |

`/nova:deepplan`은 `/nova:plan` 대비 토큰 3~5×, 실행 시간 10~20분이 추가로 소요된다.
단순 기능 추가에는 과도하다. 명시적으로 "깊이 있는 플래닝이 필요하다"고 판단될 때만 사용한다.

## 플래그

| 플래그 | 설명 |
|--------|------|
| `--iterations=N` | Critic→Refiner 루프 반복 횟수 (1~3, 기본 1) |
| `--jury` | Critic 단계에서 jury 스킬(architect/security/qa 3 페르소나) 호출. 기본은 evaluator 스킬 단독 |

## 출력

- 파일: `docs/plans/{slug}.md`
- Plan 헤더에 `> Mode: deep`, `> Iterations: N` 마커 포함
- 기본 CPS 섹션 외 3개 섹션 추가: `## Risk Map`, `## Unknowns`, `## Verification Hooks`

deepplan 출력물은 기존 CPS 골격을 유지하므로 이후 `/nova:design`, `/nova:auto`에서 그대로 소비할 수 있다.

## Related: `/ultraplan`과의 역할 분리

Claude Code `/ultraplan`은 클라우드 CCR에서 최대 30분 전용 컴퓨트로 플래닝 세션을 돌리고 브라우저에서 인라인 코멘트로 반복 편집한다. `/nova:deepplan`과 **실행 모델이 달라 체인 통합하지 않는다.** 보완재로 병용한다.

| | `/nova:deepplan` | `/ultraplan` |
|---|---|---|
| 실행 | 로컬 동기 (터미널) | 클라우드 비동기 (브라우저 리뷰) |
| Critic | evaluator/jury 서브에이전트 (Anthropic 키만 필요) | 클라우드 전용 컴퓨트 |
| 출력 | `docs/plans/{slug}.md` — Nova 체인 직행 | 독립 결과 (Nova에 수동 흡수) |
| 적합 | 로컬 코드베이스 탐색 + 빠른 체인 연결 | 대형 팀 공유 문서, 브라우저 인라인 피드백 |
| 통합 | Plan → Design → auto 체인 자동 연결 | 독립 실행 (결과를 Nova에 수동 흡수) |

> 위 비교는 2026-04-19 시점 공개 문서 기준이며, Claude Code 업데이트에 따라 변경될 수 있다.

**언제 `/ultraplan`을 병용하나**
- 팀 리뷰가 필요한 대형 아키텍처 결정에서 브라우저 인라인 피드백이 필요할 때
- 터미널을 해방하고 플래닝을 병렬로 돌리고 싶을 때
- 결과를 `/nova:deepplan` 또는 `/nova:plan`에 **수동으로 옮겨** Nova 체인에 진입시킨다 — 자동 연동 없음

Nova 자체는 `/ultraplan`을 자동 호출하지 않는다. 사용자가 판단하여 독립 실행한다.

# Input
$ARGUMENTS
