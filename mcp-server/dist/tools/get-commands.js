import fs from "fs/promises";
import path from "path";
async function extractDescription(filePath) {
    try {
        const content = await fs.readFile(filePath, "utf-8");
        const lines = content.split("\n");
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith("description:")) {
                return trimmed
                    .replace("description:", "")
                    .trim()
                    .replace(/^["']|["']$/g, "");
            }
        }
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith("#")) {
                return trimmed.replace(/^#+\s*/, "");
            }
            if (trimmed.length > 0 && !trimmed.startsWith("---")) {
                return trimmed.length > 100 ? trimmed.slice(0, 100) + "..." : trimmed;
            }
        }
        return "설명 없음";
    }
    catch {
        return "파일 읽기 실패";
    }
}
async function resolveCommandsDir(novaRoot) {
    const candidates = [
        path.join(novaRoot, ".claude", "commands"),
        path.join(novaRoot, "commands"),
    ];
    for (const candidate of candidates) {
        try {
            await fs.access(candidate);
            return candidate;
        }
        catch {
            // 다음 후보로
        }
    }
    return null;
}
export function registerGetCommands(server, novaRoot) {
    server.registerTool("get_commands", {
        title: "Nova 커맨드 목록 조회",
        description: ".claude/commands/ 디렉토리의 모든 슬래시 커맨드 목록과 설명을 반환합니다.",
        inputSchema: undefined,
    }, async () => {
        const commandsDir = await resolveCommandsDir(novaRoot);
        if (!commandsDir) {
            return {
                content: [
                    {
                        type: "text",
                        text: "파일을 찾을 수 없습니다: .claude/commands/ 또는 commands/ 디렉토리가 존재하지 않습니다.",
                    },
                ],
            };
        }
        let files;
        try {
            const entries = await fs.readdir(commandsDir);
            files = entries.filter((f) => f.endsWith(".md")).sort();
        }
        catch {
            return {
                content: [
                    {
                        type: "text",
                        text: `파일을 찾을 수 없습니다: ${commandsDir} 디렉토리를 읽을 수 없습니다.`,
                    },
                ],
            };
        }
        const commands = await Promise.all(files.map(async (file) => {
            const name = file.replace(".md", "");
            const description = await extractDescription(path.join(commandsDir, file));
            return { name: `/${name}`, description };
        }));
        const lines = [
            "# Nova 슬래시 커맨드 목록\n",
            ...commands.map((c) => `**${c.name}** — ${c.description}`),
        ];
        return {
            content: [{ type: "text", text: lines.join("\n") }],
        };
    });
}
