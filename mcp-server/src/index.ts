import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { fileURLToPath } from "url";
import path from "path";
import fs from "fs";

import { registerGetRules } from "./tools/get-rules.js";
import { registerGetCommands } from "./tools/get-commands.js";
import { registerGetState } from "./tools/get-state.js";
import { registerOrchestrate } from "./tools/orchestrate.js";
import { registerXVerify } from "./tools/x-verify.js";
import { registerOrchestrationTracker } from "./tools/orchestration-tracker.js";
import { registerRepoPreflight } from "./tools/repo-preflight.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// dist/ → mcp-server/ → nova root
const NOVA_ROOT = path.resolve(__dirname, "../..");

function readVersion(): string {
  try {
    const pluginJson = JSON.parse(
      fs.readFileSync(
        path.join(NOVA_ROOT, ".claude-plugin", "plugin.json"),
        "utf-8"
      )
    );
    return pluginJson.version ?? "0.0.0";
  } catch {
    return "0.0.0";
  }
}

const server = new McpServer({
  name: "nova",
  version: readVersion(),
});

registerGetRules(server, NOVA_ROOT);
registerGetCommands(server, NOVA_ROOT);
registerGetState(server);
registerOrchestrate(server);
registerXVerify(server);
registerOrchestrationTracker(server);
registerRepoPreflight(server);

const transport = new StdioServerTransport();
await server.connect(transport);
