# X-Verification: [Nova Engineering 핵심 설계 결정 자문 — 평가 기준: 독창성·안정성·일관성·확장성]

## 컨텍스트

Nova는 Claude C

> 날짜: 2026-05-15
> 합의율: 100%
> 판정: auto_approve
> AI: claude, gpt, gemini

## 질문
[Nova Engineering 핵심 설계 결정 자문 — 평가 기준: 독창성·안정성·일관성·확장성]

## 컨텍스트

Nova는 Claude Code 플러그인 (AI Agent Ops 프레임워크). 사용자 프로젝트에 배포되는 시스템. 작업 추적 v3 도입 결정 중.

**Nova의 독창성 (선례 없음)**: 사람용 cursor(NOVA-STATE.md) + 기계용 진실원(.nova/work-items.json) 명시 분리 + Generator-Evaluator 품질 게이트가 work-item lifecycle을 검증 (Evaluator PASS = `done` 전이 조건). 9개 진입점이 registry만 갱신, NOVA-STATE.md는 자동 투영.

**OSS 선례 조사 완료**: dbt(단방향 reconcile), adr-tools/spec-kit(`NNNN-slug` 4자리 순차 id), MADR(status enum), Backstage(managed-by-location annotation), BMad(flat directory 200+에서 무너진 사례), Cline Memory Bank(schema 없이도 동작), DORA(`commit_sha` evidence 표준).

**제약**: 한 번 결정 후 자주 못 바꿈. 9개 형제 사용자 프로젝트(plan 1~51개 범위)에 마이그레이션. 다양한 언어 스택·복잡도.

## 결정 Q1: status enum 설계 — 2축 분리 vs 단일축?

**옵션 A (2축 분리)**:
```yaml
lifecycle: proposed | accepted | superseded | withdrawn   # 의도/계약
progress: backlog | active | blocked | review | done      # 실행 상태
```
- 근거: MADR(lifecycle) + BMad(progress) 의미 충돌 회피
- 비용: 사용자 인지 부담 2배, 9 진입점 전이 로직 복잡

**옵션 B (단일축 8값)**:
```yaml
status: proposed | triage | active | blocked | review | done | superseded | archived
```
- 근거: Cline/Aider처럼 단순. 학습 곡선 낮음.
- 비용: "active이면서 review 대기"·"superseded인데 done이었던 것" 같은 의미 모호.

**옵션 C (1.5축 — status + 보조 플래그)**:
```yaml
status: proposed | active | blocked | done | superseded   # 5값
review_required: bool                                       # 보조
archived_at: timestamp?                                     # 보조
```
- 단일축 단순함 + 의미 충돌 회피.

Nova의 독창성(Evaluator PASS = done 전이)과 안정성·9 진입점 일관성 관점에서 어느 쪽이 가장 흔들림 없이 굴러가는가? 단호한 권고 부탁.

## 결정 Q2: `.nova/work-items.json` 저장 형식 — 단일 vs 분할 vs 하이브리드?

**옵션 A (단일 파일)**:
- `.nova/work-items.json` 하나에 배열로 저장
- 장점: `jq` 한 줄 쿼리, 단일 파일 schema 검증, atomic write
- 단점: BMad가 200+ items에서 무너진 사례. git diff 노이즈.

**옵션 B (분할)**:
- `.nova/work-items/WI-0001-slug.json` 파일별 저장 + `.nova/work-items/index.json`
- 장점: 확장성, git diff 깔끔, 동시 편집 충돌 줄어듦
- 단점: 초기 복잡도, jq 쿼리 어려움, schema 검증 N번

**옵션 C (하이브리드 — 임계값 자동 분할)**:
- 100개 이하: 단일 파일
- 초과: 자동 분할 + index.json 마이그레이션
- 장점: 작은 프로젝트는 단순, 큰 프로젝트도 견딤
- 단점: "임계값 마법" 복잡도, 마이그레이션 시점 변동

플러그인 사용자의 다양한 프로젝트 규모(10개~수백개)에서 가장 안정적·예측 가능한 시작점은? 한 번 결정하면 마이그레이션 비용 큼.

## 응답 형식

각 질문에 (1) 권고 옵션 + (2) 핵심 근거 3줄 + (3) 가장 큰 위험 + (4) 대안이 더 나아질 조건. 종합 5줄로 Nova가 가야 할 방향. 우유부단한 "각자 장단점이..." 식 답변 금지.

## claude
## Q1: Status Enum → **옵션 C (1.5축) 권고**

**(1) 권고**: `status` 5값 + `review_required: bool` + `archived_at: timestamp?`

**(2) 핵심 근거**
- Evaluator PASS → `done` 전이는 **단일 조건**이어야 9개 진입점이 일관된 게이트를 구현할 수 있음. 2축이면 "lifecycle=accepted + progress=done" 조합 검증이 매 진입점마다 중복 발생.
- `review_required`는 Generator-Evaluator 사이클의 **대기 신호**로 의미가 명확하며, status 축을 오염시키지 않음.
- `archived_at` timestamp는 DORA의 `commit_sha` evidence 패턴과 일관: 상태가 아닌 **사건 기록**으로 분리.

**(3) 가장 큰 위험**: `review_required=true` + `status=done` 조합이 발생할 때 진입점이 이를 묵살하거나 충돌 처리 로직이 분기될 수 있음 → **Evaluator PASS 시 `review_required`를 false로 강제 리셋하는 원자적 전이 규칙을 spec에 명문화**해야 함.

**(4) 옵션 A가 나아질 조건**: work-item이 "계약 단위"(ADR처럼 되돌릴 수 없는 의사결정)로 쓰이는 비중이 압도적일 때. Nova는 실행 추적이 주목적이므로 해당 없음.

---

## Q2: 저장 형식 → **옵션 B (분할) 권고**

**(1) 권고**: `.nova/work-items/WI-NNNN-slug.json` + `index.json`

**(2) 핵심 근거**
- **한 번 결정하면 못 바꾼다**는 제약 하에 옵션 C의 "임계값 마법"은 마이그레이션이 **자동으로 터지는 시한폭탄**. BMad 실패 원인이 바로 단일 파일 스케일 초과였음.
- `adr-tools`의 `NNNN-slug` 파일명은 git log에서 변경 맥락이 즉시 식별됨 → 9개 프로젝트에서 Evaluator 이력 추적 비용 최소화.
- `index.json`이 단일 파일 schema 검증 역할을 대체: id, status, review_required만 담는 **경량 매니페스트**로 `jq` 쿼리 허브를 유지.

**(3) 가장 큰 위험**: index.json과 개별 파일 간 **동기화 드리프트** (index 갱신 없이 개별 파일만 수정). → 9개 진입점 모두 index.json을 **단일 쓰기 경로(registry)**로만 업데이트하고, 개별 파일 직접 편집을 금지하는 접근 제어를 플러그인 레벨에서 강제해야 함.

**(4) 옵션 A가 나아질 조건**: 최대 work-item 수가 50개로 하드캡되고, 동시 편집 가능성이 없으며, CI jq 파이프라인이 핵심 인

## gpt
**Q1 권고: 옵션 C (1.5축)**  
- `done`을 Evaluator PASS와 1:1로 고정하기 가장 쉽고, 9개 진입점 전이 규칙도 단순합니다.  
- 2축은 의미론적으로 아름답지만 사용자·구현 복잡도가 큽니다. 단일 8값은 상태 의미가 섞여 장기적으로 흔들립니다.  
- `review_required`로 품질 게이트를 분리하면 Nova의 독창성(계약/실행/검증 분리)을 최소 복잡도로 보존합니다.  
- **가장 큰 위험:** `status`에 lifecycle 의미를 과적재하면 superseded/done 이력 해석이 흐려짐.  
- **대안 우세 조건:** ADR급 의사결정 추적이 핵심 제품 가치가 되면 그때만 2축.

**Q2 권고: 옵션 B (분할)**  
- 한 번 정하면 오래 가야 하므로, 소규모 최적화보다 대규모 안정성을 먼저 선택해야 합니다.  
- 파일별 저장은 diff/충돌/부분 수정/확장성에서 가장 예측 가능하며, 사용자 프로젝트 편차를 가장 잘 흡수합니다.  
- `index.json`만 표준 진입점으로 두면 자동 투영·registry 중심 구조와도 일관됩니다.  
- **가장 큰 위험:** 조회/검증 도구 체인이 초기에 더 복잡해짐.  
- **대안 우세 조건:** 대부분 프로젝트가 항상 50개 이하이고 외부 jq 직접 활용성이 핵심이면 단일 파일.

**종합 방향**  
Nova는 **“상태는 단순, 저장은 확장형”**으로 가야 합니다: **Q1=C, Q2=B**.  
즉, 전이 규칙은 최소화하고, 데이터 구조는 처음부터 대형 프로젝트를 견디게 설계하세요.

## gemini
## Q1: status enum — **옵션 C (1.5축)** 권고
- **근거**: 1. Evaluator PASS를 `review_required` 플래그와 직결해 자동화 게이트 로직을 단순화함. 2. 9개 진입점이 다뤄야 할 핵심 상태를 5개로 압축해 전이 일관성 확보. 3. `NOVA-STATE.md` 투영 시 인간이 이해하기 가장 직관적인 구조임.
- **위험**: 주 상태와 보조 플래그 간 논리적 모순(예: done인데 review_required: true) 발생 가능.
- **대안**: 에이전트의 판단력이 인간 수준으로 정교해지면 옵션 A(2축)로 확장.

## Q2: 저장 형식 — **옵션 B (분할)** 권고
- **근거**: 1. 다수 에이전트/협업자의 동시 수정 시 Git 충돌을 원천 방지함. 2. BMad 사례처럼 작업 증가 시 단일 파일이 거대해져 파싱 성능이 저하되는 리스크 차단. 3. `index.json`을 통해 옵션 A의 장점인 빠른 쿼리 성능을 보존함.
- **위험**: 파일 시스템 I/O 증가 및 파일 유실/고아 파일 관리 복잡도.
- **대안**: 모든 프로젝트 규모가 20개 미만으로 강제된다면 옵션 A가 효율적임.

**[종합 방향]** Nova는 '확장 가능한 AI Ops'를 지향하므로, **유연한 상태 플래그(1.5축)와 원자적 저장소(분할)** 조합이 안정성과 확장성을 동시에 잡는 유일한 길입니다.

## 합의 분석
- **합의율**: 100%
- **판정**: auto_approve
- **요약**: 모든 AI가 상태 관리는 1.5축(C), 저장 형식은 분할 방식(B)을 만장일치로 권고하며, 이는 Nova의 확장성과 자동화 게이트 구현에 가장 부합하는 선택임.

### 공통점
- Q1에서 1.5축(Option C)이 Evaluator PASS와 done 상태 전이 로직을 가장 단순하고 일관되게 유지할 수 있음
- Q2에서 분할 저장(Option B)이 BMad 사례와 같은 대규모 프로젝트의 확장성 한계를 극복하고 Git 충돌을 방지하는 최선책임
- index.json(매니페스트)을 도입함으로써 분할 저장 환경에서도 단일 파일의 장점인 빠른 쿼리 성능을 보존할 수 있음

### 차이점
- Claude는 상태 모순 방지를 위해 Evaluator PASS 시 플래그를 강제 리셋하는 원자적 전이 규칙의 명문화를 강조함
- GPT는 초기 도구 체인 복잡도보다 장기적인 대규모 안정성이라는 설계 원칙에 더 무게를 둠
- Gemini는 파일 시스템 I/O 증가 및 고아 파일 관리와 같은 운영 리스크를 추가로 지적함
