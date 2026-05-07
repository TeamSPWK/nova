# [Design] Self-Verification 흡수 — Sprint 1

> Nova Engineering — CPS Framework
> 작성일: 2026-04-17
> 작성자: jay-swk (via Nova)
> Plan: docs/plans/self-verify-absorption.md
> 범위: **Sprint 1만** — 핸드오프 `self_verify` 필드 정의 + 수신

---

## 설계 한계 (투명성 고지)

이 Design은 **Opus 4.7 실사용 체감 없이** 작성됐다. 사용자가 세션 종료·재시작 불가 상태에서 진행 필요. 따라서:

- self_verify 필드 스키마는 **Generator 에이전트가 명시적으로 채우도록 지시**하는 구조. 모델이 자동으로 뱉는 포맷에 의존하지 않음
- 추후 4.7 체감 후 필드 구조 조정 필요 가능 → Sprint 2 착수 전 재검토 체크포인트 삽입

---

## 1. self_verify 필드 스키마

기존 Generator → Evaluator 핸드오프(`.claude/skills/orchestrator/SKILL.md:145`)에 **5번째 필드** 추가.

### 포맷

```markdown
## 변경 요약
- 변경 파일: {파일 목록}
- 변경 의도: {한줄 요약}
- 주요 결정: {트레이드오프 선택 이유}
- 알려진 제한: {미구현/의도적 생략 항목}
- self_verify:
  - confident: {구현자가 "확신"하는 영역 — 테스트 통과 + 로직 단순}
    - 예: "src/auth/login.ts:42 — 단위 테스트로 3개 케이스 모두 통과 확인"
  - uncertain: {불확실 영역 — 경계값·에러 처리·동시성·외부 의존}
    - 예: "session 만료 타이밍 — 5분 경계에서 race condition 가능성"
  - not_tested: {실행 검증 미수행 영역}
    - 예: "DB 마이그레이션 롤백 — 로컬에서 실행 불가, 검증 필요"
```

### 필드 스키마 원칙

| 원칙 | 설명 |
|------|------|
| **선택 필드** | self_verify 없어도 정상 동작 — 하위호환 보장. 기존 핸드오프는 4개 필드만 사용 |
| **최대 3개 서브필드** | confident/uncertain/not_tested 외 추가 금지 — 인지 부하 방지 |
| **항목별 근거 필수** | "확신한다"만 쓰지 말고 "왜 확신하는지" 한 줄 근거 포함 |
| **자기 확신 경계 표시** | Generator가 "uncertain/not_tested 0건"이면 오히려 의심 — 자기 과신 시그널 |

### 하위호환 동작

- self_verify 필드가 **없는** 핸드오프: 기존 검증 로직 그대로 (Layer 1~3 전체 수행)
- self_verify 필드가 **있는** 핸드오프: Evaluator가 읽어서 판정 report에 "Generator 신호 검토" 섹션 추가. **Sprint 1에서는 참고용으로만 사용** — Layer 배분 변경은 Sprint 2에서.

---

## 2. 파일별 변경

### 2.1 `.claude/skills/orchestrator/SKILL.md` (line 145~155 블록)

핸드오프 포맷 코드블록에 self_verify 필드 추가. 그 바로 아래에 원칙 설명 3~5줄 추가.

### 2.2 `.claude/skills/evaluator/SKILL.md` (§구조화된 핸드오프 입력, line 220~229)

"아티팩트가 있으면 1~3번 수행" 목록에 **4번 추가**:
> 4. **Generator 자가 검증 신호 검토**: `self_verify` 필드가 있으면 confident/uncertain/not_tested 항목을 판정 report에 명시적으로 언급. 단, Sprint 1에서는 Layer 배분에 영향 주지 않고 참고용으로만 사용한다. Generator의 confident 영역에서 Critical 이슈 발견 시 **self-preference bias 시그널**로 별도 표기.

### 2.3 `.claude/agents/senior-dev.md`

- Output Format "코드 변경 시" 블록에 self_verify 섹션 추가
- "Nova 자가 점검"에 체크 추가:
  - [ ] self_verify 필드를 핸드오프에 포함했는가? (uncertain/not_tested 0건이면 자기 과신 의심)

### 2.4 `.claude/agents/devops-engineer.md`

- Output Format "CI/CD 설정" 블록에 self_verify 섹션 추가 (senior-dev와 동일 스키마)
- "Nova 자가 점검"에 체크 추가

### 2.5 (변경 없음) architect / qa-engineer / security-engineer

- **검증 전용 에이전트**이므로 Generator 역할 아님 → self_verify 불필요
- evaluator SKILL.md의 Generator-Evaluator 시스템 레벨 분리 §3 표 기준 (qa-engineer, security-engineer, architect는 검증 전용)

---

## 3. 검증 기준 (Done 조건)

- [ ] 기존 핸드오프(필드 없음)로 Evaluator 호출 시 정상 동작 — 하위호환
- [ ] 새 필드 포함 핸드오프로 Evaluator 호출 시 판정 report에 "Generator 자가 검증 신호" 섹션 포함
- [ ] senior-dev, devops-engineer가 Output Format에 self_verify 지시를 받음
- [ ] `bash tests/test-scripts.sh` 205/205 통과
- [ ] Evaluator 서브에이전트 Gate 2 PASS

---

## 4. Self-preference Bias 방어선 (Sprint 1 최소 구현)

Evaluator가 self_verify의 `confident` 영역에서 Critical 이슈를 발견하면 판정 report에 다음 표기:

```
## self-preference bias 시그널
- Generator: confident — "src/auth/login.ts:42 테스트 통과"
- Evaluator: FAIL — "src/auth/login.ts:42 null 체크 누락, SQL 인젝션 가능"
- 해석: Generator의 자기 확신 영역에 blind spot 존재. 향후 동일 도메인 변경 시 --strict 승격 검토 권장.
```

**Sprint 1은 표기만** — 자동 승격 로직은 Sprint 3에서 구현.

---

## 5. 변경 수준 및 릴리스

- **수준**: minor (기존 프로토콜 확장 + 새 기능 개선)
- **버전**: v5.2.3 → v5.3.0
- **커밋 메시지**: `feat(sprint1): Self-verify 흡수 — 핸드오프 self_verify 필드 + Evaluator 수신 + Generator 지시`

---

## 6. Known Gaps (Sprint 2+로 이관)

| Gap | Sprint |
|-----|--------|
| self_verify 신호 기반 Layer 배분 최적화 | Sprint 2 |
| Generator-Evaluator 충돌 탐지 → NOVA-STATE.md 자동 기록 | Sprint 3 |
| Adaptive 자동 승격 로직 (2회 충돌 시 --strict) | Sprint 3 |
| Jury에 self-verify 참여 (가중치 0.5) | Sprint 4 |
| Opus 4.7 실사용 샘플 기반 스키마 재검토 | Sprint 2 착수 전 체크포인트 |

---

## 7. 수정 파일 목록 (최종 4개)

1. `.claude/skills/orchestrator/SKILL.md`
2. `.claude/skills/evaluator/SKILL.md`
3. `.claude/agents/senior-dev.md`
4. `.claude/agents/devops-engineer.md`

(+ Design 문서 자체는 `docs/designs/`이라 gitignore 대상 — 로컬 전용)
