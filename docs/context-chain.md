# Context Chain — 컨텍스트 유지 체계

> Nova Pillar: Idempotent — "6개월 뒤 돌아와도 읽고 유지보수 가능"

세션이 끊겨도, 팀원이 바뀌어도, AI 모델이 바뀌어도 — 맥락은 살아있어야 한다.

---

## 3계층 메모리 아키텍처

```
Layer 1: Ephemeral (휘발성)     ← 현재 대화, 작업 중 상태
Layer 2: Persistent (영속성)    ← CLAUDE.md, 메모리, 의사결정 기록
Layer 3: Structural (구조적)    ← 설계 문서, git history, 린터 규칙
```

### 실용적 매핑: 어떤 정보를 어디에 저장하는가

| 정보 유형 | 저장 위치 | 수명 | 예시 |
|----------|----------|------|------|
| 현재 작업 내용 | 대화 컨텍스트 | 세션 내 | "지금 인증 모듈 리팩토링 중" |
| 프로젝트 규칙/컨벤션 | `CLAUDE.md` | 프로젝트 전체 | 네이밍 규칙, 기술 스택 |
| 기능 계획 | `docs/plans/` | 기능 수명 | CPS Plan 문서 |
| 기술 설계 | `docs/designs/` | 기능 수명 | CPS Design 문서 |
| 의사결정 | `docs/decisions/` | 영구 | 왜 PostgreSQL을 선택했는가 |
| 다관점 수집 결과 | `docs/verifications/` | 영구 | 멀티 AI 합의 기록 |
| 코드 변경 이유 | git commit message | 영구 | feat: 인증 모듈 추가 |
| 코드 구조/패턴 | 코드 자체 | 영구 | 함수명, 디렉토리 구조 |
| **진행 상태/Known Gaps** | **`NOVA-STATE.md`** | 프로젝트 전체 | 스프린트 이력, 미커버 경계값 |

---

## 컨텍스트 복원 프로토콜

새 세션을 시작할 때 다음 순서로 맥락을 복원한다:

### Step 1: 프로젝트 맥락 (자동)
```
CLAUDE.md 로드 → 프로젝트 전체 규칙/구조 파악
```
Claude Code가 자동으로 수행. CLAUDE.md가 잘 작성되어 있으면 별도 작업 불필요.

### Step 2: 최근 작업 흐름
```bash
git log --oneline -20   # 최근 변경 사항 확인
git status              # 진행 중 작업 확인
```

### Step 3: 의사결정 맥락 (필요시)
```
docs/decisions/  → 최근 의사결정 확인
docs/plans/      → 진행 중인 Plan 확인
docs/designs/    → 참조할 설계 문서 확인
```

### Step 4: 세션 상태 확인 (있는 경우)
```
NOVA-STATE.md 확인 → 스프린트 이력, 블로커, Known Gaps 파악
```
프로젝트 루트에 `NOVA-STATE.md`가 있으면 반드시 읽는다. 진행 중 스프린트, 미해소 블로커, Known Gaps를 확인하고 이어서 작업한다.

### Step 5: 이어서 작업
위 정보를 바탕으로 중단된 작업을 이어서 진행.

---

## NOVA-STATE.md 작성 원칙

`NOVA-STATE.md`는 세션 간 상태를 이어주는 인덱스 파일이다. 50줄 이내를 유지한다.

### 즉시 업데이트 트리거 (마지막에 몰아서 하지 않는다)

다음 이벤트 발생 즉시 업데이트한다:
- 배포 성공/실패
- 테스트 통과/실패
- 스프린트 완료
- 블로커 발생/해소
- 검증(Evaluator) 결과 수신

### 스프린트 전환 이력 기록

8개 이상 파일을 수정하는 작업은 스프린트로 분할한다. 전환 시 다음 형식으로 기록한다:

```
## Sprint History
- Sprint 1 완료 (2026-04-01) → 사용자 확인 → Sprint 2 시작
- Sprint 2 완료 (2026-04-01) → 사용자 확인 → Sprint 3 시작
```

### Known Gaps 필수 기록

검증 후 발견된 미커버 영역을 반드시 기록한다. "ALL PASS"만 기록하면 과신을 유도한다.

```
## Known Gaps
- [ ] 결제 모듈 경계값(0원, 음수) 미테스트
- [ ] 인증 토큰 만료 엣지 케이스 미검증
- [x] 사용자 조회 빈 문자열 처리 — v3.6.1에서 수정
```

---

## 디렉토리 구조

```
docs/
├── plans/              # CPS Plan 문서 (Phase: Plan)
├── designs/            # CPS Design 문서 (Phase: Plan→Do)
├── decisions/          # 의사결정 기록 (Phase: 전체)
├── verifications/      # 다관점 수집 결과 (Phase: Check)
├── templates/          # 문서 템플릿
│   ├── cps-plan.md
│   ├── cps-design.md
│   ├── decision-record.md
│   └── claude-md.md
├── nova-engineering.md # 방법론 상세
└── context-chain.md    # 이 문서

NOVA-STATE.md           # 세션 상태 인덱스 (프로젝트 루트)
```

---

## 원칙

1. **파일이 곧 메모리다** — 특별한 도구 없이, 파일 시스템이 컨텍스트 저장소
2. **구조가 복원을 보장한다** — 일관된 디렉토리 구조 + 템플릿 = 누구나 찾을 수 있음
3. **git이 시간을 기록한다** — 의사결정의 "언제"와 "누가"는 git이 담당
4. **CLAUDE.md가 입구다** — 모든 맥락의 시작점. 여기서부터 추적 가능해야 함
5. **가볍게 유지한다** — 문서를 위한 문서를 만들지 않는다. 실용적인 것만 기록
6. **즉시 기록한다** — NOVA-STATE.md는 이벤트 발생 즉시 업데이트. 나중에 몰아서 하면 이력이 유실된다
7. **갭은 숨기지 않는다** — Known Gaps를 명시해야 "의도적 미구현"과 "누락"을 구분할 수 있다
