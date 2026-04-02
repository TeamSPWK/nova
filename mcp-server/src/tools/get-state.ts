import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import fs from "fs/promises";
import path from "path";

export function registerGetState(server: McpServer): void {
  server.registerTool(
    "get_state",
    {
      title: "NOVA-STATE.md 읽기",
      description:
        "지정된 프로젝트 경로의 NOVA-STATE.md 파일을 읽어 반환합니다.",
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
      const targetDir = project_path ?? process.cwd();
      const statePath = path.join(targetDir, "NOVA-STATE.md");

      try {
        const content = await fs.readFile(statePath, "utf-8");
        return {
          content: [
            {
              type: "text" as const,
              text: `# NOVA-STATE.md (${targetDir})\n\n${content}`,
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
