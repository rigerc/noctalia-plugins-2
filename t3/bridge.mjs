#!/usr/bin/env node
/**
 * T3 Monitor bridge.
 *
 * Speaks T3 Code's orchestration WebSocket RPC and prints one NDJSON event per
 * line on stdout. Dependency-free: Node 22+ (`fetch`, global `WebSocket`).
 *
 * Events (one JSON object per line):
 *   {"type":"snapshot","scope":"full","projects":[...],"threads":[...],"sequence":N,"at":MS}
 *   {"type":"snapshot","scope":"projects","projects":[...],"sequence":N,"at":MS}
 *   {"type":"thread.updated","thread":{...},"at":MS}
 *   {"type":"thread.removed","threadId":"...","at":MS}
 *   {"type":"project.updated","project":{...},"at":MS}
 *   {"type":"project.removed","projectId":"...","at":MS}
 *   {"type":"health","state":"connecting|connected|offline","reason":"...","error":"...","at":MS}
 *   {"type":"heartbeat","at":MS}
 *
 * The bridge never writes to T3: it mints a short-lived WebSocket ticket from a
 * read-only bearer token and subscribes to the orchestration shell.
 *
 * `--replay <frames.ndjson>` replays recorded WebSocket frames through the same
 * projection and exits, so tests need neither T3 nor the network.
 */

import { closeSync, openSync, readFileSync, readlinkSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

const ORCHESTRATION_PROTOCOL = 2;
const SUBSCRIBE_SHELL = "orchestration.subscribeShell";
const HEARTBEAT_MS = 15_000;
const FIRST_SNAPSHOT_TIMEOUT_MS = 30_000;
const BACKOFF_MIN_MS = 5_000;
const BACKOFF_MAX_MS = 120_000;

let replaying = false;
const now = () => (replaying ? 0 : Date.now());

function emit(event) {
  process.stdout.write(JSON.stringify(event) + "\n");
}

function health(state, fields = {}) {
  emit({ type: "health", state, at: now(), ...fields });
}

function parseArgs(argv) {
  const options = {
    home: process.env.T3CODE_HOME || path.join(homedir(), ".t3"),
    tokenFile: null,
    lockFile: null,
    replay: null,
    once: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    switch (flag) {
      case "--home":
        options.home = value;
        index += 1;
        break;
      case "--token-file":
        options.tokenFile = value;
        index += 1;
        break;
      case "--lock-file":
        options.lockFile = value;
        index += 1;
        break;
      case "--replay":
        options.replay = value;
        index += 1;
        break;
      case "--once":
        options.once = true;
        break;
      case "--help":
      case "-h":
        process.stdout.write(
          "usage: bridge.mjs [--home DIR] [--token-file FILE] [--lock-file FILE] [--replay FRAMES] [--once]\n",
        );
        process.exit(0);
        break;
      default:
        break;
    }
  }
  return options;
}

/** Keep only the fields the monitor renders. Keeps lines small and stable. */
function toThread(shell) {
  const request = shell.pendingRuntimeRequest ?? null;
  return {
    id: shell.id,
    projectId: shell.projectId,
    title: typeof shell.title === "string" ? shell.title : "",
    status: typeof shell.status === "string" ? shell.status : "idle",
    provider: shell.providerInstanceId ?? null,
    model: shell.modelSelection?.model ?? null,
    parentId: shell.lineage?.parentThreadId ?? null,
    relationship: shell.lineage?.relationshipToParent ?? null,
    pendingRequest: request
      ? {
          id: request.id ?? null,
          kind: request.kind ?? null,
          createdAt: request.createdAt ?? null,
          // Absent from older servers, where every request blocked the run.
          blocking: request.blocking !== false,
        }
      : null,
    latestRunId: shell.latestRunId ?? null,
    latestRunStartedAt: shell.latestRunStartedAt ?? shell.activityRunStartedAt ?? null,
    latestRunCompletedAt: shell.latestRunCompletedAt ?? null,
    updatedAt: shell.updatedAt ?? null,
    archivedAt: shell.archivedAt ?? null,
  };
}

function toProject(shell) {
  return {
    id: shell.id,
    title: typeof shell.title === "string" ? shell.title : "",
  };
}

/**
 * Convert `orchestration.subscribeShell` stream items into bridge events.
 * A cold subscribe sends two `snapshot` items: the authoritative shell, then a
 * project-metadata refresh that carries `threads: []`. Only the first snapshot
 * on a connection is authoritative; later empty ones merge project metadata.
 */
function createProjector() {
  let sawAuthoritativeSnapshot = false;
  return function eventsForItem(item) {
    const at = now();
    switch (item?.kind) {
      case "snapshot": {
        const snapshot = item.snapshot ?? {};
        const threads = Array.isArray(snapshot.threads) ? snapshot.threads : [];
        const projects = Array.isArray(snapshot.projects) ? snapshot.projects : [];
        const full = !sawAuthoritativeSnapshot || threads.length > 0;
        if (full) sawAuthoritativeSnapshot = true;
        return [
          {
            type: "snapshot",
            scope: full ? "full" : "projects",
            projects: projects.map(toProject),
            threads: threads.map(toThread),
            sequence: snapshot.snapshotSequence ?? null,
            at,
          },
        ];
      }
      case "thread.updated": {
        const shell = item.thread;
        if (!shell || typeof shell.id !== "string") return [];
        // Archived threads leave the active shell; treat that as a removal.
        if (item.location === "archive" || shell.archivedAt) {
          return [{ type: "thread.removed", threadId: shell.id, at }];
        }
        return [{ type: "thread.updated", thread: toThread(shell), at }];
      }
      case "thread.removed":
        return typeof item.threadId === "string"
          ? [{ type: "thread.removed", threadId: item.threadId, at }]
          : [];
      case "project.updated":
        return item.project?.id
          ? [{ type: "project.updated", project: toProject(item.project), at }]
          : [];
      case "project.removed":
        return typeof item.projectId === "string"
          ? [{ type: "project.removed", projectId: item.projectId, at }]
          : [];
      case "synchronized":
        return [];
      default:
        return [];
    }
  };
}

/** Handle one decoded WebSocket frame. Returns `{fatal, reason}` when fatal. */
function handleFrame(frame, project) {
  if (!frame || typeof frame !== "object") return { fatal: true, reason: "malformed" };
  switch (frame._tag) {
    case "Chunk": {
      const values = Array.isArray(frame.values) ? frame.values : [];
      let sawSnapshot = false;
      for (const item of values) {
        if (item?.kind === "snapshot") sawSnapshot = true;
        for (const event of project(item)) emit(event);
      }
      return { fatal: false, sawSnapshot };
    }
    case "Ping":
      return { fatal: false, pong: true };
    case "Pong":
      return { fatal: false };
    case "Exit": {
      if (frame.exit?._tag === "Success") return { fatal: false };
      const failure = Array.isArray(frame.exit?.cause)
        ? frame.exit.cause.find((entry) => entry?._tag === "Fail")?.error
        : null;
      const message =
        (failure && (failure.message || failure._tag)) ||
        (typeof frame.exit?.cause === "string" ? frame.exit.cause : null) ||
        "T3 rejected the shell subscription";
      return { fatal: true, reason: "subscription-failed", error: String(message) };
    }
    case "Defect":
      return {
        fatal: true,
        reason: "protocol",
        error: String(frame.defect?.message ?? frame.defect ?? "protocol defect"),
      };
    default:
      return { fatal: false };
  }
}

function readToken(file) {
  let contents;
  try {
    contents = readFileSync(file, "utf8");
  } catch (error) {
    const failure = new Error(`Cannot read the T3 token file: ${file}`);
    failure.reason = error.code === "ENOENT" ? "token-missing" : "token-unreadable";
    throw failure;
  }
  const token = contents.trim();
  if (token === "") {
    const failure = new Error(`The T3 token file is empty: ${file}`);
    failure.reason = "token-missing";
    throw failure;
  }
  return token;
}

function tokenWarning(file) {
  try {
    const mode = statSync(file).mode & 0o777;
    if ((mode & 0o077) !== 0) {
      return `token file ${file} is readable by other users (mode ${mode.toString(8)}); run: chmod 600 ${file}`;
    }
  } catch {
    // A missing file already surfaced through readToken.
  }
  return null;
}

function readRuntime(home) {
  const file = path.join(home, "userdata", "server-runtime.json");
  let runtime;
  try {
    runtime = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    const failure = new Error(
      error.code === "ENOENT"
        ? `T3 Code is not running: ${file} is missing`
        : `Cannot read ${file}: ${error.message}`,
    );
    failure.reason = error.code === "ENOENT" ? "runtime-missing" : "runtime-unreadable";
    throw failure;
  }
  if (typeof runtime?.origin !== "string" || runtime.origin === "") {
    const failure = new Error(`${file} has no origin`);
    failure.reason = "runtime-unreadable";
    throw failure;
  }
  return runtime;
}

async function fetchTicket(origin, token) {
  const response = await fetch(`${origin}/api/auth/websocket-ticket`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: "{}",
  });
  if (response.status === 401 || response.status === 403) {
    const failure = new Error(
      "T3 rejected the token. Mint a new one with: t3 auth session issue --scope orchestration:read --ttl 30d --token-only",
    );
    failure.reason = "unauthorized";
    throw failure;
  }
  if (!response.ok) {
    const failure = new Error(`T3 ticket request failed with HTTP ${response.status}`);
    failure.reason = "unreachable";
    throw failure;
  }
  const body = await response.json().catch(() => null);
  if (typeof body?.ticket !== "string" || body.ticket === "") {
    const failure = new Error("T3 returned no WebSocket ticket");
    failure.reason = "protocol";
    throw failure;
  }
  return body.ticket;
}

function websocketUrl(origin, ticket) {
  const url = new URL(origin);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/ws";
  url.search = "";
  url.searchParams.set("orchestrationProtocol", String(ORCHESTRATION_PROTOCOL));
  url.searchParams.set("wsTicket", ticket);
  return url.toString();
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** One connection. Resolves with a health reason when the socket ends. */
function streamOnce(origin, ticket, options) {
  return new Promise((resolve) => {
    const project = createProjector();
    let socket;
    try {
      socket = new WebSocket(websocketUrl(origin, ticket));
    } catch (error) {
      resolve({ reason: "unreachable", error: String(error.message ?? error) });
      return;
    }
    let settled = false;
    let sawSnapshot = false;
    const settle = (result) => {
      if (settled) return;
      settled = true;
      clearInterval(heartbeat);
      clearTimeout(snapshotTimeout);
      try {
        socket.close();
      } catch {
        // Already closed.
      }
      resolve(result);
    };
    const heartbeat = setInterval(() => emit({ type: "heartbeat", at: now() }), HEARTBEAT_MS);
    const snapshotTimeout = setTimeout(() => {
      settle({ reason: "stalled", error: "T3 sent no shell snapshot within 30 seconds" });
    }, FIRST_SNAPSHOT_TIMEOUT_MS);

    socket.addEventListener("open", () => {
      health("connected", options.warning ? { warning: options.warning } : {});
      socket.send(
        JSON.stringify({
          _tag: "Request",
          id: 1,
          tag: SUBSCRIBE_SHELL,
          payload: {},
          headers: [],
        }),
      );
    });
    socket.addEventListener("message", (message) => {
      let frame;
      try {
        frame = JSON.parse(String(message.data));
      } catch {
        settle({ reason: "protocol", error: "T3 sent a frame that is not JSON" });
        return;
      }
      const result = handleFrame(frame, project);
      if (result.pong) {
        socket.send(JSON.stringify({ _tag: "Pong" }));
        return;
      }
      if (result.fatal) {
        settle({ reason: result.reason, error: result.error });
        return;
      }
      if (result.sawSnapshot) {
        sawSnapshot = true;
        clearTimeout(snapshotTimeout);
      }
    });
    socket.addEventListener("error", () => {
      // `close` always follows; the close handler reports the state change.
    });
    socket.addEventListener("close", (event) => {
      settle({
        reason: "disconnected",
        error: `T3 closed the WebSocket (${event.code}${event.reason ? `: ${event.reason}` : ""})`,
      });
    });
  });
}

async function replay(file) {
  replaying = true;
  const project = createProjector();
  const lines = readFileSync(file, "utf8").split("\n");
  for (const line of lines) {
    if (line.trim() === "") continue;
    let frame;
    try {
      frame = JSON.parse(line);
    } catch {
      health("offline", { reason: "protocol", error: "fixture line is not JSON" });
      return 1;
    }
    const result = handleFrame(frame, project);
    if (result.fatal) {
      health("offline", { reason: result.reason, error: result.error });
      return 1;
    }
  }
  return 0;
}

/** Kill a previous bridge left behind by a hot reload. */
function takeLock(file) {
  if (!file) return null;
  try {
    const pid = Number.parseInt(readFileSync(file, "utf8").trim(), 10);
    if (Number.isInteger(pid) && pid > 0 && pid !== process.pid) {
      const commandLine = readFileSync(`/proc/${pid}/cmdline`, "utf8");
      if (commandLine.includes("bridge.mjs")) {
        try {
          process.kill(pid, "SIGTERM");
        } catch {
          // Already gone.
        }
      }
    }
  } catch {
    // No previous lock, or no /proc: nothing to stop.
  }
  try {
    writeFileSync(file, String(process.pid), { mode: 0o600 });
  } catch {
    // A lock file is a convenience; keep running without it.
  }
  return file;
}

function releaseLock(file) {
  if (!file) return;
  try {
    if (readFileSync(file, "utf8").trim() === String(process.pid)) unlinkSync(file);
  } catch {
    // Nothing to release.
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));

  if (options.replay) {
    process.exitCode = await replay(options.replay);
    return;
  }

  if (typeof WebSocket !== "function" || typeof fetch !== "function") {
    health("offline", {
      reason: "node-too-old",
      error: `Node 22 or newer is required (running ${process.version})`,
    });
    process.exitCode = 1;
    return;
  }

  if (!options.tokenFile) {
    health("offline", { reason: "token-missing", error: "No token file is configured" });
    process.exitCode = 1;
    return;
  }

  const lock = takeLock(options.lockFile);
  let stopping = false;
  const stop = () => {
    stopping = true;
    releaseLock(lock);
    process.exit(0);
  };
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
  // Noctalia closes the stream's stdin when the plugin stops. Do not mistake an
  // inherited /dev/null (shells, tests) for that signal.
  let stdinIsDevNull = false;
  try {
    stdinIsDevNull = readlinkSync("/proc/self/fd/0") === "/dev/null";
  } catch {
    stdinIsDevNull = false;
  }
  if (!stdinIsDevNull) {
    process.stdin.on("end", stop);
    process.stdin.on("close", stop);
    process.stdin.resume();
  }

  let backoff = BACKOFF_MIN_MS;
  while (!stopping) {
    health("connecting");
    let result;
    try {
      const token = readToken(options.tokenFile);
      const runtime = readRuntime(options.home);
      const ticket = await fetchTicket(runtime.origin, token);
      const warning = tokenWarning(options.tokenFile);
      result = await streamOnce(runtime.origin, ticket, { warning });
      backoff = BACKOFF_MIN_MS;
    } catch (error) {
      result = { reason: error.reason ?? "unreachable", error: String(error.message ?? error) };
    }
    if (stopping) break;
    health("offline", { reason: result.reason, error: result.error });
    if (options.once) break;
    await sleep(backoff);
    backoff = Math.min(BACKOFF_MAX_MS, backoff * 2);
  }
  releaseLock(lock);
}

main().catch((error) => {
  health("offline", { reason: "internal", error: String(error?.stack ?? error) });
  process.exitCode = 1;
});
