import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import fs from "fs/promises";
import path from "path";

export function registerGetRules(server: McpServer, novaRoot: string): void {
  server.registerTool(
    "get_rules",
    {
      title: "Nova 규칙 조회",
      description:
        "Nova 품질 게이트 규칙 전문을 반환합니다. section을 지정하면 해당 섹션(§1~§9)만 반환합니다.",
      inputSchema: z.object({
        section: z
          .string()
          .regex(/^\d+$/, "섹션 번호는 숫자만 허용됩니다")
          .optional()
          .describe(
            "특정 섹션 번호 (예: '1', '2'). 미지정 시 전체 규칙 반환"
          ),
      }),
    },
    async ({ section }) => {
      const rulesPath = path.join(novaRoot, "docs", "nova-rules.md");

      let content: string;
      try {
        content = await fs.readFile(rulesPath, "utf-8");
      } catch {
        return {
          content: [
            {
              type: "text" as const,
              text: "파일을 찾을 수 없습니다: docs/nova-rules.md",
            },
          ],
        };
      }

      if (!section) {
        return { content: [{ type: "text" as const, text: content }] };
      }

      const sectionPattern = new RegExp(
        `(## §${section}\\..+?)(?=## §|$)`,
        "s"
      );
      const match = content.match(sectionPattern);
      if (!match) {
        return {
          content: [
            {
              type: "text" as const,
              text: `섹션 §${section}을 찾을 수 없습니다. 유효한 섹션 번호를 확인하세요.`,
            },
          ],
        };
      }

      return { content: [{ type: "text" as const, text: match[1].trim() }] };
    }
  );
}
