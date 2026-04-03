import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { fileURLToPath } from "url";
import path from "path";
import { registerGetRules } from "./tools/get-rules.js";
import { registerGetCommands } from "./tools/get-commands.js";
import { registerGetState } from "./tools/get-state.js";
import { registerCreatePlan } from "./tools/create-plan.js";
import { registerOrchestrate } from "./tools/orchestrate.js";
import { registerVerify } from "./tools/verify.js";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
// mcp-server/src/ → mcp-server/ → nova/
const NOVA_ROOT = path.resolve(__dirname, "../..");
const server = new McpServer({
    name: "nova",
    version: "3.12.0",
});
registerGetRules(server, NOVA_ROOT);
registerGetCommands(server, NOVA_ROOT);
registerGetState(server);
registerCreatePlan(server);
registerOrchestrate(server);
registerVerify(server);
const transport = new StdioServerTransport();
await server.connect(transport);
