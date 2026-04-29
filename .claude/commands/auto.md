---
description: "자연어 요청을 설계→구현→검증→수정 전체 사이클로 자동 실행한다."
description_en: "Auto-run a natural-language request through the full design → implement → verify → fix cycle."
---

# Nova Auto

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §6` 복잡한 작업의 스프린트 분할
- `docs/nova-rules.md §7` 블로커 분류 (Auto/Soft/Hard)
- `docs/nova-rules.md §9` 긴급 모드 (`--emergency`: 즉시 수정, 검증 사후)
- `docs/nova-rules.md §10` 관찰성 계약 — Phase 전이·스프린트·블로커 이벤트 기록 (orchestrator 스킬이 담당)

스킬 `orchestrator`를 실행한다.

사용자 입력을 그대로 스킬에 전달한다.

예시:
- /nova:auto "proptech-lab에 건폐율 시각화 추가"
- /nova:auto "nova-landing 한국어 버전 추가" --design-only
- /nova:auto "3개 프로젝트에 다크모드 통일" --strict
- /nova:auto --deep "대규모 인증 시스템 교체"
- /nova:auto --fresh --deep "기존 Plan 무시하고 깊은 재설계"

## 플래그

| 플래그 | 동작 |
|--------|------|
| (없음) | 전체 사이클 (설계→구현→검증→수정). 기존 Plan/Design 있으면 자동 재사용 |
| `--design-only` | 설계까지만 (구현 전 확인용) |
| `--skip-qa` | QA 생략 (빠른 프로토타이핑) |
| `--strict` | QA를 Full 검증으로 강제 |
| `--fresh` | 기존 Plan/Design 무시, 강제 fresh Architect (escape hatch) |
| `--deep` | deepplan(Explorer×3 병렬→Synth→Critic→Refiner) 호출 후 결과 Plan으로 파이프라인 진입. 아키텍처 전환·큰 마이그레이션에 권장. Plan이 이미 존재하면 `--deep` 무시 + 경고 |
| `--fresh --deep` | 기존 Plan 무시 + deepplan으로 새 Plan 생성 후 파이프라인 진입 |

# Input

$ARGUMENTS
