#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";

const rpcUrl = process.env.ZAR_RPC_URL ?? "http://127.0.0.1:18080/rpc";
const workRoot = process.env.ZAR_SMOKE_ROOT ?? path.join(os.tmpdir(), "zar-hermes-port-smoke");
const sessionId = process.env.ZAR_SMOKE_SESSION_ID ?? `hermes-port-${Date.now()}`;
const messageNeedle = `Hermes port smoke message ${Date.now()}`;
const filePath = path.join(workRoot, "coding-agent.txt");
const jsArtifactPath = path.join(workRoot, "execute-code-js.txt");
const zigBinary = process.env.ZAR_ZIG_BIN ?? "";
const nodeBinary = process.execPath;


function startMockWebServer() {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? "/", "http://127.0.0.1");
    if (url.pathname === "/search") {
      const q = url.searchParams.get("q") ?? "";
      const pageBase = `http://127.0.0.1:${server.address().port}`;
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(`<!doctype html>
<html><body>
  <div class="result">
    <a class="result__a" href="${pageBase}/page-1">Hermes Zig Web Result One</a>
    <div class="result__snippet">Mock search description one for ${q}</div>
  </div>
  <div class="result">
    <a class="result__a" href="${pageBase}/page-2">Hermes Zig Web Result Two</a>
    <div class="result__snippet">Mock search description two for ${q}</div>
  </div>
</body></html>`);
      return;
    }
    if (url.pathname === "/page-1") {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(`<!doctype html><html><head><title>Hermes Zig Web Page One</title><script>ignore-me()</script></head><body><h1>Web Extract Sentinel One</h1><p>Search to extract bridge for Hermes into ZAR.</p></body></html>`);
      return;
    }
    if (url.pathname === "/page-2") {
      res.writeHead(200, { "content-type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ kind: "mock", content: "Web extract sentinel two" }));
      return;
    }
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
    res.end("not found");
  });

  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      resolve({
        server,
        baseUrl: `http://127.0.0.1:${address.port}`,
        close: () => new Promise((resolveClose, rejectClose) => {
          server.close((error) => (error ? rejectClose(error) : resolveClose()));
        }),
      });
    });
  });
}

await fs.mkdir(workRoot, { recursive: true });
const mockWeb = await startMockWebServer();

async function rpc(method, params = {}, id = method) {
  const response = await fetch(rpcUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "connection": "close",
    },
    body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
  });
  const bodyText = await response.text();
  let body;
  try {
    body = JSON.parse(bodyText);
  } catch (error) {
    throw new Error(`Non-JSON response for ${method}: ${bodyText}`);
  }
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} for ${method}: ${bodyText}`);
  }
  if (body.error) {
    throw new Error(`RPC error for ${method}: ${JSON.stringify(body.error)}`);
  }
  return body.result;
}

try {
const catalog = await rpc("tools.catalog", {}, "catalog");
const catalogJson = JSON.stringify(catalog);
assert.match(catalogJson, /execute_code/);
assert.match(catalogJson, /file\.search/);
assert.match(catalogJson, /file\.patch/);
assert.match(catalogJson, /web\.search/);
assert.match(catalogJson, /web\.extract/);
assert.match(catalogJson, /process\.start/);
assert.match(catalogJson, /process\.list/);
assert.match(catalogJson, /process\.poll/);
assert.match(catalogJson, /process\.read/);
assert.match(catalogJson, /process\.wait/);
assert.match(catalogJson, /process\.kill/);
assert.match(catalogJson, /sessions\.search/);

const writeResult = await rpc(
  "file.write",
  {
    sessionId,
    path: filePath,
    content: [
      "alpha",
      "hermes-sentinel",
      "omega",
      "",
    ].join("\n"),
  },
  "write",
);
assert.equal(writeResult.ok, true);

const searchResult = await rpc(
  "file.search",
  {
    sessionId,
    path: workRoot,
    query: "hermes-sentinel",
    maxResults: 5,
  },
  "search",
);
assert.equal(searchResult.ok, true);
assert.equal(searchResult.count, 1);
assert.match(JSON.stringify(searchResult.items), /hermes-sentinel/);

const patchResult = await rpc(
  "file.patch",
  {
    sessionId,
    path: filePath,
    oldText: "hermes-sentinel",
    newText: "zar-sentinel",
  },
  "patch",
);
assert.equal(patchResult.ok, true);
assert.equal(patchResult.applied, true);
assert.equal(patchResult.replacements, 1);

const readResult = await rpc(
  "file.read",
  {
    sessionId,
    path: filePath,
  },
  "read",
);
assert.match(readResult.content, /zar-sentinel/);
assert.doesNotMatch(readResult.content, /hermes-sentinel/);

const webSearchResult = await rpc(
  "web.search",
  {
    sessionId,
    query: "hermes zig port",
    limit: 5,
    endpoint: `${mockWeb.baseUrl}/search`,
  },
  "web-search",
);
assert.equal(webSearchResult.ok, true);
assert.equal(webSearchResult.count, 2);
assert.match(JSON.stringify(webSearchResult.data.web), /Hermes Zig Web Result One/);

const webExtractResult = await rpc(
  "web.extract",
  {
    sessionId,
    urls: webSearchResult.data.web.map((item) => item.url),
    maxChars: 800,
  },
  "web-extract",
);
assert.equal(webExtractResult.ok, true);
assert.equal(webExtractResult.count, 2);
assert.match(JSON.stringify(webExtractResult.results), /Web Extract Sentinel One/);
assert.match(JSON.stringify(webExtractResult.results), /Web extract sentinel two/);

assert.ok(zigBinary, "ZAR_ZIG_BIN is required for execute_code zig smoke");

const executeCodeJsResult = await rpc(
  "execute_code",
  {
    sessionId,
    language: "javascript",
    runtimePath: nodeBinary,
    cwd: workRoot,
    keepFiles: true,
    args: ["delta"],
    code: [
      'const fs = require("node:fs");',
      'fs.writeFileSync("execute-code-js.txt", "js-created");',
      'console.log(JSON.stringify({ kind: "execute-code-js", cwd: process.cwd(), arg: process.argv[2] ?? "" }));',
      '',
    ].join("\n"),
  },
  "execute-code-js",
);
assert.equal(executeCodeJsResult.ok, true);
assert.equal(executeCodeJsResult.language, "javascript");
assert.equal(executeCodeJsResult.keptFiles, true);
assert.match(executeCodeJsResult.stdout, /execute-code-js/);
assert.match(executeCodeJsResult.stdout, /delta/);
assert.match(executeCodeJsResult.command, /node/);

const executeCodeJsArtifactRead = await rpc(
  "file.read",
  {
    sessionId,
    path: jsArtifactPath,
  },
  "execute-code-js-artifact",
);
assert.match(executeCodeJsArtifactRead.content, /js-created/);

const executeCodeJsScriptRead = await rpc(
  "file.read",
  {
    sessionId,
    path: executeCodeJsResult.scriptPath,
  },
  "execute-code-js-script",
);
assert.match(executeCodeJsScriptRead.content, /execute-code-js/);

const executeCodeZigResult = await rpc(
  "execute_code",
  {
    sessionId,
    language: "zig",
    runtimePath: zigBinary,
    cwd: workRoot,
    timeoutMs: 120000,
    code: [
      'const std = @import("std");',
      'pub fn main() !void {',
      '    std.debug.print("execute-code-zig\\n", .{});',
      '}',
      '',
    ].join("\n"),
  },
  "execute-code-zig",
);
assert.equal(executeCodeZigResult.ok, true);
assert.equal(executeCodeZigResult.language, "zig");
assert.match(`${executeCodeZigResult.stdout}\n${executeCodeZigResult.stderr}`, /execute-code-zig/);

const processStartResult = await rpc(
  "process.start",
  {
    sessionId,
    cwd: workRoot,
    command: "printf process-stdout; printf process-stderr >&2",
  },
  "process-start",
);
assert.equal(processStartResult.ok, true);
assert.match(processStartResult.processId, /^proc-/);

const processListResult = await rpc(
  "process.list",
  {
    sessionId,
  },
  "process-list",
);
assert.equal(processListResult.ok, true);
assert.ok(processListResult.count >= 1);
assert.match(JSON.stringify(processListResult.items), new RegExp(processStartResult.processId));

const processWaitResult = await rpc(
  "process.wait",
  {
    processId: processStartResult.processId,
    timeoutMs: 5000,
  },
  "process-wait",
);
assert.equal(processWaitResult.running, false);
assert.equal(processWaitResult.processState, "exited");
assert.equal(processWaitResult.exitCode, 0);
assert.match(processWaitResult.stdout, /process-stdout/);
assert.match(processWaitResult.stderr, /process-stderr/);

const processReadResult = await rpc(
  "process.read",
  {
    processId: processStartResult.processId,
  },
  "process-read",
);
assert.match(processReadResult.stdout, /process-stdout/);
assert.match(processReadResult.stderr, /process-stderr/);

const processKillStartResult = await rpc(
  "process.start",
  {
    sessionId,
    cwd: workRoot,
    command: "exec sleep 5",
  },
  "process-kill-start",
);
assert.equal(processKillStartResult.ok, true);

const processPollResult = await rpc(
  "process.poll",
  {
    processId: processKillStartResult.processId,
  },
  "process-poll",
);
assert.equal(processPollResult.running, true);

const processKillResult = await rpc(
  "process.kill",
  {
    processId: processKillStartResult.processId,
  },
  "process-kill",
);
assert.equal(processKillResult.requested, true);
assert.match(processKillResult.signal, /TERM/);

const processKillWaitResult = await rpc(
  "process.wait",
  {
    processId: processKillStartResult.processId,
    timeoutMs: 5000,
  },
  "process-kill-wait",
);
assert.equal(processKillWaitResult.ok, true);
assert.equal(processKillWaitResult.running, false);
assert.match(processKillWaitResult.processState, /killed|exited|failed/);
assert.equal(processKillWaitResult.status, 200);
assert.equal(processKillWaitResult.signal, "TERM");
assert.ok(processKillWaitResult.exitCode <= 0);

const sendResult = await rpc(
  "send",
  {
    channel: "telegram",
    to: "hermes-port-room",
    sessionId,
    message: messageNeedle,
  },
  "send",
);
assert.equal(sendResult.accepted, true);

const historyResult = await rpc(
  "sessions.history",
  {
    sessionId,
    limit: 10,
  },
  "history",
);
assert.equal(historyResult.sessionId, sessionId);
assert.ok(historyResult.count >= 2);
assert.match(JSON.stringify(historyResult.items), new RegExp(messageNeedle));

const sessionSearchResult = await rpc(
  "sessions.search",
  {
    query: messageNeedle,
    limit: 5,
  },
  "session-search",
);
assert.ok(sessionSearchResult.count >= 1);
assert.match(JSON.stringify(sessionSearchResult), new RegExp(sessionId));

console.log(JSON.stringify({
  ok: true,
  rpcUrl,
  sessionId,
  filePath,
  nodeBinary,
  zigBinary,
  verified: {
    toolsCatalog: [
      "execute_code",
      "file.search",
      "file.patch",
      "web.search",
      "web.extract",
      "process.start",
      "process.list",
      "process.poll",
      "process.read",
      "process.wait",
      "process.kill",
      "sessions.search",
    ],
    executeCodeJsOk: executeCodeJsResult.ok,
    executeCodeZigOk: executeCodeZigResult.ok,
    executeCodeJsArtifact: executeCodeJsArtifactRead.content,
    fileWrite: writeResult.ok,
    fileSearchCount: searchResult.count,
    filePatchApplied: patchResult.applied,
    webSearchCount: webSearchResult.count,
    webExtractCount: webExtractResult.count,
    processListCount: processListResult.count,
    processExitCode: processWaitResult.exitCode,
    processKillExitCode: processKillWaitResult.exitCode,
    sessionHistoryCount: historyResult.count,
    sessionSearchCount: sessionSearchResult.count,
  },
}, null, 2));
}
finally {
  await mockWeb.close();
}
