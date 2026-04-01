# 튜토리얼: Todo API로 배우는 Nova 워크플로우

> 하나의 기능을 `/nova:plan` → `/nova:xv` → `/nova:design` → 구현 → `/nova:gap` → `/nova:review`까지 따라가는 실전 예시

---

## Step 1: Plan — 왜, 무엇을 만드는가

```
/nova:plan Todo API
```

CPS 구조로 정리합니다:

### Context (배경)
- 프로젝트에 할 일 관리 기능이 필요
- REST API로 프론트엔드와 통신

### Problem (문제)
- 핵심: Todo의 CRUD 기능이 없어 사용자가 할 일을 관리할 수 없다
- MECE 분해:
  1. 생성 (Create) — 새 할 일 추가
  2. 조회 (Read) — 할 일 목록 보기
  3. 수정 (Update) — 완료 처리
  4. 삭제 (Delete) — 할 일 제거

### Solution (해결)
- Express.js 기반 REST API
- 4개 엔드포인트: POST, GET, PATCH, DELETE

→ 산출물: `docs/plans/todo-api.md`

---

## Step 2: X-Verify — 기술 판단 교차검증 (필요시)

DB 선택에서 고민이 있다면:

```bash
/nova:xv "Todo API의 데이터 저장소: 인메모리 vs SQLite vs PostgreSQL, MVP 단계에 최적은?"
```

3개 AI가 동시에 답변하고, 합의율이 자동 산출됩니다:

- 90%+ → 자동 채택 (예: "MVP에서는 SQLite로 시작")
- 70~89% → 차이점 보고 사람이 판단
- 70% 미만 → 질문 재정의 필요

→ 산출물: `docs/verifications/2026-03-26-todo-db-선택.md`

---

## Step 3: Design — 어떻게 만드는가

```
/nova:design Todo API
```

기술 설계를 구체화합니다:

```markdown
## API 설계

### POST /api/todos — 생성
- Request: { title: string }
- Response: { id, title, completed: false, createdAt }

### GET /api/todos — 목록
- Response: Todo[]

### PATCH /api/todos/:id — 완료 처리
- Response: { id, completed: true }

### DELETE /api/todos/:id — 삭제
- Response: 204 No Content

## 데이터 모델
- id: string (uuid)
- title: string
- completed: boolean
- createdAt: Date
```

→ 산출물: `docs/designs/todo-api.md`

---

## Step 4: 구현

설계에 따라 코드를 작성합니다:

```typescript
// src/api/todos.ts
import { Router } from 'express';

const router = Router();

router.post('/', (req, res) => {
  const { title } = req.body;
  const todo = { id: crypto.randomUUID(), title, completed: false, createdAt: new Date() };
  res.json(todo);
});

router.get('/', (req, res) => { /* ... */ });
router.patch('/:id', (req, res) => { /* ... */ });
router.delete('/:id', (req, res) => { /* ... */ });

export default router;
```

---

## Step 5: Gap Check — 설계대로 만들었는가

```bash
/nova:gap docs/designs/todo-api.md src/
```

만약 DELETE 엔드포인트를 깜빡하고 구현하지 않았다면:

```
━━━ 📊 갭 분석 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  매칭률:  75%
  판정:    ⚠️  REVIEW NEEDED

  ✅ 구현 완료:
    • Todo 생성 API (POST /api/todos)
    • Todo 목록 조회 API (GET /api/todos)
    • Todo 완료 처리 API (PATCH /api/todos/:id)

  ❌ 미구현:
    • Todo 삭제 API (DELETE /api/todos/:id)
```

→ DELETE 구현 후 다시 Gap Check → 매칭률 90%+ 되면 PASS

Gap Check에서 확인하는 추가 검증 항목:

**요구사항 원문 대조**: 설계 문서의 요구사항과 실제 구현을 1:1로 대조한다.
- 예: `POST /api/todos` — Request body에 `title`이 없을 때 400 반환하는가?

**데이터 관통**: 입력 → 저장 → 로드 → 응답까지 전 구간이 연결되는가?
- 예: Todo를 생성(POST)하면 목록 조회(GET)에서 실제로 나타나는가?

**경계값**: 핵심 로직이 경계 입력에서 크래시 없이 동작하는가?
- `title`: 빈 문자열 `""`, 공백만 `" "`, 매우 긴 문자열
- `id`: 존재하지 않는 UUID로 PATCH/DELETE 시 404 반환하는가?

---

## Step 6: Review — 코드 품질 점검

```
/nova:review src/api/todos.ts
```

단순성 원칙으로 코드를 리뷰합니다:
- 불필요한 복잡성은 없는가?
- 에러 핸들링은 적절한가?
- 네이밍은 명확한가?

> **테스트 통과 ≠ 검증 완료**: 테스트가 모두 통과해도 경계값(빈 title, 없는 id)에서 크래시가 없는지 추가로 확인한다.

Gap Check와 Review를 한 번에 실행하려면 `/nova:verify`를 사용한다:

```
/nova:verify src/api/todos.ts
```

---

## 전체 흐름 요약

```
"Todo API 만들어줘"
    │
    ├─ /nova:plan → 왜 필요한지, 뭐가 문제인지 정리
    │
    ├─ /nova:xv → DB 선택 등 기술 판단 교차검증 (선택)
    │
    ├─ /nova:design → 구체적 API 설계
    │
    ├─ 구현 → 코드 작성
    │
    ├─ /nova:gap → 설계 vs 구현 비교 (DELETE 누락 발견!)
    │
    ├─ 수정 → DELETE 구현
    │
    ├─ /nova:gap → 재검증 (매칭률 90%+ → PASS)
    │
    └─ /nova:review → 코드 품질 최종 점검
```

이 과정을 거치면:
- 뭘 만들어야 하는지 명확하고 (Plan)
- 기술 판단에 근거가 있고 (X-Verify)
- 어떻게 만들지 구체적이고 (Design)
- 빠뜨린 게 없는지 자동으로 잡히고 (Gap)
- 코드 품질도 점검됩니다 (Review)

---

## Known Gaps (이 튜토리얼 기준)

검증 후에도 의도적으로 다루지 않은 영역을 명시한다. "ALL PASS"만 기록하면 과신을 유도한다.

| 항목 | 상태 | 비고 |
|------|------|------|
| 인메모리 저장소 | 의도적 미구현 | MVP 단계 — 서버 재시작 시 데이터 소멸 |
| 인증/권한 | 미구현 | 튜토리얼 범위 외 |
| `title` 최대 길이 제한 | 미검증 | 실제 서비스 전 경계값 테스트 필요 |
| 동시성 (동일 id 동시 수정) | 미검증 | 인메모리 환경에서는 race condition 가능 |
