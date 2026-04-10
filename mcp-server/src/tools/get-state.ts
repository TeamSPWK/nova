import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import fs from "fs/promises";
import path from "path";
import { execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

interface Advisory {
  message: string;
  commits_since_last_verify: number;
  last_verify_date: string | null;
}

async function buildAdvisory(targetDir: string, stateContent: string): Promise<Advisory | null> {
  // Last Activity에서 마지막 verify/review 날짜 추출
  const activityMatch = stateContent.match(
    /\/nova:(?:verify|review).*\|\s*(\d{4}-\d{2}-\d{2})/
  );
  const lastVerifyDate = activityMatch?.[1] ?? null;

  // git log로 마지막 verify 이후 커밋 수 카운트
  let commitsSinceVerify = 0;
  try {
    const sinceArg = lastVerifyDate ? `--since=${lastVerifyDate}` : "";
    const args = ["log", "--oneline"];
    if (sinceArg) args.push(sinceArg);

    const { stdout } = await execFileAsync("git", args, {
      cwd: targetDir,
      timeout: 5000,
    });
    commitsSinceVerify = stdout.trim().split("\n").filter(Boolean).length;
  } catch {
    // git 미설치 또는 git repo 아닌 경우 무시
    return null;
  }

  if (commitsSinceVerify < 3) return null;

  const message =
    commitsSinceVerify >= 5
      ? `마지막 verify 이후 ${commitsSinceVerify}개 커밋 누적. /nova:verify --fast 실행을 권장합니다.`
      : `마지막 verify 이후 ${commitsSinceVerify}개 커밋 발생. 검증 시점을 확인하세요.`;

  return {
    message,
    commits_since_last_verify: commitsSinceVerify,
    last_verify_date: lastVerifyDate,
  };
}

export function registerGetState(server: McpServer): void {
  server.registerTool(
    "get_state",
    {
      title: "NOVA-STATE.md 읽기 + advisory",
      description:
        "프로젝트의 NOVA-STATE.md를 읽고, 검증 누락 경고(advisory)를 함께 반환합니다.",
      inputSchema: z.object({
        project_path: z
          .string()
          .optional()
          .describe(
            "NOVA-STATE.md가 위치한 프로젝트 루트 경로. 미지정 시 현재 디렉토리(process.cwd())"
          ),
      }),
    },
    async ({ project_path }) => {
      const targetDir = path.resolve(project_path ?? process.cwd());
      const statePath = path.join(targetDir, "NOVA-STATE.md");

      // Path Traversal 방어: 최종 경로가 targetDir 내부인지 확인
      const resolvedState = path.resolve(statePath);
      if (!resolvedState.startsWith(targetDir + path.sep) && resolvedState !== path.join(targetDir, "NOVA-STATE.md")) {
        return {
          content: [{ type: "text" as const, text: "잘못된 경로입니다." }],
        };
      }

      try {
        const content = await fs.readFile(statePath, "utf-8");

        // Advisory 생성
        const advisory = await buildAdvisory(targetDir, content);
        const advisorySection = advisory
          ? `\n\n---\n## Advisory\n- ${advisory.message}\n- 마지막 검증: ${advisory.last_verify_date ?? "기록 없음"}\n- 이후 커밋 수: ${advisory.commits_since_last_verify}`
          : "";

        return {
          content: [
            {
              type: "text" as const,
              text: `# NOVA-STATE.md (${targetDir})\n\n${content}${advisorySection}`,
            },
          ],
        };
      } catch {
        return {
          content: [
            {
              type: "text" as const,
              text: `파일을 찾을 수 없습니다: ${statePath}\n\nNOVA-STATE.md가 존재하지 않습니다. /init 커맨드로 초기화하세요.`,
            },
          ],
        };
      }
    }
  );
}
