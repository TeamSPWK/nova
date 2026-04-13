import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import fs from "fs/promises";
import path from "path";

type PhaseStatus = "pending" | "running" | "completed" | "failed" | "skipped";

interface Phase {
  name: string;
  role: string;
  status: PhaseStatus;
  startedAt?: string;
  completedAt?: string;
  result?: string;
}

interface Orchestration {
  id: string;
  task: string;
  complexity: string;
  status: "running" | "completed" | "failed";
  phases: Phase[];
  createdAt: string;
  updatedAt: string;
}

// 메모리 + 파일 동기화
const orchestrations = new Map<string, Orchestration>();

async function saveToDisk(): Promise<void> {
  try {
    const data = Object.fromEntries(orchestrations);
    const filePath = path.join(process.cwd(), ".nova-orchestration.json");
    await fs.writeFile(filePath, JSON.stringify(data, null, 2), "utf-8");
  } catch {
    // 저장 실패 무시 (읽기 전용 환경 등)
  }
}

async function loadFromDisk(): Promise<void> {
  try {
    const filePath = path.join(process.cwd(), ".nova-orchestration.json");
    const content = await fs.readFile(filePath, "utf-8");
    const data = JSON.parse(content) as Record<string, Orchestration>;
    for (const [id, orch] of Object.entries(data)) {
      if (orch.status === "running") {
        orchestrations.set(id, orch);
      }
    }
  } catch {
    // 파일 없으면 무시
  }
}

function generateId(): string {
  return `orch-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
}

function formatStatus(orch: Orchestration): string {
  const statusIcon: Record<PhaseStatus, string> = {
    pending: "⏳",
    running: "🔄",
    completed: "✅",
    failed: "❌",
    skipped: "⏭️",
  };

  let output = `# Orchestration: ${orch.task}\n`;
  output += `ID: ${orch.id} | 복잡도: ${orch.complexity} | 상태: ${orch.status}\n`;
  output += `생성: ${orch.createdAt} | 갱신: ${orch.updatedAt}\n\n`;
  output += `## Phases\n`;

  for (const phase of orch.phases) {
    const icon = statusIcon[phase.status];
    output += `${icon} ${phase.name} (${phase.role}) — ${phase.status}`;
    if (phase.result) output += ` — ${phase.result}`;
    output += "\n";
  }

  return output;
}

export function registerOrchestrationTracker(server: McpServer): void {
  // 시작 시 디스크에서 로드
  loadFromDisk();

  // 오케스트레이션 시작
  server.registerTool(
    "orchestration_start",
    {
      title: "오케스트레이션 시작",
      description:
        "새 오케스트레이션 세션을 생성하고 Phase를 등록합니다. " +
        "오케스트레이터 스킬이 작업 시작 시 호출합니다.",
      inputSchema: z.object({
        task: z.string().describe("수행할 태스크 설명"),
        complexity: z
          .enum(["simple", "medium", "complex"])
          .describe("복잡도"),
        phases: z
          .array(
            z.object({
              name: z.string().describe("Phase 이름 (예: 설계, 구현, 검증)"),
              role: z
                .string()
                .describe("담당 에이전트 역할 (예: Architect, Generator, Evaluator)"),
            })
          )
          .describe("Phase 목록 (실행 순서대로)"),
      }),
    },
    async ({ task, complexity, phases }) => {
      const id = generateId();
      const now = new Date().toISOString();
      const orch: Orchestration = {
        id,
        task,
        complexity,
        status: "running",
        phases: phases.map((p) => ({
          name: p.name,
          role: p.role,
          status: "pending" as PhaseStatus,
        })),
        createdAt: now,
        updatedAt: now,
      };
      orchestrations.set(id, orch);
      await saveToDisk();
      return {
        content: [
          {
            type: "text" as const,
            text: `오케스트레이션 시작: ${id}\n\n${formatStatus(orch)}`,
          },
        ],
      };
    }
  );

  // Phase 상태 업데이트
  server.registerTool(
    "orchestration_update",
    {
      title: "오케스트레이션 Phase 업데이트",
      description:
        "오케스트레이션의 특정 Phase 상태를 업데이트합니다.",
      inputSchema: z.object({
        orchestration_id: z.string().describe("오케스트레이션 ID"),
        phase_name: z.string().describe("업데이트할 Phase 이름"),
        status: z
          .enum(["running", "completed", "failed", "skipped"])
          .describe("새 상태"),
        result: z
          .string()
          .optional()
          .describe("결과 요약 (예: 'PASS', '3개 파일 수정', 'FAIL: 타입 에러')"),
      }),
    },
    async ({ orchestration_id, phase_name, status, result }) => {
      const orch = orchestrations.get(orchestration_id);
      if (!orch) {
        return {
          content: [
            {
              type: "text" as const,
              text: `ERROR: 오케스트레이션 ${orchestration_id}을 찾을 수 없습니다.`,
            },
          ],
        };
      }

      const phase = orch.phases.find((p) => p.name === phase_name);
      if (!phase) {
        return {
          content: [
            {
              type: "text" as const,
              text: `ERROR: Phase "${phase_name}"을 찾을 수 없습니다.`,
            },
          ],
        };
      }

      const now = new Date().toISOString();
      phase.status = status;
      if (result) phase.result = result;
      if (status === "running") phase.startedAt = now;
      if (status === "completed" || status === "failed") phase.completedAt = now;
      orch.updatedAt = now;

      // 전체 상태 판정
      const allDone = orch.phases.every(
        (p) => p.status === "completed" || p.status === "skipped"
      );
      const anyFailed = orch.phases.some((p) => p.status === "failed");
      if (anyFailed) orch.status = "failed";
      else if (allDone) orch.status = "completed";

      await saveToDisk();
      return {
        content: [
          { type: "text" as const, text: formatStatus(orch) },
        ],
      };
    }
  );

  // 상태 조회
  server.registerTool(
    "orchestration_status",
    {
      title: "오케스트레이션 상태 조회",
      description:
        "활성 오케스트레이션의 현재 상태를 조회합니다.",
      inputSchema: z.object({
        orchestration_id: z
          .string()
          .optional()
          .describe("특정 ID 조회. 미지정 시 활성 오케스트레이션 전체 목록"),
      }),
    },
    async ({ orchestration_id }) => {
      if (orchestration_id) {
        const orch = orchestrations.get(orchestration_id);
        if (!orch) {
          return {
            content: [
              {
                type: "text" as const,
                text: `오케스트레이션 ${orchestration_id}을 찾을 수 없습니다.`,
              },
            ],
          };
        }
        return {
          content: [{ type: "text" as const, text: formatStatus(orch) }],
        };
      }

      // 전체 목록
      const running = [...orchestrations.values()].filter(
        (o) => o.status === "running"
      );
      if (running.length === 0) {
        return {
          content: [
            {
              type: "text" as const,
              text: "활성 오케스트레이션이 없습니다.",
            },
          ],
        };
      }

      const list = running.map((o) => formatStatus(o)).join("\n---\n\n");
      return {
        content: [{ type: "text" as const, text: list }],
      };
    }
  );
}
