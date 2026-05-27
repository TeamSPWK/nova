/**
 * 사용자 프로젝트 디렉토리 해석.
 *
 * 우선순위:
 *   1. 명시 인자 (caller가 project_path / cwd 등으로 전달)
 *   2. CLAUDE_PROJECT_DIR — Claude Code v2.1.141+에서 stdio MCP 서버 환경변수로 자동 주입
 *   3. process.cwd() — fallback
 *
 * worktree 또는 nested 디렉토리에서 MCP 호출 시 process.cwd()는 의도와 다를 수 있으므로
 * Claude Code가 주입하는 CLAUDE_PROJECT_DIR를 우선한다.
 */
export function resolveProjectDir(explicit?: string): string {
  return explicit ?? process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
}
