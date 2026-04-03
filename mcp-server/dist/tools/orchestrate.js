import { z } from "zod";
function buildOrchestrationGuide(task, complexity) {
    const guides = {
        simple: `# 오케스트레이션 가이드: 간단 작업

## 태스크
${task}

## 판정: 단일 에이전트 (직접 실행)

**기준**: 버그 수정, 1~2 파일 수정, 명확한 변경

### 실행 절차
1. 구현 (Generator)
2. 독립 검증 (Evaluator 서브에이전트)
3. 검증 PASS → 커밋

### Evaluator 프롬프트 템플릿
\`\`\`
당신은 코드 검증 전문가입니다. 적대적 자세로 다음을 검토하세요:

태스크: ${task}

검증 항목:
- [ ] 기능이 요구사항대로 동작하는가?
- [ ] 엣지 케이스(빈 값, 0, 음수, 빈 배열)에서 크래시하지 않는가?
- [ ] 기존 동작이 손상되지 않았는가?
- [ ] 불필요한 변경이 포함되지 않았는가?

PASS / FAIL 판정과 이유를 명시하세요.
\`\`\`
`,
        medium: `# 오케스트레이션 가이드: 보통 작업

## 태스크
${task}

## 판정: Generator + Evaluator 분리

**기준**: 3~7 파일 수정, 새 기능 추가

### 에이전트 편성
| 역할 | 담당 | 실행 방식 |
|------|------|----------|
| **Orchestrator** | 계획 수립, 최종 판단 | 메인 |
| **Generator** | 구현 | 서브에이전트 |
| **Evaluator** | 독립 검증 | 서브에이전트 (Generator와 독립) |

### 실행 절차
1. Orchestrator: Plan 작성 + 승인
2. Generator 서브에이전트: 구현
3. Evaluator 서브에이전트: 독립 검증 (Generator 컨텍스트 미공유)
4. Evaluator PASS → Orchestrator 최종 확인 → 커밋

### Generator 프롬프트 템플릿
\`\`\`
당신은 구현 전문가입니다.

태스크: ${task}

다음 순서로 진행하세요:
1. 영향 파일 목록 확인
2. 최소 변경 원칙으로 구현
3. tsc/lint 통과 확인
4. 구현 완료 보고 (변경 파일 목록 + 변경 사유 포함)
\`\`\`

### Evaluator 프롬프트 템플릿
\`\`\`
당신은 코드 검증 전문가입니다. 적대적 자세로 검토하세요.
Generator의 구현 의도를 알고 있더라도 독립적으로 판단하세요.

태스크: ${task}

검증 항목:
- [ ] 기능 요구사항 충족
- [ ] 엣지 케이스 안전성
- [ ] 기존 기능 회귀 없음
- [ ] 불필요한 추상화/코드 없음
- [ ] 에러 핸들링 적절성
- [ ] 테스트 용이성

PASS / NEEDS WORK / FAIL 판정 + 근거 + 수정 제안
\`\`\`
`,
        complex: `# 오케스트레이션 가이드: 복잡 작업

## 태스크
${task}

## 판정: 스프린트 분할 + 전문 에이전트 팀

**기준**: 8+ 파일, 다중 모듈, 외부 의존성, 고위험 영역

### 에이전트 팀 편성
| 역할 | 담당 | 실행 방식 |
|------|------|----------|
| **Orchestrator** | 스프린트 관리, 게이트 통과 결정 | 메인 |
| **Architect** | 설계 검토 및 트레이드오프 분석 | 서브에이전트 |
| **Generator** | 스프린트별 구현 | 서브에이전트 |
| **Evaluator** | 각 스프린트 독립 검증 | 서브에이전트 |
| **Integrator** | 전체 통합 + 회귀 테스트 | 서브에이전트 |

### 실행 절차
\`\`\`
Phase 1: 설계
  Orchestrator → Architect: Design 문서 작성 요청
  Architect → Orchestrator: 트레이드오프 포함 설계 제출
  Orchestrator: 설계 승인

Phase 2: 스프린트 실행 (반복)
  Orchestrator: 스프린트 N 범위 정의
  Generator: 구현
  Evaluator: 독립 검증
  [PASS] → 다음 스프린트
  [FAIL] → Generator 재구현 → 재검증

Phase 3: 통합
  Integrator: 전체 통합 + 회귀 테스트
  Evaluator: 최종 독립 검증
  Orchestrator: 커밋 게이트 통과 확인
\`\`\`

### 스프린트 계약 (사전 정의 필수)
각 스프린트 시작 전 다음을 명시:
- 완료 조건 (Definition of Done)
- 스코프 (수정 파일 목록)
- 게이트 기준 (통과/실패 판정 방식)

### 고위험 영역 추가 게이트
인증/DB/결제가 포함된 경우:
- [ ] 보안 검토 (Evaluator 별도 실행)
- [ ] 롤백 계획 수립
- [ ] 프로덕션 반영 전 사용자 최종 확인

### Architect 프롬프트 템플릿
\`\`\`
당신은 소프트웨어 아키텍트입니다.

태스크: ${task}

다음을 포함한 Design 문서를 작성하세요:
1. 컴포넌트 분해 (MECE)
2. 인터페이스 정의
3. 데이터 흐름
4. 트레이드오프 (선택한 설계 vs 대안)
5. 리스크와 완화 전략
6. 스프린트 분할 제안 (각 스프린트 완료 조건 포함)
\`\`\`
`,
    };
    return guides[complexity];
}
export function registerOrchestrate(server) {
    server.registerTool("orchestrate", {
        title: "오케스트레이션 가이드 반환",
        description: "태스크와 복잡도에 따른 에이전트 편성 가이드와 프롬프트 템플릿을 반환합니다.",
        inputSchema: z.object({
            task: z.string().describe("수행할 태스크 설명"),
            complexity: z
                .enum(["simple", "medium", "complex"])
                .optional()
                .describe("복잡도: simple(1~2파일), medium(3~7파일), complex(8+파일/외부의존성). 미지정 시 medium"),
        }),
    }, async ({ task, complexity }) => {
        const level = complexity ?? "medium";
        const guide = buildOrchestrationGuide(task, level);
        return {
            content: [{ type: "text", text: guide }],
        };
    });
}
