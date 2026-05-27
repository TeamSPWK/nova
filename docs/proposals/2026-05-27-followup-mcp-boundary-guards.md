# Follow-up Proposal: MCP Boundary Guards (P-3 후속)

> 날짜: 2026-05-27
> 수준: minor
> 출처: v5.49.0 P-3 적용 직후 Security Engineer 적대적 검증
> 자율 등급: Semi Auto (PR)
> 상태: 보류 (별도 PR로 처리)

## Context

v5.49.0에서 P-3 (MCP `CLAUDE_PROJECT_DIR` 환경변수 우선순위 채택)를 적용한 직후 독립 Security Engineer 검증에서 **Medium 1건 + Low 2건** 발견. P-3의 원래 scope("환경변수 fallback")를 넘어가므로 본 follow-up으로 분리.

## 발견 (Security Engineer 출력 인용)

### Medium — 환경변수 신뢰 경계 불명확
- 파일: `mcp-server/src/util/project-dir.ts:13`
- `CLAUDE_PROJECT_DIR`가 Claude Code 런타임만 주입한다는 보장을 코드 레벨에서 강제하지 않음.
- 시나리오: 로컬 사용자가 직접 `CLAUDE_PROJECT_DIR=/etc` 설정 후 MCP 서버 수동 실행 → `orchestration-tracker`·`x-verify`(.env 로딩) 등이 `/etc` 하위 동작.
- 외부 공격자 시나리오 X, **로컬 권한 있는 사용자의 실수 시나리오**.

### Low — orchestration-tracker boundary 가드 부재
- 파일: `mcp-server/src/tools/orchestration-tracker.ts:42,62`
- `resolveProjectDir()` 반환 경로에 `.nova-orchestration.json` 직접 join하여 R/W 수행.
- `get-state.ts`에는 path traversal 가드(`startsWith`)가 있지만 `orchestration-tracker`에는 없음.
- 명시 인자 없는 도구라 env var만 영향 — 악용 가능성 낮음.

### Low — x-verify verifications 디렉토리 boundary 가드 부재
- 파일: `mcp-server/src/tools/x-verify.ts:491`
- `resolveProjectDir()` + `"docs/verifications"` 경로에 `fs.mkdir`/`fs.writeFile`.
- slug sanitization은 파일명에 있으나 `verifyDir` 자체 boundary 검증 없음.

## Nova 적용 방안

1. **`resolveProjectDir` 내부 가드 추가** (Medium 대응):
   ```ts
   const SENSITIVE_DIRS = ['/etc', '/usr', '/root', '/sys', '/proc', '/boot'];
   export function resolveProjectDir(explicit?: string): string {
     const resolved = path.resolve(explicit ?? process.env.CLAUDE_PROJECT_DIR ?? process.cwd());
     for (const sensitive of SENSITIVE_DIRS) {
       if (resolved === sensitive || resolved.startsWith(sensitive + path.sep)) {
         throw new Error(`Refusing to use sensitive system directory: ${resolved}`);
       }
     }
     return resolved;
   }
   ```
2. **`isInsideOrSame` helper 추출** (`mcp-server/src/util/path-guard.ts`) — `repo-preflight.ts`의 함수를 공통화.
3. **`orchestration-tracker.ts`에 boundary 가드 적용**: `saveToDisk`/`loadFromDisk`에서 `filePath`가 projectDir 하위인지 검증.
4. **`x-verify.ts`에 verifyDir boundary 가드 적용**.
5. **회귀 가드 추가**: `tests/test-scripts.sh`에 `CLAUDE_PROJECT_DIR=/tmp/outside-project` 동적 테스트 — 실제 boundary 위반 시 throw 또는 reject 검증.

## 영향 범위

- `mcp-server/src/util/project-dir.ts` (helper 가드 추가)
- `mcp-server/src/util/path-guard.ts` (신규)
- `mcp-server/src/tools/orchestration-tracker.ts`, `x-verify.ts` (boundary 가드 적용)
- `tests/test-scripts.sh` (동적 boundary 회귀 가드 신규 5개)

## 리스크

- `SENSITIVE_DIRS` denylist는 macOS/Linux 위주 — Windows 호환성 후속 검토 필요.
- 기존 회귀 가드는 정적 grep 수준이라 boundary 위반을 잡지 못함 — 동적 테스트 추가가 본 follow-up 핵심 가치.
- helper throw 도입 시 기존 호출 측 try/catch 없음 → MCP 서버 시작 실패 가능. 호출 측 graceful handling 동시 적용 필요.

## 자율 등급

**Semi Auto (PR)** — helper 변경 + 4개 도구 + 동적 테스트. 별도 PR로 분리해야 P-3과 인과 분리.

## 후속 적용 시점

- 본 follow-up은 v5.49.1 또는 v5.50.0 후보.
- 우선순위: Medium 가드(SENSITIVE_DIRS) > Low boundary 가드 > 동적 테스트.
- 즉시 적용하지 않는 이유: P-3 scope 분리 + 호출 측 try/catch 동시 변경 → 회귀 영향 큼 → 별도 검증 필요.
