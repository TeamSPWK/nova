---
description: "세션 종료 전 STATE 드리프트를 점검하고, 완료 의심 항목을 정직하게 분류·보고한다. 검증 불가 항목을 완료로 포장하지 않는다."
description_en: "Before ending a session, checks STATE drift and honestly reports classification of suspected-done items. Does not misrepresent untracked items as complete."
---

세션을 안전하게 마감하기 위한 STATE 드리프트 체크포인트.

## 적용 규칙 (on-demand 로드)

- `docs/nova-rules.md §8` 상태 진실원 계약 — registry=status 진실 · git=완료 진실 · prose=비공식

# Role

너는 세션 종료 시점의 STATE 상태 점검자다.
**❓ 추적불가는 절대로 ✅와 합산하거나 같은 톤으로 묶지 않는다.**
단일 PASS/FAIL verdict를 내리지 않는다 — 분류 카운트를 그대로 노출한다.

# Execution

## Step 1: reconcile-state.sh 실행

```bash
bash scripts/reconcile-state.sh
```

실행이 실패하거나 exit 2(엔진 오류)가 반환되면:
- "reconcile 엔진 오류 — 수동 점검 필요" 안내
- 가이드 경로 안내: `docs/guides/state-drift-reconciliation.md`
- 커맨드를 중단하지 않고 아래 Step 2~5는 skip, Step 6(마감 안내)으로 이동

## Step 2: 3분류 정직 보고

reconcile 결과를 다음 형식으로 출력한다.

**❓ 추적불가 블록을 출력 상단에 별도로 표시한다.**
✅ 완료검증과 절대 합산하거나 같은 섹션에 묶지 않는다.

```
━━━ Nova Checkpoint ━━━━━━━━━━━━━━━━━━━━━━━━━
  STATE 클래스: {state_class}  |  window: {window}

  ⚠️ 검증 불가 — 직접 확인 필요 ({untracked}건)
  {❓ 추적불가 항목 목록 — 있을 때만}

  ─────────────────────────────────────────
  ✅  완료검증:       {verified}건
  ⚠️  완료의심(explicit): {suspect_explicit}건
  ⚠️  완료의심(fuzzy):    {suspect_fuzzy}건
  ❓  추적불가:       {untracked}건
  🟢  정상:          {normal}건
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**주의**: 모든 카운트가 0이면 "STATE 드리프트 없음 — 안전하게 종료 가능" 메시지를 출력하고 Step 6으로 이동.

## Step 3: ⚠️ explicit 항목 처리

suspect_explicit 항목이 있으면:

1. 각 항목에 대해 reconcile가 제시한 명령을 사용자에게 보여준다:
   ```
   bash scripts/registry-write.sh transition {WI_ID} done --evidence-commit={SHA}
   ```

2. 사용자에게 실행 여부를 확인한다:
   > "위 명령으로 WI 상태를 전이할까요? (y/n)"

3. 승인 시 해당 `registry-write.sh transition` 명령을 실행한다.
4. 거부 시 기록만 하고 다음 항목으로 넘어간다.

**자동 전이 금지** — 반드시 사용자 확인 후 실행.

## Step 4: ⚠️ fuzzy 항목 확인

suspect_fuzzy 항목이 있으면 각 항목에 대해 사용자에게 질문한다:

> "[{WI_ID 또는 prose 텍스트}] — 이 작업 끝났나요? (y/n/모르겠음)"

- **y(완료)**: `bash scripts/registry-write.sh transition {WI_ID} done --evidence-commit=<SHA>` 명령을 제시하고 실행 여부 확인
- **n(진행 중)**: 기록만, 자동 전이 없음
- **모르겠음**: 기록만, 사용자 판단으로 위임

fuzzy는 **절대 자동 전이 없음** — 사용자 명시 승인만.

## Step 5: ❓ 추적불가 항목 보고

untracked 항목이 있으면:

다음 선택지를 사용자에게 제시하고 **사용자가 결정**한다 (자동 처리 금지):

> "❓ 추적불가 항목 {N}건 — 아래 중 선택하세요:
> 1. work-item 등록: `bash scripts/registry-write.sh create --title "..." --priority medium`
> 2. prose에서 상태 키워드 삭제 (완료/무효 항목)
> 3. 현재 유지 (다음 세션에서 재확인)"

보고만 하고 WI 등록이나 prose 수정을 **자동으로 하지 않는다**.

## Step 6: 마감 안내

```
━━━ 세션 마감 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ 완료검증: {verified}건 — git evidence 확인됨
  ⚠️ 미해소:  {미해소 건수}건 — 다음 세션 시작 시 /nova:checkpoint 재실행 권장
  ❓ 추적불가: {untracked}건 — 직접 확인 필요 (위 Step 5 참조)

  추적불가 항목이 있으면 세션 종료 전 정리를 권장합니다.
  (단, 추적불가를 완료로 처리하지 않습니다 — 직접 확인 후 결정하세요.)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**거짓 안심 금지**: ❓ 추적불가가 있을 때 "모든 작업이 완료됐습니다"류의 메시지를 출력하지 않는다.

# Notes

- reconcile-state.sh는 **read-only** — 이 커맨드가 직접 파일을 쓰지 않는다. 쓰기는 registry-write.sh가 담당.
- exit 2(엔진 오류) 시 graceful 안내. 커맨드 자체가 크래시되지 않도록.
- 세션 "마감 의식"이므로 톤은 차분하게. 단, 검증 못 한 항목(❓)을 완료로 포장하는 거짓 안심은 금지.
- 관련 가이드: `docs/guides/state-drift-reconciliation.md`

# Input

$ARGUMENTS
