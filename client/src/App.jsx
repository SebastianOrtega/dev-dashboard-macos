import { useEffect, useState } from "react";

const API_URL = "http://127.0.0.1:7000/api";

async function requestJson(path, options) {
  const headers = options?.body
    ? {
        "Content-Type": "application/json"
      }
    : undefined;

  const response = await fetch(`${API_URL}${path}`, {
    headers,
    ...options
  });

  const data = await response.json();

  if (!response.ok) {
    const error = new Error(data.error || "Request failed.");
    error.payload = data;
    throw error;
  }

  return data;
}

function Badge({ children, tone = "default" }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

function SummaryCard({ label, value, tone = "default" }) {
  return (
    <div className={`summary-card summary-card-${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function IconButton({
  label,
  tone = "ghost",
  onClick,
  disabled = false,
  children
}) {
  return (
    <button
      className={`button icon-button ${tone}`}
      type="button"
      title={label}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}

function EyeIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" />
      <circle cx="12" cy="12" r="3.2" />
    </svg>
  );
}

function CopyIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="9" y="9" width="10" height="10" rx="2" />
      <path d="M6 15H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v1" />
    </svg>
  );
}

function KillIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 2v10" />
      <path d="M7.8 4.8a8 8 0 1 0 8.4 0" />
    </svg>
  );
}

function ProjectKillIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z" />
      <path d="m9 10 6 6" />
      <path d="m15 10-6 6" />
    </svg>
  );
}

function buildTerminalCommands(processInfo) {
  const ports = [...new Set((processInfo.ports || []).map((item) => item.port))];

  return {
    inspectPid: `ps -p ${processInfo.pid} -o pid=,ppid=,etime=,args=`,
    inspectPorts: ports.length
      ? ports.map((port) => `lsof -nP -iTCP:${port} -sTCP:LISTEN`).join("\n")
      : null,
    terminatePid: `kill ${processInfo.pid}`,
    forcePid: `kill -9 ${processInfo.pid}`,
    forcePorts: ports.length
      ? ports.map((port) => `kill -9 $(lsof -ti:${port})`).join("\n")
      : null
  };
}

export default function App() {
  const [payload, setPayload] = useState({
    generatedAt: null,
    processes: [],
    warnings: [],
    summary: {
      total: 0,
      frontends: 0,
      backends: 0,
      duplicates: 0,
      suspicious: 0
    }
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState("");
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [refreshSeconds, setRefreshSeconds] = useState(5);
  const [selectedPid, setSelectedPid] = useState(null);
  const [busyPid, setBusyPid] = useState(null);
  const [busyProject, setBusyProject] = useState(null);
  const [copiedPid, setCopiedPid] = useState(null);

  async function loadProcesses(showLoading = false) {
    try {
      if (showLoading) {
        setLoading(true);
      }
      const nextPayload = await requestJson("/processes");
      setPayload(nextPayload);
      setError(null);
    } catch (loadError) {
      setError(loadError.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadProcesses(true);
  }, []);

  useEffect(() => {
    if (!autoRefresh) {
      return undefined;
    }

    const timer = window.setInterval(() => {
      loadProcesses();
    }, refreshSeconds * 1000);

    return () => window.clearInterval(timer);
  }, [autoRefresh, refreshSeconds]);

  useEffect(() => {
    if (copiedPid == null) {
      return undefined;
    }

    const timer = window.setTimeout(() => setCopiedPid(null), 1500);
    return () => window.clearTimeout(timer);
  }, [copiedPid]);

  const term = search.trim().toLowerCase();
  const filteredProcesses = !term
    ? payload.processes
    : payload.processes.filter((processInfo) => {
        const haystack = [
          processInfo.pid,
          processInfo.name,
          processInfo.command,
          processInfo.cwd,
          processInfo.appType,
          processInfo.portSummary.join(" ")
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase();

        return haystack.includes(term);
      });

  const selectedProcess =
    filteredProcesses.find((processInfo) => processInfo.pid === selectedPid) ||
    payload.processes.find((processInfo) => processInfo.pid === selectedPid) ||
    null;
  const detailCommands = selectedProcess ? buildTerminalCommands(selectedProcess) : null;

  async function handleCopy(processInfo) {
    try {
      await navigator.clipboard.writeText(processInfo.command || "");
      setCopiedPid(processInfo.pid);
    } catch (copyError) {
      setError(copyError.message);
    }
  }

  async function handleTerminate(processInfo) {
    const confirmed = window.confirm(
      `Terminar proceso ${processInfo.pid} (${processInfo.name}) en ${processInfo.portSummary.join(
        ", "
      )}?`
    );

    if (!confirmed) {
      return;
    }

    setBusyPid(processInfo.pid);

    try {
      await requestJson(`/processes/${processInfo.pid}/terminate`, {
        method: "POST",
        body: JSON.stringify({ force: false })
      });
      await loadProcesses();
    } catch (terminateError) {
      if (terminateError.payload?.requiresForce) {
        const forceConfirmed = window.confirm(
          `El proceso ${processInfo.pid} sigue vivo. ¿Quieres forzar el cierre?`
        );

        if (forceConfirmed) {
          await requestJson(`/processes/${processInfo.pid}/terminate`, {
            method: "POST",
            body: JSON.stringify({ force: true })
          });
          await loadProcesses();
        }
      } else {
        setError(terminateError.message);
      }
    } finally {
      setBusyPid(null);
    }
  }

  async function handleTerminateProject(processInfo) {
    if (!processInfo.cwd) {
      return;
    }

    const confirmed = window.confirm(
      `Terminar todos los procesos asociados a ${processInfo.cwd}?`
    );

    if (!confirmed) {
      return;
    }

    setBusyProject(processInfo.cwd);

    try {
      await requestJson("/projects/terminate", {
        method: "POST",
        body: JSON.stringify({
          cwd: processInfo.cwd,
          force: false
        })
      });
      await loadProcesses();
    } catch (projectError) {
      if (projectError.payload?.results?.some((item) => item.requiresForce)) {
        const forceConfirmed = window.confirm(
          "Uno o más procesos del proyecto siguen vivos. ¿Quieres forzar el cierre?"
        );

        if (forceConfirmed) {
          await requestJson("/projects/terminate", {
            method: "POST",
            body: JSON.stringify({
              cwd: processInfo.cwd,
              force: true
            })
          });
          await loadProcesses();
        }
      } else {
        setError(projectError.message);
      }
    } finally {
      setBusyProject(null);
    }
  }

  return (
    <div className="shell">
      <header className="hero">
        <div>
          <p className="eyebrow">Local Operations Dashboard</p>
          <h1>Development Processes</h1>
          <p className="hero-copy">
            Vista rápida de servidores locales detectados con `lsof` y `ps`.
            El API corre en 127.0.0.1:7000 y la UI en 127.0.0.1:7001; esos puertos
            se excluyen del tablero.
          </p>
        </div>
        <div className="hero-meta">
          <span>Último refresh</span>
          <strong>{payload.generatedAt ? new Date(payload.generatedAt).toLocaleTimeString() : "..."}</strong>
        </div>
      </header>

      <section className="summary-grid">
        <SummaryCard label="Procesos detectados" value={payload.summary.total} />
        <SummaryCard label="Frontends" value={payload.summary.frontends} tone="frontend" />
        <SummaryCard label="Backends" value={payload.summary.backends} tone="backend" />
        <SummaryCard label="Duplicados" value={payload.summary.duplicates} tone="warning" />
        <SummaryCard label="Sospechosos" value={payload.summary.suspicious} tone="danger" />
      </section>

      {payload.warnings.length > 0 && (
        <section className="warning-strip">
          {payload.warnings.map((warning) => (
            <div className="warning-card" key={warning.type}>
              <Badge tone="warning">{warning.level}</Badge>
              <span>{warning.message}</span>
            </div>
          ))}
        </section>
      )}

      <section className="control-bar">
        <input
          className="search-input"
          type="search"
          placeholder="Buscar por puerto, PID, nombre o comando"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />

        <div className="control-actions">
          <label className="toggle">
            <input
              type="checkbox"
              checked={autoRefresh}
              onChange={(event) => setAutoRefresh(event.target.checked)}
            />
            <span>Auto refresh</span>
          </label>

          <select
            value={refreshSeconds}
            onChange={(event) => setRefreshSeconds(Number(event.target.value))}
          >
            <option value={3}>3s</option>
            <option value={5}>5s</option>
            <option value={10}>10s</option>
          </select>

          <button className="button" onClick={loadProcesses}>
            Refresh
          </button>
        </div>
      </section>

      {error && <section className="error-banner">{error}</section>}

      <section className="table-wrap">
        <table className="process-table">
          <thead>
            <tr>
              <th>PID</th>
              <th>Proceso</th>
              <th>Puertos</th>
              <th>Carpeta</th>
              <th>Tipo</th>
              <th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr>
                <td colSpan="6" className="empty-state">
                  Cargando procesos...
                </td>
              </tr>
            ) : filteredProcesses.length === 0 ? (
              <tr>
                <td colSpan="6" className="empty-state">
                  No hay procesos de desarrollo escuchando puertos.
                </td>
              </tr>
            ) : (
              filteredProcesses.map((processInfo) => (
                <tr
                  key={processInfo.pid}
                  className={[
                    processInfo.warnings.includes("duplicated") ? "row-duplicated" : "",
                    processInfo.warnings.includes("suspicious") ? "row-suspicious" : ""
                  ]
                    .filter(Boolean)
                    .join(" ")}
                >
                  <td className="mono">{processInfo.pid}</td>
                  <td>
                    <div className="primary-cell">
                      <strong>{processInfo.name}</strong>
                      <div className="badge-row">
                        {processInfo.role === "frontend" && <Badge tone="frontend">frontend</Badge>}
                        {processInfo.role === "backend" && <Badge tone="backend">backend</Badge>}
                        {processInfo.warnings.includes("duplicated") && (
                          <Badge tone="warning">duplicated</Badge>
                        )}
                        {processInfo.warnings.includes("suspicious") && (
                          <Badge tone="danger">suspicious</Badge>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="mono">{processInfo.portSummary.join(", ")}</td>
                  <td className="cwd-cell" title={processInfo.cwd || "desconocido"}>
                    {processInfo.cwd || "desconocido"}
                  </td>
                  <td>
                    <div className="type-cell">
                      <strong>{processInfo.appType}</strong>
                      <span className="type-runtime mono">{processInfo.runtime.label}</span>
                    </div>
                  </td>
                  <td>
                    <div className="action-stack">
                      <IconButton label="Ver detalle" onClick={() => setSelectedPid(processInfo.pid)}>
                        <EyeIcon />
                      </IconButton>
                      <IconButton
                        label={copiedPid === processInfo.pid ? "Comando copiado" : "Copiar comando"}
                        onClick={() => handleCopy(processInfo)}
                      >
                        <CopyIcon />
                      </IconButton>
                      <IconButton
                        label={busyPid === processInfo.pid ? "Cerrando proceso" : "Matar proceso"}
                        tone="danger"
                        disabled={busyPid === processInfo.pid}
                        onClick={() => handleTerminate(processInfo)}
                      >
                        <KillIcon />
                      </IconButton>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </section>

      {selectedProcess && (
        <section className="detail-panel">
          <div className="detail-heading">
            <div>
              <p className="eyebrow">Detalle del proceso</p>
              <h2>
                {selectedProcess.name} <span className="mono">#{selectedProcess.pid}</span>
              </h2>
            </div>
            <button className="button ghost" onClick={() => setSelectedPid(null)}>
              Cerrar
            </button>
          </div>

          <div className="detail-grid">
            <div className="detail-card">
              <span>Tipo estimado</span>
              <strong>{selectedProcess.appType}</strong>
            </div>
            <div className="detail-card">
              <span>Puertos</span>
              <strong className="mono">{selectedProcess.portSummary.join(", ")}</strong>
            </div>
            <div className="detail-card">
              <span>Runtime</span>
              <strong>{selectedProcess.runtime.label}</strong>
            </div>
            <div className="detail-card">
              <span>Procesos en carpeta</span>
              <strong>{selectedProcess.projectProcessCount}</strong>
            </div>
          </div>

          <div className="detail-block">
            <span>Comando completo</span>
            <code>{selectedProcess.command || "desconocido"}</code>
          </div>

          <div className="detail-block">
            <span>Carpeta de trabajo</span>
            <code>{selectedProcess.cwd || "desconocido"}</code>
          </div>

          {detailCommands && (
            <div className="detail-command-grid">
              <div className="detail-block">
                <span>Ver por PID</span>
                <pre>
                  <code>{detailCommands.inspectPid}</code>
                </pre>
              </div>

              {detailCommands.inspectPorts && (
                <div className="detail-block">
                  <span>Ver por puerto</span>
                  <pre>
                    <code>{detailCommands.inspectPorts}</code>
                  </pre>
                </div>
              )}

              <div className="detail-block">
                <span>Cerrar normal</span>
                <pre>
                  <code>{detailCommands.terminatePid}</code>
                </pre>
              </div>

              <div className="detail-block">
                <span>Forzar por PID</span>
                <pre>
                  <code>{detailCommands.forcePid}</code>
                </pre>
              </div>

              {detailCommands.forcePorts && (
                <div className="detail-block">
                  <span>Forzar por puerto</span>
                  <pre>
                    <code>{detailCommands.forcePorts}</code>
                  </pre>
                </div>
              )}
            </div>
          )}

          <div className="detail-actions">
            {selectedProcess.cwd && (
              <IconButton
                label={
                  busyProject === selectedProcess.cwd
                    ? "Cerrando proyecto"
                    : "Matar proyecto"
                }
                tone="danger"
                disabled={busyProject === selectedProcess.cwd}
                onClick={() => handleTerminateProject(selectedProcess)}
              >
                <ProjectKillIcon />
              </IconButton>
            )}
            <IconButton
              label={copiedPid === selectedProcess.pid ? "Comando copiado" : "Copiar comando"}
              onClick={() => handleCopy(selectedProcess)}
            >
              <CopyIcon />
            </IconButton>
          </div>
        </section>
      )}
    </div>
  );
}
