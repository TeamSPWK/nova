# X-Verification: AXIS Kit /auto 커맨드의 Pause & Resume 메커니즘 설계. /auto는 자율 실행 중 블로커(API 키 필요, 외부 서비스 

> 날짜: 2026-03-28
> 합의율: 95%
> 판정: auto_approve
> AI: claude gpt gemini

## 질문
AXIS Kit /auto 커맨드의 Pause & Resume 메커니즘 설계. /auto는 자율 실행 중 블로커(API 키 필요, 외부 서비스 설정, DB 마이그레이션, 패키지 설치 등)를 만나면 적절히 처리해야 한다. 질문: 1) 블로커를 몇 단계로 분류하는 게 적절한가? Claude는 3단계(Auto-Resolve/Soft-Block/Hard-Block)를 제안했는데, 각 단계의 구체적 기준과 예시는? 2) Soft-Block(placeholder+TODO 처리 후 계속)이 실제로 안전한가? 나중에 TODO를 잊을 리스크는? 3) Hard-Block으로 중단할 때 상태 보존은 어떻게 구현하는가? /auto resume 같은 재개 메커니즘이 현실적으로 가능한가? Claude Code의 대화 컨텍스트 한계를 고려하면? 4) 실행 전에 필요한 환경(API 키, 패키지 등)을 사전 점검하는 preflight check가 더 효과적이지 않은가?

## claude
# AXIS Kit /auto 커맨드 Pause & Resume 설계 분석

## 1. 블로커 분류: 3단계가 적절한가?

**결론: 3단계가 실용적 최적점, 단 기준이 명확해야 함**

```
Auto-Resolve  → AI가 독립적으로 해결 가능
Soft-Block    → 진행은 가능, 단 품질/안전 타협 수반
Hard-Block    → 진행 불가, 인간 개입 필수
```

**구체적 분류 기준:**

| 단계 | 핵심 기준 | 예시 |
|------|-----------|------|
| **Auto-Resolve** | 외부 상태 변경 없음 + 되돌리기 가능 | 패키지 설치, mock 데이터 생성, 환경변수 템플릿 생성 |
| **Soft-Block** | 진행 가능하나 **런타임 실패 가능** | API 키 미설정(placeholder), 선택적 서비스 미연결 |
| **Hard-Block** | **데이터 손실/보안/돌이킬 수 없는 변경** | DB 마이그레이션, 프로덕션 배포, 결제 API 연동 |

**⚠️ 경계 모호 케이스 처리 원칙:**
```
불확실하면 Hard-Block으로 상향. 
"안전한 방향으로 보수적 판단"을 명시적 규칙화
```

---

## 2. Soft-Block의 안전성: TODO 망각 리스크

**결론: Soft-Block은 위험하다. 구조적 강제장치 없으면 사실상 기술부채 자동생성기**

### 문제의 본질
```python
# Soft-Block이 생성하는 것
API_KEY = "TODO: Set your API key here"  # 이게 프로덕션에 올라간다
```

### 리스크 레벨별 분류
```
낮음: 빌드타임에 실패하는 TODO (컴파일 에러 등)
중간: 런타임에 실패하는 TODO (앱 시작 시 검증)  
높음: 특정 경로에서만 실패 (결제 플로우 진입 시)  ← 실제 위험
```

### 안전한 Soft-Block 설계 조건 (이 중 하나라도 없으면 사용 금지)

```typescript
// 조건 1: 실패가 즉시 명시적이어야 함
const apiKey = process.env.API_KEY;
if (!apiKey) throw new Error('[AXIS-BLOCK] API_KEY required. See .env.example');

// 조건 2: TODO 레지스트리에 기록 (파일로 추적)
// .axis/pending-blocks.json 에 자동 추가

// 조건 3: /auto 완료 후 summary에 반드시 노출
// "⚠️ 3 Soft-Blocks require manual resolution before production"
```

### 실용적 판단
```
Soft-Block 허용 기준:
✅ 개발/테스트 환경 전용 코드
✅ 즉시 실패하는 validation 포함
✅ .axis/blocks.json 추적 + 최종 리포트 필수

❌ 프로덕션 경로
❌ 조용히 실패하는 케이스 (fallback으로 숨

## gpt
권장: **3단계면 충분**합니다.

1) **분류 기준**
- **Auto-Resolve**: 결정이 명확·가역적·로컬 처리 가능. 예) 패키지 설치, 코드 포맷, 안전한 기본 설정 생성.
- **Soft-Block**: 진행 가능하지만 품질/완성도 저하를 명시해야 함. 예) API 키 없어 mock/placeholder 주입, 외부 서비스 미연결로 adapter stub 생성, 마이그레이션 파일만 생성하고 적용 보류.
- **Hard-Block**: 사용자 결정/비밀값/파괴적 작업 필요. 예) 실제 API 키 입력, 프로덕션 DB 마이그레이션 실행, 과금/권한 필요한 외부 서비스 활성화.

2) **Soft-Block 안전성**
조건부로만 안전합니다. 반드시:
- TODO를 코드 주석이 아니라 **머신리더블 블로커 레지스트리**로 저장
- CI에서 unresolved blocker 있으면 실패
- 실행 결과 요약에 남은 TODO 강제 출력
주석만 남기면 잊힐 확률 높습니다.

3) **Pause/Resume**
가능하지만 **대화 컨텍스트 의존 금지**.
- `.axis/session.json`: 목표, 계획, 완료 단계, 남은 blocker, 생성 파일, 다음 액션 저장
- 재개 시 세션 파일+repo 상태를 다시 읽어 계획 재구성
- `/auto resume`는 “이어쓰기”보다 **상태복원 후 재계획** 방식이 현실적

4) **Preflight**
매우 효과적이며 필수입니다. 다만 완전 대체는 불가.
- 시작 전: API 키, CLI, 패키지 매니저, DB 연결, 권한 점검
- 실행 중: 새로 드러난 blocker는 위 3단계로 처리
즉, **preflight + runtime blocker handling** 조합이 최선입니다.

## gemini
아키텍처 전문가로서 답변드립니다.

1. **블로커 분류**: 3단계가 효율적입니다. ①**Auto**: 즉시 수정 가능(패키지 설치, 경로 보정). ②**Soft**: 비핵심 로직 누락(Mocking/TODO 삽입). ③**Hard**: 실행 불능(API Key 미설정, DB 스키마 충돌).
2. **Soft-Block 안전성**: 위험합니다. 이를 보완하려면 `Task Ledger`에 기록을 남기고, 최종 완료 전 'Pending TODO' 검수 단계를 강제해야 합니다. 자동화된 CI/CD 파이프라인과 연동하여 잔류 TODO 발생 시 빌드를 실패하게 만들어야 합니다.
3. **상태 보존 및 재개**: `checkpoint.json`에 현재 Plan, 수정 로그, 핵심 컨텍스트 요약을 저장하십시오. 재개 시 이전 대화 전체가 아닌 '압축된 요약본'을 주입하면 Claude의 컨텍스트 한계를 극복하며 현실적으로 구현 가능합니다.
4. **Preflight Check**: 정적 환경(환경변수, 의존성)은 사전 점검이 압도적으로 효율적입니다. 하지만 실행 중 발생하는 동적 에러는 제어가 불가능하므로, **사전 점검과 일시중지 메커니즘을 병행하는 하이브리드 설계**가 필수입니다.


## 합의 분석
- **합의율**: 95%
- **판정**: auto_approve
- **요약**: 모든 AI가 3단계 분류, 파일 기반 상태 관리, 하이브리드 체크 방식에 대해 일치된 견해를 보이므로 해당 설계를 즉시 채택 가능함

### 공통점
- 블로커를 3단계(Auto/Soft/Hard)로 분류하는 것이 가장 실용적이고 효율적임
- Soft-Block은 위험하므로 단순 주석이 아닌 머신 리더블한 레지스트리(JSON 등)에 기록하고 최종 검수를 강제해야 함
- 대화 컨텍스트 한계를 극복하기 위해 로컬 파일(.axis/session.json 등)에 상태와 계획을 저장하는 Resume 메커니즘이 필수적임
- Preflight Check는 효율적이지만 만능은 아니므로 런타임 블로커 처리와 병행하는 하이브리드 구조를 채택해야 함

### 차이점
- 상태 보존 시 저장할 데이터의 상세 항목(수정 로그, 압축된 요약본, 재계획 로직 등)에 대한 강조점 차이
- Soft-Block의 안전 장치로 CI/CD 연동을 강조(Gemini)하거나 런타임 에러 강제 발생(Claude)을 제안하는 등 구체적 구현 방법의 차이
