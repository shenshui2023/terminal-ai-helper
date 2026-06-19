import http from "node:http";
import { requestCommandHelp } from "./api.js";
import { buildPrompt } from "./prompts.js";
import { renderHuman, renderJson, renderRaw } from "./render.js";

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 128 * 1024) {
        reject(new Error("Request body is too large."));
        req.destroy();
      }
    });
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

function send(res, status, contentType, body) {
  res.writeHead(status, {
    "content-type": contentType,
    "cache-control": "no-store",
    "access-control-allow-origin": "*"
  });
  res.end(body);
}

export async function startServer({ config, port }) {
  const server = http.createServer(async (req, res) => {
    try {
      if (req.method === "GET" && req.url === "/health") {
        send(res, 200, "application/json; charset=utf-8", JSON.stringify({ ok: true }));
        return;
      }

      if (req.method !== "POST" || req.url !== "/api") {
        send(res, 404, "text/plain; charset=utf-8", "not found");
        return;
      }

      const body = JSON.parse(await readBody(req));
      const mode = body.mode || "explain";
      const text = String(body.text || "").trim();
      const format = body.format || "text";
      if (!["explain", "complete", "fix"].includes(mode)) {
        send(res, 400, "text/plain; charset=utf-8", "invalid mode");
        return;
      }
      if (!text) {
        send(res, 400, "text/plain; charset=utf-8", "empty text");
        return;
      }

      const prompt = buildPrompt({
        mode,
        text,
        source: body.source || "http",
        shell: body.shell || "ssh remote shell"
      });
      const result = await requestCommandHelp(config, prompt);
      const output = format === "json" ? renderJson(result) : format === "raw" ? renderRaw(result) : renderHuman(result);
      send(res, 200, format === "json" ? "application/json; charset=utf-8" : "text/plain; charset=utf-8", output);
    } catch (error) {
      send(res, 500, "text/plain; charset=utf-8", error.message);
    }
  });

  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  console.log(`terminal-ai-helper server listening on http://127.0.0.1:${port}`);
  console.log("Use SSH reverse tunnel: ssh -R 17888:127.0.0.1:17888 <user>@<host>");
}
