import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

type Scope = "lite" | "standard" | "full";

function buildVerifyChecklist(scope: Scope): string {
  const base = `## 공통 게이트 (모든 스코프 필수)

- [ ] tsc / lint 에러 없음
- [ ] 기능이 요구사항대로 동작함
- [ ] 경계값(0, 음수, 빈 값, 빈 배열)에서 크래시 없음
- [ ] 기존 동작 회귀 없음`;

  const standard = `

## 표준 검증 (standard + full)

### 코드 품질
- [ ] 불필요한 추상화, 미래 대비 코드 없음
- [ ] 의도가 코드에서 직접 읽힘 (가독성)
- [ ] 최소 변경 원칙 준수 (목표 외 수정 없음)
- [ ] 에러 핸들링이 적절함 (throw vs 메시지 반환)

### 테스트 용이성
- [ ] 변경 사항을 검증하는 테스트가 존재하거나 추가됨
- [ ] 테스트가 없는 경우, 이유가 정당화됨

### 보안 기본
- [ ] 사용자 입력 유효성 검증 존재
- [ ] 민감 정보(키, 토큰) 하드코딩 없음
- [ ] 파일 경로 조작(path traversal) 취약점 없음`;

  const full = `

## 심층 검증 (full 전용)

### 성능
- [ ] N+1 쿼리 또는 루프 내 I/O 없음
- [ ] 대용량 데이터 처리 시 메모리 누수 없음
- [ ] 응답 시간이 허용 기준 이내

### 고위험 영역 (인증/DB/결제)
- [ ] 인증 우회 경로 없음
- [ ] SQL 인젝션 / NoSQL 인젝션 방어
- [ ] 트랜잭션 원자성 보장
- [ ] 결제 금액 정합성 검증

### 아키텍처
- [ ] 설계 문서(Plan/Design)와 구현 일치
- [ ] 인터페이스 계약 준수
- [ ] 의존성 방향이 올바름 (순환 의존 없음)
- [ ] 배포 환경 전환 조건 충족

### 통합
- [ ] 외부 API 연동 실패 시 폴백 존재
- [ ] 환경 변수 누락 시 명확한 에러 메시지
- [ ] 롤백 계획 수립됨`;

  const scopes: Record<Scope, string> = {
    lite: `# Nova 검증 체크리스트 — Lite (--fast)

${base}

---

**판정**: PASS / FAIL
**이유**: (실패 시 구체적 파일:라인 명시)
`,
    standard: `# Nova 검증 체크리스트 — Standard

${base}
${standard}

---

**판정**: PASS / NEEDS WORK / FAIL
**이슈 목록**: (NEEDS WORK/FAIL 시 심각도 + 파일:라인 + 내용 + 제안)
`,
    full: `# Nova 검증 체크리스트 — Full (--strict)

${base}
${standard}
${full}

---

**판정**: PASS / NEEDS WORK / FAIL
**이슈 목록**: (심각도: Critical / High / Medium / Low)

| # | 심각도 | 파일:라인 | 내용 | 제안 |
|---|--------|-----------|------|------|

**잘된 점**:
- (구체적으로)
`,
  };

  return scopes[scope];
}

export function registerVerify(server: McpServer): void {
  server.registerTool(
    "verify",
    {
      title: "검증 기준 체크리스트 반환",
      description:
        "검증 강도(lite/standard/full)에 따른 Nova 품질 검증 체크리스트를 반환합니다.",
      inputSchema: z.object({
        scope: z
          .enum(["lite", "standard", "full"])
          .optional()
          .describe(
            "검증 강도: lite(빠른 게이트), standard(기본), full(심층/--strict). 미지정 시 standard"
          ),
      }),
    },
    async ({ scope }) => {
      const level: Scope = scope ?? "standard";
      const checklist = buildVerifyChecklist(level);
      return {
        content: [{ type: "text" as const, text: checklist }],
      };
    }
  );
}
