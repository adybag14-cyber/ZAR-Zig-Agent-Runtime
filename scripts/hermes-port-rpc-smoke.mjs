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
const delegateFilePath = path.join(workRoot, "delegate-task.txt");
const acpDelegateFilePath = path.join(workRoot, "acp-prompt-delegate.txt");
const acpSessionId = `${sessionId}-acp`;
const acpForkSessionId = `${acpSessionId}-fork`;
const acpDelegateSessionId = `${acpSessionId}-exec`;
const zigBinary = process.env.ZAR_ZIG_BIN ?? "";
const nodeBinary = process.execPath;
const requireHostedProcessSupport =
  process.env.ZAR_HERMES_REQUIRE_PROCESS === "1" ||
  (process.env.ZAR_HERMES_REQUIRE_PROCESS !== "0" && process.platform !== "win32");
const approvalPromptNodeId = "node-hermes-approval";
const approvalDenyNodeId = "node-hermes-deny";


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

async function rpcEnvelope(method, params = {}, id = method) {
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
  return body;
}

async function rpc(method, params = {}, id = method) {
  const body = await rpcEnvelope(method, params, id);
  if (body.error) {
    throw new Error(`RPC error for ${method}: ${JSON.stringify(body.error)}`);
  }
  return body.result;
}

try {
const catalog = await rpc("tools.catalog", {}, "catalog");
const catalogJson = JSON.stringify(catalog);
assert.match(catalogJson, /tools\.catalog/);
assert.match(catalogJson, /acp\.describe/);
assert.match(catalogJson, /acp\.initialize/);
assert.match(catalogJson, /acp\.authenticate/);
assert.match(catalogJson, /acp\.sessions\.list/);
assert.match(catalogJson, /acp\.sessions\.new/);
assert.match(catalogJson, /acp\.sessions\.load/);
assert.match(catalogJson, /acp\.sessions\.resume/);
assert.match(catalogJson, /acp\.sessions\.get/);
assert.match(catalogJson, /acp\.sessions\.messages/);
assert.match(catalogJson, /acp\.sessions\.events/);
assert.match(catalogJson, /acp\.sessions\.updates/);
assert.match(catalogJson, /acp\.sessions\.search/);
assert.match(catalogJson, /acp\.sessions\.fork/);
assert.match(catalogJson, /acp\.sessions\.cancel/);
assert.match(catalogJson, /acp\.prompt/);
assert.match(catalogJson, /execute_code/);
assert.match(catalogJson, /delegate_task/);
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
assert.match(catalogJson, /sessions\.history/);
assert.match(catalogJson, /sessions\.search/);
assert.match(catalogJson, /tasks\.list/);
assert.match(catalogJson, /tasks\.get/);
assert.match(catalogJson, /tasks\.events/);
assert.match(catalogJson, /tasks\.search/);
assert.match(catalogJson, /"runtimeTarget":"hosted"/);
assert.match(catalogJson, /"kind":"execute"/);
assert.match(catalogJson, /"approvalSensitive":true/);
assert.match(catalogJson, /"supportedOnBaremetal":false/);
assert.match(catalogJson, /"currentRuntimeSupported":true/);

const acpDescribeResult = await rpc("acp.describe", {}, "acp-describe");
assert.equal(acpDescribeResult.schemaVersion, 1);
assert.equal(acpDescribeResult.authentication.initializeMethod, "acp.initialize");
assert.equal(acpDescribeResult.authentication.authenticateMethod, "acp.authenticate");
assert.equal(acpDescribeResult.eventDelivery.mode, "poll");
assert.equal(acpDescribeResult.eventDelivery.eventsMethod, "acp.sessions.events");
assert.equal(acpDescribeResult.eventDelivery.updatesMethod, "acp.sessions.updates");
assert.equal(acpDescribeResult.eventDelivery.taskEventsMethod, "tasks.events");
assert.equal(acpDescribeResult.eventDelivery.receiptsMethod, "tasks.get");
assert.equal(acpDescribeResult.capabilities.delegateTask, true);
assert.equal(acpDescribeResult.capabilities.taskReceipts, true);
assert.equal(acpDescribeResult.capabilities.taskEvents, true);
assert.equal(acpDescribeResult.capabilities.sessionLifecycle, true);
assert.equal(acpDescribeResult.capabilities.sessionLoad, true);
assert.equal(acpDescribeResult.capabilities.sessionResume, true);
assert.equal(acpDescribeResult.capabilities.sessionMessages, true);
assert.equal(acpDescribeResult.capabilities.sessionEvents, true);
assert.equal(acpDescribeResult.capabilities.initialize, true);
assert.equal(acpDescribeResult.capabilities.authenticate, true);
assert.equal(acpDescribeResult.capabilities.sessionUpdates, true);
assert.equal(acpDescribeResult.capabilities.acpSessionSearch, true);
assert.equal(acpDescribeResult.capabilities.sessionFork, true);
assert.equal(acpDescribeResult.capabilities.sessionCancel, true);
assert.equal(acpDescribeResult.capabilities.prompt, true);
assert.equal(acpDescribeResult.sessionLifecycle.newMethod, "acp.sessions.new");
assert.equal(acpDescribeResult.sessionLifecycle.loadMethod, "acp.sessions.load");
assert.equal(acpDescribeResult.sessionLifecycle.resumeMethod, "acp.sessions.resume");
assert.equal(acpDescribeResult.sessionLifecycle.listMethod, "acp.sessions.list");
assert.equal(acpDescribeResult.sessionLifecycle.getMethod, "acp.sessions.get");
assert.equal(acpDescribeResult.sessionLifecycle.messagesMethod, "acp.sessions.messages");
assert.equal(acpDescribeResult.sessionLifecycle.eventsMethod, "acp.sessions.events");
assert.equal(acpDescribeResult.sessionLifecycle.updatesMethod, "acp.sessions.updates");
assert.equal(acpDescribeResult.sessionLifecycle.searchMethod, "acp.sessions.search");
assert.equal(acpDescribeResult.sessionLifecycle.forkMethod, "acp.sessions.fork");
assert.equal(acpDescribeResult.sessionLifecycle.cancelMethod, "acp.sessions.cancel");
assert.equal(acpDescribeResult.sessionLifecycle.promptMethod, "acp.prompt");
assert.equal(acpDescribeResult.contentBlocks.text, true);
assert.match(JSON.stringify(acpDescribeResult.tools), /tasks\.events/);
assert.match(JSON.stringify(acpDescribeResult.tools), /acp\.prompt/);

const acpInitializeResult = await rpc("acp.initialize", {}, "acp-initialize");
assert.equal(acpInitializeResult.protocolVersion, 1);
assert.equal(acpInitializeResult.runtimeTarget, "hosted");
assert.ok(acpInitializeResult.authMethodCount >= 3);
assert.match(JSON.stringify(acpInitializeResult.authMethods), /openai-api-key/);
assert.match(JSON.stringify(acpInitializeResult.authMethods), /anthropic-api-key/);
assert.match(JSON.stringify(acpInitializeResult.authMethods), /google-api-key/);

const acpAuthenticateResult = await rpc(
  "acp.authenticate",
  { methodId: "openai-api-key" },
  "acp-authenticate",
);
assert.equal(acpAuthenticateResult.ok, true);
assert.equal(acpAuthenticateResult.methodId, "openai-api-key");
assert.equal(acpAuthenticateResult.provider, "openai");
assert.equal(acpAuthenticateResult.runtimeTarget, "hosted");

const acpSessionNewResult = await rpc(
  "acp.sessions.new",
  {
    sessionId: acpSessionId,
    cwd: workRoot,
    title: "ACP Smoke Session",
  },
  "acp-session-new",
);
assert.equal(acpSessionNewResult.created, true);
assert.equal(acpSessionNewResult.session.sessionId, acpSessionId);
assert.equal(acpSessionNewResult.session.messageCount, 0);

const acpSessionLoadResult = await rpc(
  "acp.sessions.load",
  {
    sessionId: acpSessionId,
    cwd: workRoot,
  },
  "acp-session-load",
);
assert.equal(acpSessionLoadResult.loaded, true);
assert.equal(acpSessionLoadResult.session.sessionId, acpSessionId);

const acpCancelResult = await rpc(
  "acp.sessions.cancel",
  {
    sessionId: acpSessionId,
  },
  "acp-cancel",
);
assert.equal(acpCancelResult.cancelRequested, true);
assert.equal(acpCancelResult.session.cancelRequested, true);
assert.equal(acpCancelResult.session.status, "cancel_requested");

const acpPromptBlockedEnvelope = await rpcEnvelope(
  "acp.prompt",
  {
    sessionId: acpSessionId,
    content: [{ type: "text", text: "Blocked while canceled" }],
  },
  "acp-prompt-blocked",
);
assert.equal(acpPromptBlockedEnvelope.error.code, -32047);
assert.match(acpPromptBlockedEnvelope.error.message, /SessionCancelled/);

const acpSessionResumeResult = await rpc(
  "acp.sessions.resume",
  {
    sessionId: acpSessionId,
  },
  "acp-session-resume",
);
assert.equal(acpSessionResumeResult.created, false);
assert.equal(acpSessionResumeResult.session.cancelRequested, false);
assert.equal(acpSessionResumeResult.session.status, "idle");

const acpPromptResult = await rpc(
  "acp.prompt",
  {
    sessionId: acpSessionId,
    content: [{ type: "text", text: "Record a portable ACP smoke prompt" }],
  },
  "acp-prompt",
);
assert.equal(acpPromptResult.ok, true);
assert.equal(acpPromptResult.taskCount, 0);
assert.equal(acpPromptResult.session.sessionId, acpSessionId);
assert.equal(acpPromptResult.promptBlocks, 1);
assert.ok(acpPromptResult.latestEventId > 0);
assert.match(JSON.stringify(acpPromptResult.response), /Prompt recorded in the ACP session/);

const acpEventsResult = await rpc(
  "acp.sessions.events",
  {
    sessionId: acpSessionId,
    limit: 20,
  },
  "acp-events",
);
assert.equal(acpEventsResult.count, 6);
assert.ok(acpEventsResult.cursor > 0);
assert.match(JSON.stringify(acpEventsResult.items), /session\.resume/);
assert.match(JSON.stringify(acpEventsResult.items), /message\.user/);
assert.match(JSON.stringify(acpEventsResult.items), /message\.assistant/);

const acpUpdatesResult = await rpc(
  "acp.sessions.updates",
  {
    sessionId: acpSessionId,
    limit: 20,
  },
  "acp-updates",
);
assert.equal(acpUpdatesResult.count, 6);
assert.ok(acpUpdatesResult.cursor > 0);
assert.match(JSON.stringify(acpUpdatesResult.items), /"type":"message"/);
assert.match(JSON.stringify(acpUpdatesResult.items), /message\.assistant/);

const acpSearchResult = await rpc(
  "acp.sessions.search",
  {
    query: "portable ACP smoke prompt",
    limit: 10,
  },
  "acp-search",
);
assert.ok(acpSearchResult.count >= 1);
assert.match(JSON.stringify(acpSearchResult.items), new RegExp(acpSessionId));

const acpMessagesResult = await rpc(
  "acp.sessions.messages",
  {
    sessionId: acpSessionId,
    limit: 10,
  },
  "acp-messages",
);
assert.equal(acpMessagesResult.count, 2);
assert.equal(acpMessagesResult.items[0].role, "user");
assert.equal(acpMessagesResult.items[1].role, "assistant");
const acpForkResult = await rpc(
  "acp.sessions.fork",
  {
    sourceSessionId: acpSessionId,
    newSessionId: acpForkSessionId,
  },
  "acp-fork",
);
assert.equal(acpForkResult.clonedMessages, 2);
assert.equal(acpForkResult.session.sessionId, acpForkSessionId);
assert.equal(acpForkResult.session.sourceSessionId, acpSessionId);

const acpGetResult = await rpc(
  "acp.sessions.get",
  {
    sessionId: acpForkSessionId,
  },
  "acp-get",
);
assert.equal(acpGetResult.session.sessionId, acpForkSessionId);
assert.equal(acpGetResult.session.messageCount, 2);
assert.equal(acpGetResult.session.sourceSessionId, acpSessionId);

const acpListResult = await rpc(
  "acp.sessions.list",
  {
    limit: 10,
  },
  "acp-list",
);
assert.ok(acpListResult.count >= 2);
assert.match(JSON.stringify(acpListResult.items), new RegExp(acpSessionId));
assert.match(JSON.stringify(acpListResult.items), new RegExp(acpForkSessionId));

const acpDelegatePromptResult = await rpc(
  "acp.prompt",
  {
    sessionId: acpDelegateSessionId,
    goal: "ACP delegated smoke file flow",
    prompt: "Write and read through ACP prompt",
    toolsets: ["file"],
    steps: [
      { tool: "file.write", path: acpDelegateFilePath, content: "acp-smoke-data" },
      { tool: "file.read", path: acpDelegateFilePath },
    ],
  },
  "acp-prompt-delegate",
);
assert.equal(acpDelegatePromptResult.ok, true);
assert.equal(acpDelegatePromptResult.taskCount, 1);
assert.equal(acpDelegatePromptResult.tasks[0].status, "completed");
assert.ok(acpDelegatePromptResult.tasks[0].eventCount >= 6);
const acpDelegateTaskId = acpDelegatePromptResult.tasks[0].taskId;
assert.match(acpDelegateTaskId, /^delegate-task-/);

const acpDelegateReadResult = await rpc(
  "file.read",
  {
    sessionId: acpDelegateSessionId,
    path: acpDelegateFilePath,
  },
  "acp-delegate-read",
);
assert.match(acpDelegateReadResult.content, /acp-smoke-data/);

const acpDelegateMessagesResult = await rpc(
  "acp.sessions.messages",
  {
    sessionId: acpDelegateSessionId,
    limit: 10,
  },
  "acp-delegate-messages",
);
assert.equal(acpDelegateMessagesResult.count, 2);
assert.match(JSON.stringify(acpDelegateMessagesResult.items), /task_summary/);

const acpDelegateEventsResult = await rpc(
  "acp.sessions.events",
  {
    sessionId: acpDelegateSessionId,
    limit: 20,
  },
  "acp-delegate-events",
);
assert.equal(acpDelegateEventsResult.count, 8);
assert.ok(acpDelegateEventsResult.cursor > 0);
assert.match(JSON.stringify(acpDelegateEventsResult.items), /task\.start/);
assert.match(JSON.stringify(acpDelegateEventsResult.items), /message\.task_summary/);

const acpDelegateUpdatesResult = await rpc(
  "acp.sessions.updates",
  {
    sessionId: acpDelegateSessionId,
    limit: 20,
  },
  "acp-delegate-updates",
);
assert.equal(acpDelegateUpdatesResult.count, 8);
assert.match(JSON.stringify(acpDelegateUpdatesResult.items), /message\.task_summary/);

const approvalsAllowResult = await rpc(
  "exec.approvals.set",
  {
    mode: "allow",
  },
  "approvals-allow",
);
assert.equal(approvalsAllowResult.approvals.mode, "allow");

const approvalPromptModeResult = await rpc(
  "exec.approvals.node.set",
  {
    nodeId: approvalPromptNodeId,
    mode: "prompt",
  },
  "approvals-node-prompt",
);
assert.equal(approvalPromptModeResult.approvals.mode, "prompt");

const approvalRequiredResult = await rpc(
  "execute_code",
  {
    sessionId,
    nodeId: approvalPromptNodeId,
    language: "javascript",
    runtimePath: nodeBinary,
    cwd: workRoot,
    code: 'console.log("approval-required-js")',
  },
  "approval-required",
);
assert.equal(approvalRequiredResult.ok, false);
assert.equal(approvalRequiredResult.state, "approval_required");
assert.equal(approvalRequiredResult.approval.mode, "prompt");
assert.match(approvalRequiredResult.approval.reason, /Approval required/);
const approvalId = approvalRequiredResult.approval.approvalId;
assert.match(approvalId, /^approval-/);

const approvalPendingResult = await rpc(
  "exec.approval.waitDecision",
  {
    approvalId,
    timeoutMs: 10,
  },
  "approval-wait",
);
assert.equal(approvalPendingResult.approval.status, "pending");

const approvalResolvedResult = await rpc(
  "exec.approval.resolve",
  {
    approvalId,
    status: "approved",
  },
  "approval-resolve",
);
assert.equal(approvalResolvedResult.approval.status, "approved");

const approvalGrantedResult = await rpc(
  "execute_code",
  {
    sessionId,
    nodeId: approvalPromptNodeId,
    approvalId,
    language: "javascript",
    runtimePath: nodeBinary,
    cwd: workRoot,
    code: 'console.log("approval-granted-js")',
  },
  "approval-granted",
);
assert.equal(approvalGrantedResult.ok, true);
assert.match(approvalGrantedResult.stdout, /approval-granted-js/);

const approvalDenyModeResult = await rpc(
  "exec.approvals.node.set",
  {
    nodeId: approvalDenyNodeId,
    mode: "deny",
  },
  "approvals-node-deny",
);
assert.equal(approvalDenyModeResult.approvals.mode, "deny");

const approvalDeniedResult = await rpc(
  "process.start",
  {
    sessionId,
    nodeId: approvalDenyNodeId,
    cwd: workRoot,
    command: "printf denied-should-not-run",
  },
  "approval-denied",
);
assert.equal(approvalDeniedResult.ok, false);
assert.equal(approvalDeniedResult.state, "approval_denied");

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

const delegateTaskSessionId = `${sessionId}-delegate`;
const delegateTaskResult = await rpc(
  "delegate_task",
  {
    goal: "delegate file flow",
    sessionId: delegateTaskSessionId,
    toolsets: ["file"],
    steps: [
      { tool: "file.write", path: delegateFilePath, content: "delegate-needle" },
      { tool: "file.search", path: workRoot, query: "delegate-needle", maxResults: 5 },
      { tool: "file.patch", path: delegateFilePath, oldText: "delegate-needle", newText: "delegate-patched" },
      { tool: "file.read", path: delegateFilePath },
    ],
  },
  "delegate-task",
);
assert.equal(delegateTaskResult.ok, true);
assert.equal(delegateTaskResult.kind, "delegate_task");
assert.equal(delegateTaskResult.count, 1);
assert.equal(delegateTaskResult.results[0].status, "completed");
assert.equal(delegateTaskResult.results[0].successCount, 4);
assert.match(JSON.stringify(delegateTaskResult.results[0].events), /task\.start/);
assert.match(JSON.stringify(delegateTaskResult.results[0].events), /delegate file flow/);
assert.match(JSON.stringify(delegateTaskResult.results[0].events), /tool\.call\.start/);
assert.match(JSON.stringify(delegateTaskResult.results[0].steps), /delegate-patched/);
const delegateTaskId = delegateTaskResult.results[0].taskId;
assert.match(delegateTaskId, /^delegate-task-/);

const taskListResult = await rpc(
  "tasks.list",
  {
    sessionId: delegateTaskSessionId,
    limit: 10,
  },
  "task-list",
);
assert.equal(taskListResult.count, 1);
assert.equal(taskListResult.items[0].taskId, delegateTaskId);
assert.equal(taskListResult.items[0].eventCount, 10);

const taskGetResult = await rpc(
  "tasks.get",
  {
    taskId: delegateTaskId,
  },
  "task-get",
);
assert.equal(taskGetResult.task.taskId, delegateTaskId);
assert.equal(taskGetResult.task.status, "completed");
assert.equal(taskGetResult.task.eventCount, 10);
assert.equal(taskGetResult.latestEventId > 0, true);
assert.match(taskGetResult.task.goal, /delegate file flow/);

const taskEventsResult = await rpc(
  "tasks.events",
  {
    taskId: delegateTaskId,
    limit: 20,
  },
  "task-events",
);
assert.equal(taskEventsResult.count, 10);
assert.equal(taskEventsResult.items[0].taskId, delegateTaskId);
assert.equal(taskEventsResult.cursor > 0, true);
assert.match(JSON.stringify(taskEventsResult.items), /task\.start/);
assert.match(JSON.stringify(taskEventsResult.items), /task\.complete/);
assert.match(JSON.stringify(taskEventsResult.items), /delegate-patched/);

const taskSearchResult = await rpc(
  "tasks.search",
  {
    query: "delegate file flow",
    sessionId: delegateTaskSessionId,
    limit: 5,
  },
  "task-search",
);
assert.equal(taskSearchResult.count, 1);
assert.equal(taskSearchResult.items[0].taskId, delegateTaskId);

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

let executeCodeJsResult = null;
let executeCodeJsArtifactRead = null;
let executeCodeZigResult = null;
let processListResult = null;
let processWaitResult = null;
let processKillWaitResult = null;
let delegateTaskApprovalResult = null;

if (requireHostedProcessSupport) {
  assert.ok(zigBinary, "ZAR_ZIG_BIN is required for execute_code zig smoke");

  executeCodeJsResult = await rpc(
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

  executeCodeJsArtifactRead = await rpc(
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

  executeCodeZigResult = await rpc(
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

  delegateTaskApprovalResult = await rpc(
    "delegate_task",
    {
      goal: "delegate approval flow",
      sessionId: `${sessionId}-delegate-approval`,
      toolsets: ["terminal"],
      steps: [
        {
          tool: "execute_code",
          nodeId: approvalPromptNodeId,
          language: "javascript",
          runtimePath: nodeBinary,
          cwd: workRoot,
          code: 'console.log("delegate-approval-js")',
        },
      ],
    },
    "delegate-task-approval",
  );
  assert.equal(delegateTaskApprovalResult.ok, false);
  assert.equal(delegateTaskApprovalResult.kind, "delegate_task");
  assert.equal(delegateTaskApprovalResult.results[0].status, "blocked");
  assert.equal(delegateTaskApprovalResult.results[0].approvalRequiredCount, 1);
  assert.equal(delegateTaskApprovalResult.results[0].steps[0].state, "approval_required");
  assert.match(JSON.stringify(delegateTaskApprovalResult.results[0].events), /task\.start/);
  assert.match(JSON.stringify(delegateTaskApprovalResult.results[0].events), /delegate approval flow/);

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

  processListResult = await rpc(
    "process.list",
    {
      sessionId,
    },
    "process-list",
  );
  assert.equal(processListResult.ok, true);
  assert.ok(processListResult.count >= 1);
  assert.match(JSON.stringify(processListResult.items), new RegExp(processStartResult.processId));

  processWaitResult = await rpc(
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

  processKillWaitResult = await rpc(
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
}

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
      "tools.catalog",
      "acp.describe",
      "acp.initialize",
      "acp.authenticate",
      "acp.sessions.list",
      "acp.sessions.new",
      "acp.sessions.load",
      "acp.sessions.resume",
      "acp.sessions.get",
      "acp.sessions.messages",
      "acp.sessions.events",
      "acp.sessions.updates",
      "acp.sessions.search",
      "acp.sessions.fork",
      "acp.sessions.cancel",
      "acp.prompt",
      "execute_code",
      "delegate_task",
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
      "sessions.history",
      "sessions.search",
      "tasks.list",
      "tasks.get",
      "tasks.events",
      "tasks.search",
    ],
    toolsCatalogRuntimeTarget: catalog.runtimeTarget,
    toolsCatalogHasKinds: /"kind":"execute"/.test(catalogJson),
    toolsCatalogHasApprovalMetadata: /"approvalSensitive":true/.test(catalogJson),
    toolsCatalogHasBaremetalMetadata: /"supportedOnBaremetal":false/.test(catalogJson),
    toolsCatalogHasCurrentRuntimeMetadata: /"currentRuntimeSupported":true/.test(catalogJson),
    acpDescribeSchemaVersion: acpDescribeResult.schemaVersion,
    acpDescribeInitializeMethod: acpDescribeResult.authentication.initializeMethod,
    acpDescribeAuthenticateMethod: acpDescribeResult.authentication.authenticateMethod,
    acpDescribeEventsMethod: acpDescribeResult.eventDelivery.eventsMethod,
    acpDescribeUpdatesMethod: acpDescribeResult.eventDelivery.updatesMethod,
    acpDescribeTaskEventsMethod: acpDescribeResult.eventDelivery.taskEventsMethod,
    acpDescribeReceiptsMethod: acpDescribeResult.eventDelivery.receiptsMethod,
    acpDescribeTaskReceipts: acpDescribeResult.capabilities.taskReceipts,
    acpDescribeTaskEvents: acpDescribeResult.capabilities.taskEvents,
    acpDescribeSessionNewMethod: acpDescribeResult.sessionLifecycle.newMethod,
    acpDescribeSessionLoadMethod: acpDescribeResult.sessionLifecycle.loadMethod,
    acpDescribeSessionResumeMethod: acpDescribeResult.sessionLifecycle.resumeMethod,
    acpDescribeSessionEventsMethod: acpDescribeResult.sessionLifecycle.eventsMethod,
    acpDescribeSessionUpdatesMethod: acpDescribeResult.sessionLifecycle.updatesMethod,
    acpDescribeSessionSearchMethod: acpDescribeResult.sessionLifecycle.searchMethod,
    acpDescribeSessionCancelMethod: acpDescribeResult.sessionLifecycle.cancelMethod,
    acpDescribePromptMethod: acpDescribeResult.sessionLifecycle.promptMethod,
    acpDescribeSessionLifecycle: acpDescribeResult.capabilities.sessionLifecycle,
    acpDescribeSessionEvents: acpDescribeResult.capabilities.sessionEvents,
    acpDescribeInitialize: acpDescribeResult.capabilities.initialize,
    acpDescribeAuthenticate: acpDescribeResult.capabilities.authenticate,
    acpDescribeSessionUpdates: acpDescribeResult.capabilities.sessionUpdates,
    acpDescribeAcpSessionSearch: acpDescribeResult.capabilities.acpSessionSearch,
    acpSessionCreated: acpSessionNewResult.created,
    acpInitializeAuthMethodCount: acpInitializeResult.authMethodCount,
    acpAuthenticateMethodId: acpAuthenticateResult.methodId,
    acpAuthenticateProvider: acpAuthenticateResult.provider,
    acpAuthenticateOk: acpAuthenticateResult.ok,
    acpAuthenticateAuthenticated: acpAuthenticateResult.authenticated,
    acpSessionLoaded: acpSessionLoadResult.loaded,
    acpCancelRequested: acpCancelResult.cancelRequested,
    acpBlockedCode: acpPromptBlockedEnvelope.error.code,
    acpResumeCreated: acpSessionResumeResult.created,
    acpEventsCount: acpEventsResult.count,
    acpEventsCursor: acpEventsResult.cursor,
    acpUpdatesCount: acpUpdatesResult.count,
    acpUpdatesCursor: acpUpdatesResult.cursor,
    acpPromptLatestEventId: acpPromptResult.latestEventId,
    acpMessagesCount: acpMessagesResult.count,
    acpSearchCount: acpSearchResult.count,
    acpForkClonedMessages: acpForkResult.clonedMessages,
    acpListCount: acpListResult.count,
    acpPromptTaskCount: acpPromptResult.taskCount,
    acpDelegateTaskId,
    acpDelegateTaskCount: acpDelegatePromptResult.taskCount,
    acpDelegateMessagesCount: acpDelegateMessagesResult.count,
    acpDelegateEventsCount: acpDelegateEventsResult.count,
    acpDelegateUpdatesCount: acpDelegateUpdatesResult.count,
    globalApprovalMode: approvalsAllowResult.approvals.mode,
    approvalPromptState: approvalRequiredResult.state,
    approvalApprovedOk: approvalGrantedResult.ok,
    approvalDeniedState: approvalDeniedResult.state,
    hostedProcessSupportRequired: requireHostedProcessSupport,
    executeCodeJsOk: executeCodeJsResult?.ok ?? null,
    executeCodeZigOk: executeCodeZigResult?.ok ?? null,
    executeCodeJsArtifact: executeCodeJsArtifactRead?.content ?? null,
    delegateTaskOk: delegateTaskResult.ok,
    delegateTaskId,
    delegateTaskStepCount: delegateTaskResult.results[0]?.steps?.length ?? null,
    delegateTaskEventCount: delegateTaskResult.results[0]?.events?.length ?? null,
    delegateTaskApprovalState: delegateTaskApprovalResult?.results?.[0]?.steps?.[0]?.state ?? null,
    taskListCount: taskListResult.count,
    taskGetLatestEventId: taskGetResult.latestEventId,
    taskEventsCount: taskEventsResult.count,
    taskEventsCursor: taskEventsResult.cursor,
    taskSearchCount: taskSearchResult.count,
    fileWrite: writeResult.ok,
    fileSearchCount: searchResult.count,
    filePatchApplied: patchResult.applied,
    webSearchCount: webSearchResult.count,
    webExtractCount: webExtractResult.count,
    processListCount: processListResult?.count ?? null,
    processExitCode: processWaitResult?.exitCode ?? null,
    processKillExitCode: processKillWaitResult?.exitCode ?? null,
    sessionHistoryCount: historyResult.count,
    sessionSearchCount: sessionSearchResult.count,
  },
}, null, 2));
}
finally {
  await mockWeb.close();
}
