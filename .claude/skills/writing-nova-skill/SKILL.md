---
name: writing-nova-skill
description: "새 Nova 스킬을 작성하거나 기존 스킬 description을 수정할 때. — MUST TRIGGER: skills/ 하위 신규 SKILL.md 생성, 기존 SKILL description 리팩터, 사용자가 'Nova 스킬 추가/수정' 요청 시."
description_en: "Use when authoring a new Nova skill or revising an existing skill's description. — MUST TRIGGER: creating a new SKILL.md under skills/, refactoring an existing SKILL description, or when the user asks to 'add or modify a Nova skill'."
user-invocable: false
---

# Writing a Nova Skill

Nova 스킬을 작성/수정할 때 따라야 할 규약. **Jesse Vincent(obra/superpowers)의 실측 발견** — *"description이 workflow를 요약하면 Claude가 본문 대신 description을 따라간다"* — 을 Nova에 흡수한 메타-스킬.

## 핵심 규약

### 1. Description = When-to-use only

description은 **언제 발동하는가**만 기술한다. HOW(동작 방식)은 본문으로.

**금지:**
- `→`, `파이프라인`, `4단`, `Explorer×3` 같은 단계 열거
- "X로 Y를 Z한다" 형식의 동작 기술 전체
- "엔진", "시스템"만 선언하는 정체성 홍보 (예: "Nova XXX 엔진 —")

**요구:**
- "...할 때.", "...가 필요한 경우" 같은 트리거 표현
- `MUST TRIGGER: ...` 섹션에 트리거 조건 3개 이상
- 사용자 요청 패턴 포함 (예: "사용자가 /nova:xxx 호출 시")

**예시 (evaluator):**
- ❌ "Nova Adversarial Evaluator — Nova Quality Gate의 핵심 검증 엔진. 독립 서브에이전트로 코드를 적대적 관점에서 검증."
- ✅ "코드 구현을 적대적 관점으로 검증해야 할 때. — MUST TRIGGER: /run, /check, /review 내부에서 독립 서브에이전트로 호출, 스프린트 완료 직후, 커밋 전 Evaluator PASS 필요 시."

### 2. 본문 구조

1. 한 문단 — 스킬 목적 + Nova 5기둥 내 위치
2. `## 핵심 원칙` — 설계 결정 3~5개
3. `## 적용 규칙 (on-demand 로드)` — 참조하는 nova-rules §N 번호
4. `## 오케스트레이션 추적` — `mcp__plugin_nova_nova__orchestration_update` 호출 의무 (해당 시)
5. 예시 / 안티패턴

### 3. 트리거 회귀 테스트 (MUST)

새 스킬 추가 시 `tests/skill-triggering/prompts/{name}-positive.txt` 제출 의무.

- positive: 이 스킬이 **반드시 발동해야 할** 사용자 프롬프트 1개
- negative (선택): 이 스킬이 **발동하면 안 되는** 유사 맥락 프롬프트

`tests/test-skill-triggering.sh`가 각 `skills/*/SKILL.md`에 대응하는 positive fixture 존재를 강제한다. 누락 시 CI FAIL.

실제 LLM 트리거 검증은 `/nova:field-test`로 수동 수행.

### 4. 동기화 체크리스트 (CLAUDE.md와 일치)

새 스킬 추가 시:
1. `hooks/session-start.sh` 커맨드 목록 영향 여부 확인 (커맨드 아니면 대개 불필요)
2. `tests/test-scripts.sh`의 description lint 통과 확인
3. `docs/nova-meta.json` — `bump-version.sh`가 자동 재생성 (수동 편집 금지)
4. `tests/skill-triggering/prompts/{name}-positive.txt` 제출

## 안티패턴

- description을 짧게 만들려고 트리거를 생략한다 → Claude가 언제 쓸지 판단 못 함
- "5인 적대 평가자", "3단 파이프라인" 같은 숫자 홍보 → 본문 스킵 유발
- 여러 목적을 한 스킬에 몰아넣는다 → 트리거 모호, 본문 비대

## 근거 (왜 이 규약이 존재하는가)

- `obra/superpowers/skills/writing-skills/SKILL.md` — *"Testing revealed that when a description summarizes the skill's workflow, Claude may follow the description instead of reading the full skill content"*
- `memory/project_nova_competitive_analysis_2026_04_23.md` — 경쟁 분석 결과 9개 Nova SKILL 중 5개가 이 안티패턴에 해당, Tier 1.1에서 일괄 리팩터
- Nova 5기둥 중 **협업 기둥** — 스킬이 제 때 발동하지 않으면 에이전트 협업이 붕괴한다
