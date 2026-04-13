import { execFile } from "node:child_process";
import { promisify } from "node:util";
import {
  EXCLUDED_PORTS,
  FRONTEND_HINTS,
  GENERIC_DEV_HINTS,
  IGNORE_COMMAND_HINTS,
  NODE_BACKEND_HINTS,
  PYTHON_SERVER_HINTS,
  TYPICAL_DEV_PORTS
} from "./config.js";

const execFileAsync = promisify(execFile);

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runCommand(file, args) {
  const { stdout } = await execFileAsync(file, args, {
    maxBuffer: 10 * 1024 * 1024
  });

  return stdout;
}

function parseSocketName(rawName) {
  if (!rawName) {
    return null;
  }

  const value = rawName.trim();

  let host = null;
  let port = null;

  if (value.startsWith("[")) {
    const match = value.match(/^\[([^\]]+)\]:(\d+)$/);
    if (!match) {
      return null;
    }
    host = match[1];
    port = Number(match[2]);
  } else {
    const lastColon = value.lastIndexOf(":");
    if (lastColon === -1) {
      return null;
    }
    host = value.slice(0, lastColon);
    port = Number(value.slice(lastColon + 1));
  }

  if (!Number.isInteger(port)) {
    return null;
  }

  const normalizedHost = host === "*" || host === "::" ? "0.0.0.0" : host;
  const address =
    normalizedHost === "127.0.0.1" ||
    normalizedHost === "::1" ||
    normalizedHost === "localhost"
      ? "localhost"
      : normalizedHost;

  return {
    raw: value,
    host: normalizedHost,
    address,
    port
  };
}

function parseLsofListeners(output) {
  const processes = new Map();
  let currentPid = null;

  // `lsof -F` devuelve un stream de campos: `p` abre un proceso y los `n`
  // siguientes pertenecen a sus file descriptors. Aquí solo retenemos sockets
  // TCP en escucha y descartamos puertos reservados del propio dashboard.
  for (const line of output.split("\n")) {
    if (!line) {
      continue;
    }

    const field = line[0];
    const value = line.slice(1);

    if (field === "p") {
      currentPid = Number(value);
      if (!Number.isInteger(currentPid)) {
        currentPid = null;
        continue;
      }
      if (!processes.has(currentPid)) {
        processes.set(currentPid, {
          pid: currentPid,
          name: null,
          sockets: []
        });
      }
      continue;
    }

    if (!currentPid || !processes.has(currentPid)) {
      continue;
    }

    const processInfo = processes.get(currentPid);

    if (field === "c") {
      processInfo.name = value || processInfo.name;
      continue;
    }

    if (field !== "n") {
      continue;
    }

    const socket = parseSocketName(value);

    if (!socket || EXCLUDED_PORTS.has(socket.port)) {
      continue;
    }

    const alreadyTracked = processInfo.sockets.some(
      (item) => item.port === socket.port && item.host === socket.host
    );

    if (!alreadyTracked) {
      processInfo.sockets.push(socket);
    }
  }

  return new Map(
    [...processes.entries()].filter(([, processInfo]) => processInfo.sockets.length > 0)
  );
}

function parsePsOutput(output) {
  const details = new Map();

  // En macOS `ps` no expone JSON, así que separamos las primeras columnas fijas
  // y dejamos el resto de la línea como comando completo.
  for (const line of output.split("\n")) {
    if (!line.trim()) {
      continue;
    }

    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$/);
    if (!match) {
      continue;
    }

    const [, pid, ppid, user, etime, args] = match;

    details.set(Number(pid), {
      pid: Number(pid),
      ppid: Number(ppid),
      user,
      etime,
      command: args.trim()
    });
  }

  return details;
}

function parseCwdOutput(output) {
  const cwdMap = new Map();
  let currentPid = null;

  for (const line of output.split("\n")) {
    if (!line) {
      continue;
    }

    const field = line[0];
    const value = line.slice(1);

    if (field === "p") {
      currentPid = Number(value);
      continue;
    }

    if (field === "n" && currentPid) {
      cwdMap.set(currentPid, value.trim());
    }
  }

  return cwdMap;
}

function parseElapsedTime(etime) {
  if (!etime) {
    return null;
  }

  // `ps etime` puede venir como `MM:SS`, `HH:MM:SS` o `DD-HH:MM:SS`.
  const daySplit = etime.split("-");
  const timePart = daySplit.pop();
  const days = daySplit.length ? Number(daySplit[0]) : 0;
  const pieces = timePart.split(":").map((item) => Number(item));

  if (pieces.some((item) => Number.isNaN(item))) {
    return null;
  }

  if (pieces.length === 2) {
    const [minutes, seconds] = pieces;
    return days * 86400 + minutes * 60 + seconds;
  }

  if (pieces.length === 3) {
    const [hours, minutes, seconds] = pieces;
    return days * 86400 + hours * 3600 + minutes * 60 + seconds;
  }

  return null;
}

function formatRuntime(seconds) {
  if (seconds == null) {
    return "desconocido";
  }

  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainingSeconds = seconds % 60;

  if (days > 0) {
    return `${days}d ${hours}h`;
  }

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }

  if (minutes > 0) {
    return `${minutes}m ${remainingSeconds}s`;
  }

  return `${remainingSeconds}s`;
}

function basenameFromPath(value) {
  if (!value) {
    return null;
  }

  const parts = value.split("/").filter(Boolean);
  return parts.length ? parts[parts.length - 1] : value;
}

function matchesAny(text, entries) {
  return entries.some((entry) => text.includes(entry));
}

function classifyProcess(processInfo) {
  const haystack = [
    processInfo.name,
    processInfo.command,
    processInfo.cwd
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  const isIgnored = matchesAny(haystack, IGNORE_COMMAND_HINTS);
  const isVite =
    matchesAny(haystack, FRONTEND_HINTS.filter((item) => item.includes("vite"))) ||
    /\bvite\b/.test(haystack);
  const isNext =
    haystack.includes("next dev") || haystack.includes("next/dist/bin/next");
  const isPythonServer =
    haystack.includes("python") && matchesAny(haystack, PYTHON_SERVER_HINTS);
  const isNodeLike =
    /\b(node|npm|pnpm|yarn|bun|tsx|ts-node|nodemon)\b/.test(haystack);
  const hasProjectContext =
    (processInfo.cwd && processInfo.cwd.startsWith("/Users/") && processInfo.cwd !== "/") ||
    (processInfo.command &&
      processInfo.command.includes("/Users/") &&
      !processInfo.command.includes("/Applications/"));
  const looksLikeBackendEntry =
    matchesAny(haystack, NODE_BACKEND_HINTS) || /\b(src|app|server|index)\.(js|mjs|cjs|ts)\b/.test(haystack);

  let appType = "unknown";
  let role = "unknown";

  if (isVite) {
    appType = "vite frontend";
    role = "frontend";
  } else if (isNext) {
    appType = "next dev server";
    role = "frontend";
  } else if (isNodeLike && hasProjectContext && looksLikeBackendEntry) {
    appType = "node backend";
    role = "backend";
  } else if (isPythonServer) {
    role = "backend";
  }

  const isDevelopmentProcess =
    !isIgnored &&
    hasProjectContext &&
    (appType !== "unknown" ||
      isPythonServer ||
      (matchesAny(haystack, GENERIC_DEV_HINTS) && looksLikeBackendEntry));

  return {
    appType,
    role,
    isDevelopmentProcess
  };
}

function summarizePorts(sockets) {
  return sockets
    .map((socket) => `${socket.address}:${socket.port}`)
    .sort((left, right) => left.localeCompare(right));
}

function summarizeAddresses(sockets) {
  const addresses = [...new Set(sockets.map((socket) => socket.address))];
  return addresses.length ? addresses.join(", ") : "desconocido";
}

function annotateProcesses(processes) {
  const byCwd = new Map();
  const bySignature = new Map();
  const typicalDevListeners = [];

  for (const processInfo of processes) {
    if (processInfo.cwd) {
      if (!byCwd.has(processInfo.cwd)) {
        byCwd.set(processInfo.cwd, []);
      }
      byCwd.get(processInfo.cwd).push(processInfo);
    }

    const signature = `${processInfo.appType}|${processInfo.cwd || "unknown"}|${
      processInfo.name || "unknown"
    }`;

    if (!bySignature.has(signature)) {
      bySignature.set(signature, []);
    }
    bySignature.get(signature).push(processInfo);

    if (processInfo.ports.some((socket) => TYPICAL_DEV_PORTS.has(socket.port))) {
      typicalDevListeners.push(processInfo);
    }
  }

  const warnings = [];

  if (typicalDevListeners.length > 1) {
    warnings.push({
      type: "multi-dev-ports",
      level: "warning",
      message: "Hay varios procesos ocupando puertos típicos de desarrollo."
    });
  }

  for (const processInfo of processes) {
    const itemWarnings = [];
    const projectPeers = processInfo.cwd ? byCwd.get(processInfo.cwd) || [] : [];
    const signature = `${processInfo.appType}|${processInfo.cwd || "unknown"}|${
      processInfo.name || "unknown"
    }`;
    const similarProcesses = bySignature.get(signature) || [];

    if (similarProcesses.length > 1) {
      itemWarnings.push("duplicated");
    }

    if (projectPeers.length > 1) {
      itemWarnings.push("suspicious");
    }

    processInfo.warnings = [...new Set(itemWarnings)];
    processInfo.projectProcessCount = projectPeers.length;
    processInfo.duplicateCount = Math.max(similarProcesses.length - 1, 0);
  }

  if (processes.some((item) => item.warnings.includes("duplicated"))) {
    warnings.push({
      type: "duplicates",
      level: "warning",
      message: "Se detectaron procesos parecidos o posiblemente duplicados."
    });
  }

  if (processes.some((item) => item.warnings.includes("suspicious"))) {
    warnings.push({
      type: "same-project",
      level: "warning",
      message: "Hay más de un proceso escuchando desde la misma carpeta de proyecto."
    });
  }

  return warnings;
}

function buildProcessRecord(listenerInfo, psDetail, cwd) {
  const elapsedSeconds = parseElapsedTime(psDetail?.etime);
  const processInfo = {
    pid: listenerInfo.pid,
    name: listenerInfo.name || basenameFromPath(psDetail?.command?.split(" ")[0]) || "unknown",
    command: psDetail?.command || null,
    ports: listenerInfo.sockets
      .sort((left, right) => left.port - right.port)
      .map((socket) => ({
        port: socket.port,
        address: socket.address,
        host: socket.host,
        raw: socket.raw
      })),
    portSummary: summarizePorts(listenerInfo.sockets),
    address: summarizeAddresses(listenerInfo.sockets),
    runtime: {
      raw: psDetail?.etime || null,
      seconds: elapsedSeconds,
      label: formatRuntime(elapsedSeconds)
    },
    cwd: cwd || null,
    projectName: basenameFromPath(cwd),
    user: psDetail?.user || null,
    projectProcessCount: 0,
    duplicateCount: 0,
    warnings: []
  };

  const classification = classifyProcess(processInfo);

  return {
    ...processInfo,
    ...classification
  };
}

export async function scanProcesses() {
  const lsofOutput = await runCommand("/usr/sbin/lsof", [
    "-nP",
    "-iTCP",
    "-sTCP:LISTEN",
    "-Fpcn"
  ]);

  const listeners = parseLsofListeners(lsofOutput);
  const pids = [...listeners.keys()];

  if (!pids.length) {
    return {
      generatedAt: new Date().toISOString(),
      processes: [],
      warnings: [],
      summary: {
        total: 0,
        frontends: 0,
        backends: 0,
        duplicates: 0,
        suspicious: 0
      }
    };
  }

  const pidArgument = pids.join(",");
  const [psOutput, cwdOutput] = await Promise.all([
    runCommand("/bin/ps", ["-ww", "-o", "pid=,ppid=,user=,etime=,args=", "-p", pidArgument]),
    runCommand("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pidArgument, "-Fn"]).catch(() => "")
  ]);

  const psDetails = parsePsOutput(psOutput);
  const cwdMap = parseCwdOutput(cwdOutput);

  const processes = pids
    .map((pid) => buildProcessRecord(listeners.get(pid), psDetails.get(pid), cwdMap.get(pid)))
    .filter((processInfo) => processInfo.isDevelopmentProcess)
    .sort((left, right) => left.pid - right.pid);

  const warnings = annotateProcesses(processes);

  return {
    generatedAt: new Date().toISOString(),
    processes,
    warnings,
    summary: {
      total: processes.length,
      frontends: processes.filter((item) => item.role === "frontend").length,
      backends: processes.filter((item) => item.role === "backend").length,
      duplicates: processes.filter((item) => item.warnings.includes("duplicated")).length,
      suspicious: processes.filter((item) => item.warnings.includes("suspicious")).length
    }
  };
}

export async function terminateProcess(pid, { force = false } = {}) {
  if (!Number.isInteger(pid) || pid <= 0) {
    throw new Error("PID inválido.");
  }

  if (pid === process.pid) {
    throw new Error("No se puede terminar el propio servidor del dashboard.");
  }

  const signal = force ? "SIGKILL" : "SIGTERM";

  process.kill(pid, signal);
  await delay(force ? 250 : 800);

  try {
    process.kill(pid, 0);
    return {
      ok: false,
      pid,
      signal,
      requiresForce: !force
    };
  } catch {
    return {
      ok: true,
      pid,
      signal,
      requiresForce: false
    };
  }
}

export async function terminateProjectByCwd(cwd, { force = false } = {}) {
  if (!cwd) {
    throw new Error("La carpeta del proyecto es obligatoria.");
  }

  const scan = await scanProcesses();
  const targets = scan.processes.filter(
    (processInfo) => processInfo.cwd === cwd && processInfo.pid !== process.pid
  );

  if (!targets.length) {
    return {
      ok: true,
      killed: [],
      missing: true
    };
  }

  const results = [];

  for (const target of targets) {
    try {
      const result = await terminateProcess(target.pid, { force });
      results.push(result);
    } catch (error) {
      results.push({
        ok: false,
        pid: target.pid,
        error: error.message
      });
    }
  }

  return {
    ok: results.every((item) => item.ok),
    cwd,
    results
  };
}
