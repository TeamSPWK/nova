# [Plan] NOVA-STATE.md 드리프트 클래스 구조적 차단 — 계약 + 대조 엔진 + 3개 진입점

> Nova Engineering — CPS Framework
> 작성일: 2026-05-20
> 작성자: Nova DeepPlan
> Mode: deep
> Iterations: 1
> Design: designs/state-drift-reconciliation.md

---

## Context (배경)

### 현재 상태

NOVA-STATE.md는 한 파일 안에 **진실을 주장하는 평면이 둘** 공존한다:

- **v3 marker 영역** (`<!-- nova:registry-rendered:start/end -->`) — `scripts/registry-render-state.sh`가 `.nova/work-items/` registry에서 자동 렌더. 손편집 금지.
- **손편집 prose 영역** (Current / Active Tree 손작성본 / Risks & Gaps) — 사람·AI가 손으로 쓰는 스냅샷. registry와 연결 안 됨, 자동 갱신 안 됨.

두 평면 사이에 **계약(contract)이 없다.** 어느 쪽이 status의 진실인지, 충돌하면 누가 이기는지 규칙이 없다.

### 왜 필요한가

다운스트림 프로젝트 `swk-ground-control`에서 `/nova:next`가 **이미 완료된 작업**(`gc-cost-jump --cron-window` 가드, 커밋 `af5912f`)을 "진행 중"으로 추천하는 stale 버그가 발생했다. 추적 결과 3개 층의 드리프트가 드러났다:

- **Layer A — 등록 갭**: follow-up이 work-item으로 등록조차 안 됨 → registry-render 대상 자체가 없음, 손편집 prose에만 존재.
- **Layer B — 완료 전이 갭 (keystone)**: WI를 `done`으로 바꾸는 경로(`registry-write transition done` / `evaluator-pass`)는 `/nova:run`·`/nova:auto`만 호출. **평범한 `git commit`으로 고치면 done 전이가 안 일어난다.** 등록된 WI였어도 status는 영구 `active`.
- **Layer C — prose 무효화 갭**: `/nova:next`는 `git log`를 읽지만, prose의 "진행 중" 주장과 git log의 완료 커밋을 **대조해 prose를 stale로 무효화하는 규칙이 없다.**

핵심 통찰: **레지스트리도 은탄환이 아니다.** cron-window가 처음부터 WI였어도, 평범한 커밋으로 고치면 `transition done`이 호출 안 돼 똑같이 썩는다 → **Layer B(commit↔done 연결)가 keystone.** sync 지점을 아무리 추가해도 드리프트는 재발한다 — 진짜 원인은 **계약 부재**다.

### Layer B를 실증하는 Nova 자기 레포 데이터 (Critic 검증으로 확정)

이 버그는 Nova 레포 자신에게도 살아있다. `.nova/events.jsonl` 실측:

- `registry_rendered` 8건 — 자동 렌더는 정상 작동.
- `work_item_created` / `work_item_transitioned` / `work_item_updated` / `work_item_review_required` — **전부 0건.**
- `registry-write.sh`는 `record_event_safe`로 이 이벤트들을 발화하도록 코딩돼 있다 (L365/452/543/622/666). 코드는 정상.

→ 결론: **`registry-write.sh`의 `create`/`transition` 경로가 Nova 레포에서 단 한 번도 실행된 적이 없다.** 12개 WI는 전부 `migrate-state-v3.sh` 일괄 마이그레이션 산출물이며 전부 `proposed` 상태(notes="이전 STATE에서 done이었음")로, transition 경로를 통과한 적이 없다. frontmatter `goal: v5.41.0`은 실제 버전 `v5.44.1`과 5개 마이너 릴리스만큼 어긋나 있다.

이는 Layer B가 keystone이라는 주장을 **데이터로 확정한다** — 전이 경로가 진입점에 연결되지 않으면 registry는 status 진실원이 될 수 없다. dogfooding 검증 대상이 확보돼 있다.

### 관련 자료

- `scripts/check-state-drift.sh:1-144` — 코드 변경 vs NOVA-STATE.md mtime 검증 (cross-platform epoch util 재사용 가능)
- `scripts/registry-drift-check.sh:1-294` — Hard 9 + Warn 9 룰셋. W8(marker 손편집 dry-run→diff 비교), W1(STATE 7일+ 미갱신)
- `scripts/registry-render-state.sh:1-245` — marker 블록 자동 렌더
- `scripts/registry-write.sh:1-690` — registry 단일 쓰기 경로 (create/update/transition/evaluator-pass/require-review). `transition <wi> done --evidence-commit=SHA`
- `hooks/pre-commit-reminder.sh:1-226` — PreToolUse stdin JSON 훅, 7상태 Evaluator Hard Gate (STATE_STALE·META_STALE 경고 이미 발화 중)
- `hooks/record-event.sh:16-19` — work_item_created / work_item_transitioned / registry_rendered 이벤트
- `.claude/commands/next.md:1-194` — 현재 진단 로직
- `docs/nova-rules.md:196-207` — §8 세션 상태 유지 (데이터 모델 분리 v5.44.0+). **Recent Activity / Recently Done 표는 v5.44.0+에서 손편집 대상 아님 — v3 marker 자동 렌더 또는 비어있음**

---

## Problem (문제 정의)

### 핵심 문제

NOVA-STATE.md의 손편집 prose와 v3 work-item registry가 **계약 없는 두 진실 평면**이라, 완료된 작업이 prose에 "진행 중"으로 남아 `/nova:next`가 stale 추천을 낸다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | **계약 부재** | prose/registry 평면 간 권위 규칙 없음. 충돌 시 누가 이기는지 미정의 | 🔴 High |
| 2 | **대조 부재** | prose의 status 주장을 git log·registry와 대조하는 메커니즘 없음. `check-state-drift`는 mtime만, `registry-drift-check`는 registry 내부만 검사 | 🔴 High |
| 3 | **commit↔done 단절 (keystone)** | 평범한 `git commit`이 WI를 `done`으로 전이시키지 않음. `/nova:run`·`auto`만 전이 → registry status 자체가 stale. Nova 레포 `work_item_transitioned` 0건이 실증 | 🔴 High |
| 4 | **진입점 산재·부재** | next/pre-commit/marker-render가 각각 진단. 사용자가 명시 호출하는 "마감" 진입점 없음 | 🟡 Med |
| 5 | **enforcement 부재** | "prose에 status 쓰지 마라"가 규칙으로도 없고 탐지도 없음 → 다음 세션에 또 손편집 | 🟡 Med |

> 5개 영역은 인과 사슬(1→2·3, 2·3→4·5)이되 산출물 영역은 겹치지 않는다: 1=문서 규칙, 2·3=엔진 로직, 4=진입점, 5=탐지 룰.

### 제약 조건

- **pre-commit-reminder.sh는 PreToolUse 훅** → 커밋 시점에 SHA가 아직 없다. **advisory nudge만 가능**, SHA 자동 기입 불가. (SHA가 필요한 자동 전이는 Stop hook/post-commit 경로 — Solution 결정 #3 참조)
- **WI title이 날짜 문자열뿐** (`"title": "2026-05-14"`) → registry는 키워드 매칭 대상 텍스트가 없음. **registry는 `evidence.commit_sha` 정확매칭만 신뢰** 가능.
- **한글 prose ↔ 영문 커밋 prefix**(`feat:`/`fix:`/`chore:`) 반복 → fuzzy 매칭 노이즈 floor가 높음.
- **`registry-write.sh` create/transition 경로 미사용 (확정)** — `work_item_*` 이벤트 0건. registry가 status 진실원이 되려면 진입점이 실제로 transition을 호출해야 함. 이것이 Layer B 수정의 핵심 레버.
- **v2 / hybrid / v3 STATE 혼재** — 엔진이 STATE 클래스를 판정 후 분기해야 함. Nova 레포는 현재 hybrid(schema_version:2 + v3 marker).
- **Recent Activity / Recently Done 표는 status 탐지 대상이 아니다** — `nova-rules.md §8`(v5.44.0+)이 손편집 금지·자동 렌더로 재정의. 엔진은 이 표 + v3 marker 영역을 prose-status 탐지에서 명시 제외해야 한다 (오탐 방지).
- 동기화 의무: `docs/nova-rules.md` 수정 시 `hooks/session-start.sh` 동기화 + JSON 유효성 + 테스트. 신규 커맨드/스크립트 체크리스트(가이드·README·EXPECTED_COMMANDS·`-h`).
- 사용자 승인 스코프: 계약 강제는 **"엔진 경고" 수준** — 하드 게이트(`exit 2` 차단) 아님. (단 Layer 5 효과 미달 시 승격 경로는 Unknowns에 명시 — 사용자 결정 영역)

---

## Solution (해결 방안)

### 선택한 방안

**방안 A — 신규 `scripts/reconcile-state.sh` 1개 + 단계적 3 스프린트 출시.**

option-explorer 권장안. 사용자 승인 스코프 4항목(계약 명문화 / 신규 대조 엔진 1개 / 진입점 3개 / commit↔WI 연결)을 변형 없이 그대로 구현한다. 신규 엔진은 `check-state-drift.sh`(코드↔STATE mtime)·`registry-drift-check.sh`(registry 내부 18룰)와 책임이 명확히 구분돼 SRP를 지키고 exit code 규약 충돌이 없다. `check-state-drift.sh`의 cross-platform epoch util과 `registry-drift-check.sh`의 W8 dry-run→diff 패턴만 부분 재사용한다.

**핵심 설계 결정 (Explorer 종합 + Critic 반영):**

1. **계약이 곧 충돌 resolution 규칙이다.** registry=status 진실 · git=완료 진실 · prose=status를 갖지 않는 비공식 메모(Goal·관찰·서사). 따라서 prose의 status 주장은 **정의상 비권위** — 충돌하면 prose가 진다. 엔진은 prose status 주장을 "대조 대상 용의자"로만 취급한다. hybrid STATE에서 prose Recent Activity의 ✅ 기록과 registry WI의 `proposed`가 충돌하면 → prose 비권위 원칙으로 prose가 진다(엔진은 "hybrid 이행 미완" 경고 동반).

2. **3분류 + 정상.** 🟢정상 / ✅완료검증(`evidence.commit_sha` reachable, 또는 명시적 `Nova-WI:` 링크) / ⚠️완료의심(prose는 진행 중인데 git log에 키워드·시간윈도우 일치 커밋, 또는 evidence SHA 고아) / ❓추적불가(prose에만 존재, WI 없음, 일치 커밋 없음). **⚠️·❓는 자동 done 전이 절대 금지 — 사용자에게 보여주는 질문일 뿐.**

3. **commit↔WI 연결 = nudge(예방) + reconcile 탐지(포착) 이중 그물.** Layer B(keystone)는 **nudge 단독으로 안 닫힌다** — `work_item_transitioned` 0건이 "에이전트가 상기 없이는 transition 안 한다"의 실증이다(단 nudge 자체가 부재했으므로 "nudge해도 무시한다"의 증거는 아님). 따라서:
   - **예방**: pre-commit nudge가 에이전트에게 "커밋 후 `registry-write transition <wi> done --evidence-commit=$(git rev-parse HEAD)` 호출"을 상기.
   - **포착**: nudge가 무시돼도 `/nova:next`·`/nova:checkpoint`가 reconcile 엔진을 돌려 un-transition된 WI를 ⚠️로 잡는다.
   - **Design 검토 대상**: 커밋 메시지 trailer `Nova-WI: WI-xxxx`가 있으면 — trailer는 에이전트의 **명시적 기계 판독 선언**이므로 fuzzy와 다르다 — Stop hook(SHA 존재 시점)에서 **자동 transition**하는 경로. nudge를 유일 메커니즘으로 확정하지 않는다. (자동 전이는 trailer가 있을 때만; fuzzy·무trailer는 ⚠️까지만.)

4. **enforcement = 탐지하되 차단 안 함(Warn). 단 효과를 측정한다.** 엔진이 prose의 **구조적 위치**(Risks & Gaps 상태 칼럼 / 체크박스 / Active Tree 손작성 prose)에서 status 어휘를 탐지해 **Warn 등급**으로 보고한다. **Recent Activity / Recently Done 표와 v3 marker 영역은 탐지 대상에서 제외**(v5.44.0 §8 정합). 자유 텍스트 "진행 중"(예: "X는 결정 대기 중")은 오탐 방지를 위해 제외. `exit 2` 하드 차단은 하지 않는다(사용자 스코프 준수).
   - **솔직한 한계 인정**: 기존 Warn(STATE_STALE)이 `goal: v5.41.0` 5릴리스 누적을 못 막은 것은 "Warn은 무시될 수 있다"의 실증이다. 따라서 Warn이 Layer 5를 닫는다고 단정하지 않는다. Verification Hook #13으로 출시 후 Warn 무시율을 측정하고, 미달 시 "release.sh 위생 게이트 승격"을 사용자 결정 안건으로 올린다(Unknowns 참조).

5. **discipline 의존 완화.** checkpoint를 사용자 호출에만 의존시키지 않는다 — `session-start.sh`가 reconcile를 advisory로 1회 실행해 결과를 additionalContext에 주입(기존 W1 stale 패턴 재사용), `/nova:next`는 추천 전 reconcile를 무조건 선행 실행.

6. **엔진은 read-only 불변식.** `reconcile-state.sh`는 **어떤 파일도 쓰지 않는다**(상태 변경 0, stdout 보고만). 이 불변식 덕분에 여러 진입점(pre-commit + session-start + next)이 동시 호출해도 race가 무해하다 — lock 설계 불요. 전이가 필요하면 호출자(에이전트/커맨드)가 `registry-write.sh`(자체 lock 보유)를 통해 수행한다.

### 대안 비교

| 방안 | 접근 | 장점 | 단점 | 권장도 |
|------|------|------|------|--------|
| A | 신규 `reconcile-state.sh` 1개 + 단계적 출시. 계약은 nova-rules §8+session-start. commit↔WI는 trailer+nudge+reconcile 포착. 계약 강제는 엔진 경고 수준 + 효과 측정 | 기존 2개 drift 스크립트와 exit code/severity 충돌 없음. read-only라 race-free. 단계적 출시로 가이드·테스트·동기화 부담 분산 | 스크립트 3개로 늘어 "뭘 언제 쓰나" 혼동 가능 → 가이드로 완화 | ⭐ |
| B | `registry-drift-check.sh` 확장(W10~12 룰) + 3 진입점 동시 출시 | 진실원 스크립트 1개로 수렴. 검증된 인프라 재사용 | `registry-drift-check`는 registry 내부 검사기 — prose 대조는 SRP 위반. 한 릴리스에 대형 변경 → 최소 코드·릴리스 단위 위배, Evaluator 부담 급증 | |
| C | 계약을 하드 게이트로 + commit-msg 훅 신설로 trailer 강제 | 드리프트 구조적 원천 차단 | `commit-msg` 훅 타입은 Claude Code 스펙 미검증 의존. 자연어 "진행 중" 단어 차단은 정상 메모 오차단 → §8 계약과 모순. 사용자 스코프(경고 수준) 초과 | |

### 구현 범위

**Sprint 1 — 계약 + 엔진 + `/nova:next` 통합 (엔진과 최소 진입점을 원자 출시):**
- [ ] `docs/nova-rules.md §8`에 계약 명문화 — registry=status 진실 / git=완료 진실 / prose=status 없는 메모 / 충돌 resolution = prose 비권위
- [ ] `hooks/session-start.sh` 동기화 — §8 계약 요약 주입 (JSON 유효성 + 테스트)
- [ ] `scripts/reconcile-state.sh` 신규 — **read-only 불변식**. STATE 클래스 판정(v2/hybrid/v3) → prose↔git log↔registry 3-way 대조 → 3분류 출력. `-h`/`--help`로 가이드 경로 안내. `--jsonl` 기계 판독 출력. `check-state-drift.sh` cross-platform epoch util 재사용
- [ ] prose-status 어휘 탐지 — 구조적 위치 한정. **Recent Activity/Recently Done 표 + v3 marker 영역 명시 제외**. Warn 등급
- [ ] `.claude/commands/next.md` — 추천 전 reconcile-state.sh 선행 실행, ⚠️/❓ 항목을 추천에서 제외/플래그, 신뢰도 순위(git log > registry > prose) 명문화
- [ ] `docs/guides/state-drift-reconciliation.md` 사용자 가이드 (TL;DR + 절차 + FAIL 시 해결 + cheatsheet)
- [ ] `tests/test-scripts.sh` 회귀 가드 — reconcile-state.sh `-h` + 가이드 파일 존재 + 핵심 키워드 + 3 fixture(v2/hybrid/v3) 파서 정확성
- [ ] `README.md` / `README.ko.md` 가이드 링크

**Sprint 2 — 진입점 ① pre-commit nudge + commit↔WI 연결:**
- [ ] `hooks/pre-commit-reminder.sh` 확장 — reconcile-state.sh 호출, **drift ⚠️/❓ ≥ 1건일 때만 조건부 nudge**, 기존 STATE_STALE·META_STALE 경고와 **단일 블록 통합**, drift 0건이면 침묵
- [ ] commit↔WI 연결 — nudge가 "커밋 후 `registry-write transition done --evidence-commit` 호출" 상기. trailer `Nova-WI:` 컨벤션 문서화 + Stop hook 자동 transition 경로 설계 검토
- [ ] 성능 예산 — reconcile 호출이 pre-commit을 지연시키지 않도록 타임아웃 + graceful skip

**Sprint 3 — 진입점 ③ /nova:checkpoint + session-start advisory:**
- [ ] `.claude/commands/checkpoint.md` 신규 — 세션 종료 의도적 체크포인트. 3분류 정직 보고(❓를 ✅과 합산 금지, 별도 경고 블록 상단) + 해결 대화형 제안
- [ ] `.claude/skills/checkpoint/SKILL.md` (로직 복잡 시) — 또는 커맨드 단독
- [ ] `hooks/session-start.sh` 커맨드 목록에 `/nova:checkpoint` 추가 + session-start advisory reconcile 1회 실행
- [ ] `.claude/commands/next.md` 워크플로우 추천 경로에 checkpoint 추가
- [ ] `tests/test-scripts.sh` `EXPECTED_COMMANDS`에 checkpoint 추가
- [ ] `bump-version.sh` → `nova-meta.json` + README 테이블 자동 갱신 확인

### 검증 기준

`## Verification Hooks` 참조. 핵심: (1) reconcile-state.sh가 STATE 3 클래스 정확 분기 + 파서 무오작동 (2) Nova 자기 레포 dogfooding — `goal` frontmatter 불일치 + 12개 proposed WI 탐지 (3) 원래 버그 재현 차단 (4) ❓가 ✅과 합산 안 됨 (5) pre-commit nudge drift 0건 시 침묵 (6) `bash tests/test-scripts.sh` 전체 PASS.

---

## Sprints (스프린트 분할)

수정·신규 파일 11개 이상 → 3 스프린트로 분할. **S1은 엔진과 최소 진입점(`/nova:next`)을 함께 묶어 출시** — "엔진은 있는데 진입점이 없어 아무도 안 쓰는 상태"(events.jsonl 0건의 전례)를 구조적으로 불가능하게 한다.

| Sprint | 범위 | 신규/수정 파일 | 릴리스 |
|--------|------|---------------|--------|
| **S1** | 계약 + 대조 엔진 + `/nova:next` 통합 | `nova-rules.md`·`session-start.sh`·`next.md`(수정) · `reconcile-state.sh`·`guides/state-drift-reconciliation.md`(신규) · `test-scripts.sh`·README×2(수정) | minor — **출시 즉시 next.md로 엔진 사용** |
| **S2** | 진입점 ① pre-commit nudge + commit↔WI | `pre-commit-reminder.sh`(수정) · commit↔WI 컨벤션 문서 | minor |
| **S3** | 진입점 ③ /nova:checkpoint + session-start advisory | `commands/checkpoint.md`·`skills/checkpoint/SKILL.md`(신규, skill 조건부) · `session-start.sh`·`next.md`·`test-scripts.sh`(수정) | minor |

의존성: S1(엔진+next) → S2·S3. S2와 S3는 S1 이후 병렬 가능하나 단계적 출시로 S2 → S3 순서 권장. **S1만 출시돼도 `/nova:next`가 엔진을 쓰므로 "미사용 엔진" 상태가 안 된다.**

---

## Risk Map

| 리스크 | 가능성 | 영향 | 완화 |
|--------|--------|------|------|
| **WI title이 날짜 문자열뿐** — 대조 엔진이 키워드 매칭할 텍스트 자체가 없음 → 3분류 전량 ❓로 떨어짐 | H | H | 대조 엔진 설계 전 WI title/notes 정규화 선행. 빈 title WI는 reindex로 source_docs·커밋 메시지에서 역추출. registry는 `evidence.commit_sha` 정확매칭만 사용 |
| **fuzzy 키워드 false positive** — 한글 prose ↔ 영문 커밋 부분일치로 무관 커밋을 ⚠️ 오인. `feat/fix` prefix 반복으로 노이즈 floor 높음 | H | M | ⚠️는 "사용자에게 보여주는 질문"으로만, 자동 done 전이 금지. 매칭점수 + 시간윈도우(prose 날짜 ±N일) 교차로만 후보 산출. evidence.commit_sha 정확매칭 1순위. Verification Hook #12로 오탐률 정량 측정 |
| **거짓 안심 — checkpoint가 ❓를 "검증 완료"로 흡수** — 12 WI 전부 evidence 없음·proposed | H | H | ❓를 ✅과 같은 톤으로 합산 금지. "검증 못 함 N건"을 별도 경고 블록으로 항상 상단 노출. PASS/FAIL 단일 verdict 금지, 3분류 카운트 그대로 노출 |
| **계약 enforcement 효과 미달** — Warn 등급이 무시당함. `goal: v5.41.0` 5릴리스 누적 = 기존 Warn(STATE_STALE) 무시 실증 | H | H | Warn으로 Layer 5가 닫힌다고 단정하지 않음. Verification Hook #13으로 출시 후 Warn 무시율 측정 → 미달 시 "release.sh 위생 게이트 승격"을 사용자 결정 안건으로(Unknowns) |
| **커밋 nudge alarm fatigue** — pre-commit이 이미 STATE_STALE+META_STALE 2종 발화 중. Nova 커밋이 릴리스 단위로 잦음 | M | M | nudge는 drift ⚠️/❓ 1건+ 일 때만 조건부. 기존 경고와 단일 블록 통합. drift 0건이면 침묵 |
| **squash/rebase로 evidence.commit_sha 고아화** — done WI가 존재하지 않는 SHA 가리킴 → ⚠️로 강등돼 끝난 작업 재부상 | M | M | SHA 정확매칭 + fallback `git log --all --grep` + 커밋 날짜 범위. SHA 부재 시 FAIL 대신 "SHA 재바인딩 필요" 분류 |
| **v2/하이브리드/v3 혼재 — 엔진 동작 분기** — 현 레포가 하이브리드. pre-commit hook은 v2 분기로 Recent Activity 표만 봄 | H | H | 엔진 진입 시 STATE 클래스 명시 판정 후 분기. 하이브리드는 "이행 미완" 경고 + prose Recent Activity를 status 진실원으로 불인정. v2-only 입력 경로 우선 정의 |
| **discipline 의존 — checkpoint 실행 망각** — checkpoint·next 모두 사용자 호출 의존 | M | M | session-start.sh에서 reconcile를 advisory 1회 실행해 additionalContext 주입. next.md는 추천 전 reconcile 무조건 선행 |
| **엔진 파서 오작동** — awk/grep 기반 파서가 hybrid STATE의 marker 내부 `⬜`를 prose로 오인, 또는 정상 표를 status로 오탐 | M | H | reconcile를 read-only로 설계해 오탐이 파일을 망치진 않음. 3 fixture(v2/hybrid/v3) 파서 단위 테스트(Verification Hook #1). marker 영역·시계열 표 명시 스킵 |
| **대조 엔진 동시 실행 race** — pre-commit + session-start + next가 동시 호출, registry-render가 marker를 다시 쓰는 중 reconcile가 읽음 | M | M | reconcile-state.sh를 **read-only 불변식**으로 설계(Solution 결정 #6) — 읽기 전용이면 race 무해, lock 불요 |
| **엔진 지연** — reconcile가 git log + registry + prose 파싱을 매 pre-commit/session-start마다 수행. session-start는 응답 지연 민감 | M | M | 성능 예산 reconcile < 500ms. session-start advisory는 git log 범위를 최근 N커밋 제한. 타임아웃 시 graceful skip(`|| true` 패턴 재사용) |

---

## Unknowns

- **`commit↔WI done 연결`의 trailer 컨벤션 상세** — `Nova-WI:` trailer의 정확한 형식, 누락 시 fallback, 다중 WI 커밋 처리, Stop hook 자동 transition의 발화 조건은 Design 대상. (Plan은 "nudge+reconcile 포착 + trailer 시 Stop 자동전이 검토"로 방향만 확정.)
- **3분류 임계값·시간 윈도우 수치 미정** — ⚠️완료의심의 키워드 일치 최소 점수, 매칭 시간 윈도우(±며칠), 한↔영 매칭 신뢰 가중치가 미정. Design에서 Nova 자기 레포 git log로 캘리브레이션 후 Verification Hook #12 기준값 확정.
- **v2-only STATE(marker 없는 형제 레포)에서 엔진 동작 범위** — 계약 (1)은 registry 존재를 전제하는데 v2-only에는 WI registry가 없다. checkpoint가 "registry 부재"로 skip할지 prose↔git 2-way 축소 동작할지 Design 결정. SWK 형제 레포 다수가 이 상태일 가능성 — 적용 범위에 큰 영향.
- **[사용자 결정 영역] Layer 5 enforcement 강도** — Warn 출시 후 무시율이 높으면(Verification Hook #13) "reconcile 통과를 `release.sh` 위생 게이트로 승격"할지는 사용자 판단. Plan은 Warn으로 시작하되 승격 경로를 열어둔다. 하드 게이트는 사용자 명시 승인 전까지 채택 안 함.

---

## Verification Hooks

> Sprint Contract 씨앗 — 이후 `/nova:design` 단계에서 구체화한다.

| # | 검증 항목 | 검증 방법 | 우선순위 |
|---|----------|----------|---------|
| 1 | reconcile-state.sh가 STATE 클래스(v2/hybrid/v3) 정확 판정 + 파서 무오작동 | 3 fixture(v2/hybrid/v3)로 `--jsonl` 출력의 `state_class` 확인 + marker 내부 `⬜`를 prose로 오인 안 함 | Critical |
| 2 | Nova 자기 레포 dogfooding — `goal` frontmatter 불일치(v5.41.0↔실제) + 12개 proposed WI를 드리프트로 탐지 | `bash scripts/reconcile-state.sh` → ⚠️/❓에 12 WI + goal 불일치 포함. **Recent Activity 표는 탐지 대상 아님(오탐 시 FAIL)** | Critical |
| 3 | 원래 버그 재현 차단 — git이 완료를 보이는 작업을 `/nova:next`가 추천 안 함 | fixture STATE에 "진행 중" prose + 일치 done 커밋 → `/nova:next` 출력에 해당 항목 제외/⚠️ 플래그 | Critical |
| 4 | ❓추적불가가 ✅완료검증과 합산되지 않음 | `reconcile-state.sh` 출력에서 3분류 카운트 독립 + ❓는 별도 경고 블록 | Critical |
| 5 | pre-commit nudge가 drift 0건일 때 침묵 | drift 없는 fixture에서 `pre-commit-reminder.sh` stdin 주입 → drift nudge 미출력 | Critical |
| 6 | pre-commit nudge가 ⚠️/❓ ≥1건일 때만, 기존 경고와 단일 블록으로 발화 | drift 있는 fixture → 단일 통합 블록 1개 | Critical |
| 7 | `/nova:checkpoint` 커맨드 등록 — session-start 목록 + EXPECTED_COMMANDS | `bash tests/test-scripts.sh` 자동 검증 | Critical |
| 8 | 계약 동기화 — nova-rules.md §8 ↔ session-start.sh | `bash hooks/session-start.sh \| python3 -m json.tool` + 동기화 테스트 | Critical |
| 9 | 사용자 가이드 존재 + 핵심 키워드 | `tests/test-scripts.sh` 가이드 회귀 가드 | Critical |
| 10 | reconcile-state.sh가 read-only — 어떤 파일도 쓰지 않음 | reconcile 실행 전후 `git status` + STATE/registry mtime 불변 확인 | Critical |
| 11 | 전체 회귀 — 기존 테스트 무손상 | `bash tests/test-scripts.sh` 전체 PASS | Critical |
| 12 | fuzzy 매칭 false positive 정량 통제 | Nova git log 최근 30커밋 대상 reconcile → **⚠️ 오탐 ≤ 2건**, 측정값을 가이드에 기록 | Critical |
| 13 | Layer 5 Warn 효과 측정 (출시 후) | 출시 N주 후 `goal`/prose-status Warn 발생 후 실제 수정율 측정 → 미달 시 위생 게이트 승격 안건화 | Nice-to-have |
| 14 | reconcile-state.sh `-h`/`--help`로 가이드 경로 안내 | `bash scripts/reconcile-state.sh -h \| grep guides/` | Nice-to-have |
