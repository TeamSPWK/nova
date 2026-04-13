import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import fs from "fs/promises";
import path from "path";

type AiName = "claude" | "gpt" | "gemini";

interface AiResult {
  name: AiName;
  text: string;
  ok: boolean;
}

interface ConsensusAnalysis {
  consensus_rate: number | string;
  common_points: string[];
  differences: string[];
  verdict: string;
  summary: string;
}

// .env 파싱 (KEY=VALUE, 주석/빈줄 무시)
function parseEnv(content: string): Record<string, string> {
  const env: Record<string, string> = {};
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eqIdx = trimmed.indexOf("=");
    if (eqIdx < 0) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    let value = trimmed.slice(eqIdx + 1).trim();
    // 따옴표 제거
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

// API 호출 (재시도 1회)
async function callApi(
  url: string,
  headers: Record<string, string>,
  body: unknown,
  extractFn: (json: unknown) => string | undefined
): Promise<string> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...headers },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(30_000),
      });
      const json = await res.json();
      const text = extractFn(json);
      if (text) return text;
    } catch {
      // retry
    }
    if (attempt === 0) await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("API 호출 실패 (2회 시도)");
}

async function callClaude(
  apiKey: string,
  model: string,
  systemPrompt: string,
  question: string
): Promise<string> {
  return callApi(
    "https://api.anthropic.com/v1/messages",
    {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    {
      model,
      max_tokens: 1024,
      system: systemPrompt,
      messages: [{ role: "user", content: question }],
    },
    (json: unknown) => {
      const j = json as { content?: { text?: string }[] };
      return j?.content?.[0]?.text;
    }
  );
}

async function callGpt(
  apiKey: string,
  model: string,
  systemPrompt: string,
  question: string
): Promise<string> {
  return callApi(
    "https://api.openai.com/v1/chat/completions",
    { Authorization: `Bearer ${apiKey}` },
    {
      model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: question },
      ],
      temperature: 0.7,
    },
    (json: unknown) => {
      const j = json as { choices?: { message?: { content?: string } }[] };
      return j?.choices?.[0]?.message?.content;
    }
  );
}

async function callGemini(
  apiKey: string,
  model: string,
  systemPrompt: string,
  question: string
): Promise<string> {
  return callApi(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {},
    {
      contents: [{ parts: [{ text: `${systemPrompt}\n\n${question}` }] }],
    },
    (json: unknown) => {
      const j = json as {
        candidates?: { content?: { parts?: { text?: string }[] } }[];
      };
      return j?.candidates?.[0]?.content?.parts?.[0]?.text;
    }
  );
}

async function analyzeConsensus(
  geminiKey: string,
  geminiModel: string,
  question: string,
  results: AiResult[]
): Promise<ConsensusAnalysis> {
  const responsesText = results
    .filter((r) => r.ok)
    .map((r) => `## ${r.name} 응답\n${r.text}`)
    .join("\n\n");

  const prompt = `다음은 같은 질문에 대한 ${results.filter((r) => r.ok).length}개 AI의 응답입니다. 합의 수준을 분석하세요.

## 원래 질문
${question}

${responsesText}
반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트 없이 JSON만:
{
  "consensus_rate": (0-100 정수. 핵심 결론의 방향성이 일치하는 정도),
  "common_points": ["공통 의견1", "공통 의견2"],
  "differences": ["차이점1", "차이점2"],
  "verdict": "auto_approve 또는 human_review 또는 redefine",
  "summary": "한줄 요약"
}`;

  const raw = await callApi(
    `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent?key=${geminiKey}`,
    {},
    {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.1 },
    },
    (json: unknown) => {
      const j = json as {
        candidates?: { content?: { parts?: { text?: string }[] } }[];
      };
      return j?.candidates?.[0]?.content?.parts?.[0]?.text;
    }
  );

  // JSON 추출 (마크다운 코드블록 제거)
  const cleaned = raw.replace(/```json\s*/g, "").replace(/```/g, "").trim();
  return JSON.parse(cleaned) as ConsensusAnalysis;
}

function formatOutput(
  question: string,
  results: AiResult[],
  analysis: ConsensusAnalysis | null,
  availableAis: AiName[]
): string {
  const aiLabels: Record<AiName, string> = {
    claude: "🟣 Claude (Anthropic)",
    gpt: "🟢 GPT (OpenAI)",
    gemini: "🔵 Gemini (Google)",
  };

  let output = `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Nova X-Verification v2 — 멀티 AI 다관점 자문
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ❓ 질문: ${question}

`;

  for (const ai of (["claude", "gpt", "gemini"] as AiName[])) {
    const result = results.find((r) => r.name === ai);
    if (result) {
      output += `━━━ ${aiLabels[ai]} ━━━━━━━━━━━━━━━━━━━━━━\n`;
      output += result.ok
        ? result.text
        : `ERROR: ${result.text}`;
      output += "\n\n";
    } else if (!availableAis.includes(ai)) {
      output += `━━━ ${aiLabels[ai]} ━━━ [건너뜀: API 키 없음] ━━━\n\n`;
    }
  }

  if (analysis) {
    const verdictMap: Record<string, string> = {
      auto_approve: "✅ AUTO APPROVE",
      human_review: "⚠️  HUMAN REVIEW",
      agent_review: "🤖 AGENT REVIEW",
      redefine: "🔄 REDEFINE",
    };
    const verdictLabel = verdictMap[analysis.verdict] ?? `❓ ${analysis.verdict}`;
    const rateStr =
      typeof analysis.consensus_rate === "number"
        ? `${analysis.consensus_rate}%`
        : String(analysis.consensus_rate);

    output += `━━━ 📊 합의 분석 결과 ━━━━━━━━━━━━━━━━━━━━━━━━━

  합의율:  ${rateStr}
  판정:    ${verdictLabel}
  요약:    ${analysis.summary}

`;
    if (analysis.common_points.length > 0) {
      output += `  공통점:\n`;
      for (const p of analysis.common_points) output += `    • ${p}\n`;
      output += "\n";
    }
    if (analysis.differences.length > 0) {
      output += `  차이점:\n`;
      for (const d of analysis.differences) output += `    • ${d}\n`;
      output += "\n";
    }
  } else {
    output += `💡 AI 1개 + 현재 에이전트 = 교차검증 (합의 분석 건너뜀)\n\n`;
  }

  output += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`;
  return output;
}

function buildSaveContent(
  question: string,
  results: AiResult[],
  analysis: ConsensusAnalysis | null,
  availableAis: AiName[]
): string {
  const date = new Date().toISOString().slice(0, 10);
  const rateStr = analysis
    ? typeof analysis.consensus_rate === "number"
      ? `${analysis.consensus_rate}%`
      : String(analysis.consensus_rate)
    : "N/A";
  const verdict = analysis?.verdict ?? "agent_review";

  let md = `# X-Verification: ${question.slice(0, 80)}

> 날짜: ${date}
> 합의율: ${rateStr}
> 판정: ${verdict}
> AI: ${availableAis.join(", ")}

## 질문
${question}

`;

  for (const r of results) {
    md += `## ${r.name}\n${r.ok ? r.text : `ERROR: ${r.text}`}\n\n`;
  }

  if (analysis) {
    md += `## 합의 분석
- **합의율**: ${rateStr}
- **판정**: ${verdict}
- **요약**: ${analysis.summary}

### 공통점
${analysis.common_points.map((p) => `- ${p}`).join("\n")}

### 차이점
${analysis.differences.map((d) => `- ${d}`).join("\n")}
`;
  }

  return md;
}

export function registerXVerify(server: McpServer): void {
  server.registerTool(
    "x_verify",
    {
      title: "멀티 AI 교차검증 (X-Verification)",
      description:
        "3개 AI(Claude, GPT, Gemini)에 동시 질의하고 합의율을 자동 산출합니다. " +
        "프로젝트 루트의 .env에서 API 키를 읽습니다.",
      inputSchema: z.object({
        question: z.string().describe("교차검증할 질문"),
        no_save: z
          .boolean()
          .optional()
          .describe("true이면 결과를 파일로 저장하지 않음"),
        selected_ais: z
          .array(z.enum(["claude", "gpt", "gemini"]))
          .optional()
          .describe("특정 AI만 호출 (미지정 시 키가 있는 모든 AI)"),
        claude_model: z
          .enum(["opus", "sonnet", "haiku"])
          .optional()
          .describe("Claude 모델 선택 (기본: sonnet)"),
      }),
    },
    async ({ question, no_save, selected_ais, claude_model }) => {
      // .env 로드 (CWD = 사용자 프로젝트 루트)
      let envVars: Record<string, string> = {};
      try {
        const envContent = await fs.readFile(
          path.join(process.cwd(), ".env"),
          "utf-8"
        );
        envVars = parseEnv(envContent);
      } catch {
        return {
          content: [
            {
              type: "text" as const,
              text: "ERROR: 프로젝트 루트에 .env 파일을 찾을 수 없습니다. API 키가 필요합니다.",
            },
          ],
        };
      }

      // API 키 확인
      const keys: Record<AiName, string | undefined> = {
        claude: envVars.ANTHROPIC_API_KEY,
        gpt: envVars.OPENAI_API_KEY,
        gemini: envVars.GEMINI_API_KEY,
      };

      let availableAis: AiName[] = (
        Object.entries(keys) as [AiName, string | undefined][]
      )
        .filter(([, v]) => !!v)
        .map(([k]) => k);

      // 선택된 AI 필터링
      if (selected_ais && selected_ais.length > 0) {
        const missing = selected_ais.filter(
          (ai) => !availableAis.includes(ai)
        );
        if (missing.length > 0) {
          return {
            content: [
              {
                type: "text" as const,
                text: `ERROR: ${missing.join(", ")} API 키가 .env에 없습니다.`,
              },
            ],
          };
        }
        availableAis = selected_ais as AiName[];
      }

      if (availableAis.length === 0) {
        return {
          content: [
            {
              type: "text" as const,
              text: "ERROR: 사용 가능한 AI가 없습니다. .env에 ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY 중 최소 1개를 설정하세요.",
            },
          ],
        };
      }

      // 모델 설정
      const claudeModelMap: Record<string, string> = {
        opus: envVars.CLAUDE_MODEL_OPUS ?? "claude-opus-4-6",
        sonnet: envVars.CLAUDE_MODEL ?? "claude-sonnet-4-6",
        haiku: envVars.CLAUDE_MODEL_HAIKU ?? "claude-haiku-4-5-20251001",
      };
      const resolvedClaudeModel =
        claudeModelMap[claude_model ?? "sonnet"];
      const openaiModel = envVars.OPENAI_MODEL ?? "gpt-5.4";
      const geminiModel =
        envVars.GEMINI_MODEL ?? "gemini-3-flash-preview";

      const systemPrompt =
        "당신은 소프트웨어 아키텍처 전문가입니다. 질문에 대해 명확하고 구조화된 의견을 한국어로 제시하세요. 답변은 500자 이내로 핵심만 간결하게.";

      // 병렬 호출
      const calls: Promise<AiResult>[] = availableAis.map(
        async (ai): Promise<AiResult> => {
          try {
            let text: string;
            switch (ai) {
              case "claude":
                text = await callClaude(
                  keys.claude!,
                  resolvedClaudeModel,
                  systemPrompt,
                  question
                );
                break;
              case "gpt":
                text = await callGpt(
                  keys.gpt!,
                  openaiModel,
                  systemPrompt,
                  question
                );
                break;
              case "gemini":
                text = await callGemini(
                  keys.gemini!,
                  geminiModel,
                  systemPrompt,
                  question
                );
                break;
            }
            return { name: ai, text, ok: true };
          } catch (e) {
            return {
              name: ai,
              text: e instanceof Error ? e.message : String(e),
              ok: false,
            };
          }
        }
      );

      const results = await Promise.all(calls);
      const successCount = results.filter((r) => r.ok).length;

      if (successCount === 0) {
        return {
          content: [
            {
              type: "text" as const,
              text: "ERROR: 모든 AI 호출이 실패했습니다. 네트워크 및 API 키를 확인하세요.\n\n" +
                results.map((r) => `${r.name}: ${r.text}`).join("\n"),
            },
          ],
        };
      }

      // 합의 분석 (성공 2개 이상 + Gemini 키 필요)
      let analysis: ConsensusAnalysis | null = null;
      if (successCount >= 2 && keys.gemini) {
        try {
          analysis = await analyzeConsensus(
            keys.gemini,
            geminiModel,
            question,
            results
          );
        } catch {
          // 합의 분석 실패 시 결과만 반환
        }
      }

      // 결과 포맷
      const output = formatOutput(question, results, analysis, availableAis);

      // 파일 저장
      let savedPath = "";
      if (!no_save) {
        try {
          const date = new Date().toISOString().slice(0, 10);
          const slug = question
            .slice(0, 40)
            .replace(/[^a-zA-Z0-9가-힣]/g, "-")
            .replace(/-+/g, "-")
            .replace(/-$/, "");
          const verifyDir = path.join(process.cwd(), "docs", "verifications");
          await fs.mkdir(verifyDir, { recursive: true });
          const filePath = path.join(verifyDir, `${date}-${slug}.md`);
          await fs.writeFile(
            filePath,
            buildSaveContent(question, results, analysis, availableAis),
            "utf-8"
          );
          savedPath = filePath;
        } catch {
          // 저장 실패는 무시
        }
      }

      const footer = savedPath ? `\n\n📁 결과 저장: ${savedPath}` : "";

      return {
        content: [{ type: "text" as const, text: output + footer }],
      };
    }
  );
}
