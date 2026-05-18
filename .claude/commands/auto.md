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

## autoMode 안전 가드 (Claude Code v2.1.136+)

자동 실행 흐름에서 위험 명령을 차단하려면 사용자 `.claude/settings.json`의 `autoMode.hard_deny` 배열을 활용한다 (CC v2.1.136 도입). Nova `/nova:auto`는 LLM 분류 기반이라 명시적 deny 규칙과 **병행 사용** 권장.

```jsonc
{
  "autoMode": {
    "allow": ["$defaults"],
    "soft_deny": ["$defaults"],
    "hard_deny": [
      "Bash(rm -rf *)",
      "Bash(git push --force*)",
      "Bash(*sh -c *rm -rf*)"
    ]
  }
}
```

- `hard_deny`는 분류기 우회 불가능한 무조건 거부. `--emergency` 모드에서도 적용됨.
- Nova `/nova:setup --permissions`로 관리되는 `permissions.deny`(런타임 차단)와 직교 — 둘 다 활용이 안전 기반선.
- **광범위 glob 주의**: `*rm*`처럼 단어 일부만 매칭하면 `terraform`, `performance`, `platform` 등 정상 명령도 차단된다. 명령 + 공백을 포함한 정확한 패턴(`rm -rf`)을 권장.
- 출처: https://code.claude.com/docs/en/changelog (v2.1.136)

## 관련

- 단일 완료 조건의 다중-턴 자동 진행은 Anthropic 공식 `/goal` 커맨드(CC v2.1.139+, Research Preview). Nova `/nova:auto`는 CPS 구조 + Generator-Evaluator 분리 + 5기둥 통합으로 차별화.

# Input

$ARGUMENTS
