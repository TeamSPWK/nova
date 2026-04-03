import { z } from "zod";
function buildPlanTemplate(topic, context) {
    const now = new Date().toISOString().split("T")[0];
    return `# Plan: ${topic}

> 작성일: ${now}
> 프레임워크: CPS (Context → Problem → Solution)

---

## Context

> 왜 이 작업이 필요한가? 배경과 현재 상태를 기술한다.

${context ? context : "<!-- 배경, 현재 상태, 작업 동기를 여기에 기술하세요 -->"}

### 현재 상태
- [ ] 현재 시스템/기능의 상태

### 작업 동기
- [ ] 이 작업을 지금 해야 하는 이유

---

## Problem

> 구체적으로 무엇이 문제인가? MECE(상호 배타적, 전체 포괄)로 분해한다.

### 핵심 문제
- [ ] 문제 1
- [ ] 문제 2

### 제약 조건
- 기술적 제약:
- 비즈니스 제약:
- 시간 제약:

### 비기능 요구사항
- 인증/보안:
- 성능:
- 외부 연동:

---

## Solution

> 어떻게 해결하는가? 트레이드오프와 결정 근거를 포함한다.

### 접근 방식
<!-- 선택한 해결책과 그 이유 -->

### 대안 검토
| 대안 | 장점 | 단점 | 결정 |
|------|------|------|------|
| 안 A |  |  | 기각 |
| 안 B |  |  | **채택** |

### 구현 계획
1. 단계 1:
2. 단계 2:
3. 단계 3:

### 복잡도 판정
- 수정 파일 예상: __개
- 복잡도: ☐ 간단 / ☐ 보통 / ☐ 복잡
- 고위험 영역(인증/DB/결제): ☐ 해당 / ☐ 미해당

### 검증 계획
- [ ] 기능 테스트:
- [ ] 엣지 케이스:
- [ ] 성능 확인:

---

## 승인

- [ ] 계획 검토 완료
- [ ] 구현 착수 승인
`;
}
export function registerCreatePlan(server) {
    server.registerTool("create_plan", {
        title: "CPS Plan 생성",
        description: "CPS(Context → Problem → Solution) 프레임워크 기반의 Plan 문서 초안을 생성합니다.",
        inputSchema: z.object({
            topic: z.string().describe("Plan의 주제 또는 기능명"),
            context: z
                .string()
                .optional()
                .describe("Context 섹션에 미리 채울 배경 정보 (선택)"),
        }),
    }, async ({ topic, context }) => {
        const planText = buildPlanTemplate(topic, context);
        return {
            content: [{ type: "text", text: planText }],
        };
    });
}
