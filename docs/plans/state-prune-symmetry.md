# [Plan] NOVA-STATE.md 단조 증가 갭 — 갱신/정리 구조적 비대칭 해소

> Nova Engineering — CPS Framework
> 작성일: 2026-04-28
> 작성자: jay-swk
> Design: (작성 예정)

---

## Context (배경)

### 현재 상태

- `docs/nova-rules.md §8`에 "NOVA-STATE.md는 50줄 이내" 규칙이 명시되어 있다.
- `skills/context-chain/SKILL.md`에 "Recently Done 3개 초과 시 제거", "Last Activity 1줄", "50줄 초과 시 정리" 규칙이 명시되어 있다.
- 6개 커맨드(`plan.md`, `design.md`, `check.md`, `review.md`, `ux-audit.md`, `run.md`)는 "CRITICAL: NOVA-STATE.md 갱신 (이 단계를 건너뛰지 마라)"를 강제한다.

### 왜 필요한가

실측 (2026-04-28) — 두 곳에서 동일 패턴 관찰:

| 프로젝트 | NOVA-STATE.md 라인 수 | 룰 대비 |
|----------|----------------------|---------|
| swk-ground-control | 1880줄 | 37.6× |
| nova (자기 자신) | 181줄 | 3.6× |

Nova 본 레포조차 자기 룰을 못 지킨다 — 사용자 책임이 아닌 **플러그인 구조 갭**의 직접 증거다.

### 관련 자료

- `docs/nova-rules.md §8`
- `skills/context-chain/SKILL.md` (50줄, Recently Done 3개, Last Activity 1줄)
- `swk-ground-control/NOVA-STATE.md` 1880줄 — 갭의 실증
- 본 레포 `NOVA-STATE.md` 181줄 — 자가 갭의 직접 증거

---

## Problem (문제 정의)

### 핵심 문제

**갱신은 6개 커맨드에서 강제 / 정리는 0개에서 강제** — 단조 증가가 구조적으로 보장된 비대칭이 모든 Nova 사용자의 NOVA-STATE.md를 무한히 키운다.

### MECE 분해

| # | 문제 영역 | 설명 | 영향도 |
|---|----------|------|--------|
| 1 | 글로벌 룰 노출 누락 | `hooks/session-start.sh` additionalContext (strict/standard/lean 3개 모드)에 STATE 사이즈 룰이 없음 → 매 세션 클로드가 50줄/3개/1줄 룰을 인지조차 못 한 채 작업 시작 | 높음 |
| 2 | 갱신 트리거에 정리 트리거 부재 | 6개 커맨드에 "갱신 강제" 명령은 있고 "갱신 직후 길이 체크 + 트림" 명령은 없음 → 갱신할수록 누적 | 높음 |
| 3 | 회귀 가드 부재 | `tests/test-scripts.sh:242`는 빈 템플릿(`docs/templates/nova-state.md`)만 50줄 검증. 실제 사용자 NOVA-STATE.md/갱신-정리 트리거 카운트 비대칭을 검증하는 테스트 없음 | 중간 |
| 4 | 본 레포 자가 위반 | nova 레포 NOVA-STATE.md 181줄로 자기 룰 위반 → "Nova도 안 지키는 룰을 사용자에게 강제"하는 신뢰성 갭 | 중간 |

### 제약 조건

- **하위 호환**: 기존 NOVA-STATE.md를 자동 트림하면 사용자 데이터 유실 위험 → 트림은 클로드가 룰을 인지하고 판단하는 방식이지, hook이 자동으로 행을 지우지 않는다.
- **session-start.sh 예산**: `docs/nova-rules.md` soft 1200자 / hard 2500자 한도 준수 필수. 이 작업으로 한도 초과 금지.
- **수정은 텍스트 추가만**: 실제 코드 동작 변경 없음. 모두 LLM에게 룰을 주입/지시하는 텍스트 수정.
- **즉시 반영**: 플러그인 업데이트만으로 사용자에게 자동 전달. 수동 설치 작업 요구 금지 (메모리: 수동 설정 금지 원칙).

---

## Solution (해결 방안)

### 선택한 방안

**3축 동시 보강** — 룰 인지 + 갱신/정리 트리거 동기화 + 회귀 가드:

1. **session-start.sh additionalContext**에 STATE 사이즈 룰 1줄 추가 (3개 모드 모두). "5. NOVA-STATE.md 읽기" → "5. NOVA-STATE.md 읽기 + 50줄/Recently Done 3개/Last Activity 1줄 유지"로 확장.
2. **6개 갱신 트리거 커맨드**에 "갱신 직후 길이 점검 + 초과 시 오래된 항목 트림" 1줄 추가. 기존 "CRITICAL: 갱신" 블록에 정리 단계 명시.
3. **tests/test-scripts.sh** 회귀 가드 추가:
   - 갱신 트리거 6개 커맨드에 정리 지시문도 모두 존재하는지 검증 (비대칭 회귀 방지)
   - session-start.sh 3개 모드에 STATE 사이즈 룰 키워드 존재 검증
4. **자가 적용** — 본 레포 NOVA-STATE.md 트림 (181 → ≤50줄). 새 룰을 본인부터 준수하여 신뢰 회복.

### 대안 비교

| 기준 | 방안 A (3축 동시 보강) | 방안 B (트림 자동화 hook) | 방안 C (룰만 강화, 트리거 무수정) |
|------|-----------------------|--------------------------|----------------------------------|
| 효과 | 룰 인지 + 트리거 + 가드 동시 닫음 | 사용자 데이터 자동 손실 위험 | 갱신 강제만 남고 정리 의지는 여전히 약함 |
| 위험 | 텍스트 추가만 (낮음) | 자동 sed/awk 트림 시 의도 해석 실패 위험 (높음) | 효과 약함 (재발 가능) |
| 구현 비용 | 9파일 텍스트 수정 + 테스트 2개 | hook 신규 + 안전 가드 + 복원 메커니즘 (큼) | 1~2파일 |
| 선택 | **채택** | 기각 (자동 행 삭제는 데이터 무결성 침해 — context-chain SKILL이 사람 판단을 명시) | 기각 (실측 결과가 룰만으로는 부족함을 증명) |

### 구현 범위

**Sprint 1 — 사용자 가시 트리거 동기화 (룰 인지 + 갱신/정리 비대칭 해소)**

수정 파일 (7):

- [ ] `hooks/session-start.sh` — strict/standard/lean 3개 additionalContext의 "Always-On" 또는 NOVA-STATE 항목에 사이즈 룰 1줄 추가. 각 모드 합쳐 +60자 이내 (예산 준수).
- [ ] `commands/plan.md` — `# CRITICAL: NOVA-STATE.md 갱신` 블록 끝에 "갱신 후 50줄 초과 시 가장 오래된 Last Activity / Recently Done부터 정리. 정리 없이 종료 금지" 1줄 추가.
- [ ] `commands/design.md` — 동일 패턴.
- [ ] `commands/check.md` — 동일 패턴.
- [ ] `commands/review.md` — 동일 패턴 (review.md는 갱신 지시가 2회 등장 — 둘 다 처리).
- [ ] `commands/ux-audit.md` — 동일 패턴.
- [ ] `commands/run.md` — `run.md:226` "검증 결과 자동 반영" 직후 동일 패턴.

**Sprint 2 — 회귀 가드 + 자가 적용 + 룰 일관성**

수정 파일 (3):

- [ ] `tests/test-scripts.sh` — assert 2개 추가:
  - `assert "6 갱신 트리거 커맨드에 정리 지시문 존재"` — `commands/{plan,design,check,review,ux-audit,run}.md` 각각 grep "정리|트림|50줄|초과" 1+ 매치.
  - `assert "session-start.sh 3 모드 STATE 사이즈 룰 노출"` — `bash hooks/session-start.sh` 출력에 strict/standard/lean 모드별 "50줄" 또는 "사이즈" 키워드 매치.
- [ ] `skills/context-chain/SKILL.md` — 기존 "아카이빙 규칙" 섹션 유지. 갱신 트리거 표 우측에 "정리 의무" 컬럼 추가하여 6개 커맨드에서 정리도 강제임을 명시.
- [ ] `NOVA-STATE.md` (본 레포) — 트림 → 50줄 이내. 잔존은 Current/최근 3 Last Activity/Recently Done 3건/Known Risks/Refs 핵심만.

### 검증 기준

1. **자동 회귀**:
   - `bash tests/test-scripts.sh` 신규 assert 2개 포함 PASS.
   - `bash hooks/session-start.sh | python3 -m json.tool` JSON 유효성 PASS.
2. **사이즈 예산**:
   - session-start.sh strict/standard/lean 출력 모두 hard 2500자 이내, 가능하면 soft 1200자 근접.
3. **자가 적용**:
   - 본 레포 `NOVA-STATE.md` ≤ 50줄.
4. **트리거 비대칭 해소**:
   - 갱신 트리거 6개 커맨드 모두에서 grep "정리|트림|50줄|초과" 1+ 매치.
5. **사용자 검증**:
   - 다음 신규 세션에서 `/nova:check` 또는 `/nova:review` 호출 시 클로드가 "갱신 + 정리"를 함께 수행하는지 실측 (수동 1회).

---

## Sprints (스프린트 분할)

| Sprint | 기능 단위 | 예상 파일 | 의존성 | Done 조건 |
|--------|----------|----------|--------|-----------|
| 1 | 사용자 가시 트리거 동기화 | `hooks/session-start.sh` + `commands/{plan,design,check,review,ux-audit,run}.md` (7개) | 없음 | (a) 6 커맨드 모두에 정리 지시문 grep 매치 (b) session-start 3 모드에 사이즈 룰 키워드 매치 (c) JSON 유효성 PASS (d) hard 2500자 이내 |
| 2 | 회귀 가드 + 자가 적용 + 룰 일관성 | `tests/test-scripts.sh` + `skills/context-chain/SKILL.md` + `NOVA-STATE.md` (3개) | Sprint 1 | (a) 신규 assert 2개 포함 `bash tests/test-scripts.sh` PASS (b) 본 레포 NOVA-STATE.md ≤ 50줄 (c) Sprint 1에서 추가한 정리 지시문이 자가 적용 통해 실제 동작함을 본 레포에서 시연 |

각 스프린트는 독립 검증 가능. Sprint 2는 Sprint 1의 텍스트 추가가 끝나야 회귀 가드를 의미 있게 작성 가능 (의존성 분명).

---

## Notes

- 본 작업은 Nova 자체가 자기 룰을 못 지킨 사례 — Sprint 2의 본 레포 트림은 실증/시연 의미. "Plugin이 자기 룰을 따른다"는 신뢰 신호.
- `/nova:design`은 이번 Plan에 대해 생략 가능: 모든 변경이 텍스트 1~2줄 추가로 구조 결정 단계 없음. 다만 release.sh 워크플로우 자동화 갭(Known Risks #100)과 통합할 여지가 있으면 Design에서 결정.
- v5.19.5 → v5.19.6 patch 또는 minor 후보. 기능 추가가 아닌 룰 시정이므로 patch가 적절.
