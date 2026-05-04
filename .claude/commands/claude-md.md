---
description: "안내와 함께 CLAUDE.md/AGENTS.md 에이전트 지침을 감사하고 신규/기존 프로젝트 기준으로 재구성안을 만든다."
description_en: "Show a guided intro, audit CLAUDE.md/AGENTS.md instructions, and propose a new/existing project reorganization."
---

# /nova:claude-md

프로젝트의 에이전트 지침 표면을 설계·정리한다. `CLAUDE.md`를 운영 헌법 + 라우터로 유지하고, 상세 절차·경로별 규칙·강제 가드·현재 상태를 올바른 위치로 분리한다.

## 적용 스킬

- `skills/claude-md/SKILL.md` — 신규/기존 프로젝트 지침 감사, 분리 기준, 생성 템플릿

## 사용법

```bash
/nova:claude-md                # 처음 사용자용 가이드 + 현재 레포 감사 시작
/nova:claude-md --check        # 수정 없이 감사만
/nova:claude-md --apply        # 승인된 재구성안 적용
/nova:claude-md --new          # 신규 프로젝트 지침 골격 생성
/nova:claude-md --adopt        # 기존 CLAUDE.md/AGENTS.md 재구성
/nova:claude-md --global-karpathy  # 개인 전역 Karpathy 압축 원칙 추가/갱신 여부 확인
```

인자가 없으면 **Guided Mode**로 실행한다. 먼저 60초짜리 짧은 안내를 보여주고, 현재 레포에 `CLAUDE.md`/`AGENTS.md`가 있는지에 따라 `--check` 또는 `--new`에 해당하는 안전한 제안 흐름으로 이어간다.

## 실행 규칙

1. 먼저 `skills/claude-md/SKILL.md`를 읽고 그 절차를 따른다.
2. 기존 지침 파일이 있으면 즉시 덮어쓰지 말고 섹션별 `keep / move / enforce / local-only / remove` 분류표를 만든다.
3. 신규 프로젝트는 모르는 정보를 추측하지 말고 `TODO(owner)` 또는 질문으로 남긴다.
4. hard guard는 CLAUDE.md 문장만으로 완료 처리하지 않는다. `.claude/settings.json`, hooks, CI, 스크립트 중 enforcement owner를 표시한다.
5. 정리 결과에는 반드시 다음 에이전트가 같은 기준을 적용할 수 있는 `Instruction Placement Contract`를 남긴다.
6. 인자가 없으면 Guided Mode를 먼저 출력한다. 사용자가 플래그를 몰라도 다음 행동을 선택할 수 있게 한다.
7. `--global-karpathy`는 프로젝트 파일이 아니라 `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`만 대상으로 하며, 수정 전 반드시 yes/no 확인을 받는다.

## Output

```text
━━━ Agent Instructions Audit ━━━━━━━━━━━━━
Mode: Existing / New / Nested
Loaded: CLAUDE.md N lines, AGENTS.md N lines, rules N, skills N, settings yes/no

Verdict:
- Size: PASS/WARN/FAIL
- Duplication: PASS/WARN/FAIL
- Enforcement gaps: N
- Cross-agent bridge: PASS/WARN/FAIL

Placement Plan:
| Source section | Classification | Destination | Reason |

Proposed files:
| File | Action | Notes |

Questions:
- {추측하면 안 되는 정보}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

# Input

$ARGUMENTS
