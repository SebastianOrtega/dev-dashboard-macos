import cors from "cors";
import express from "express";
import { HOST, PORT } from "./config.js";
import {
  scanProcesses,
  terminateProcess,
  terminateProjectByCwd
} from "./processScanner.js";

const app = express();

app.use(express.json());
app.use(
  cors({
    origin(origin, callback) {
      if (!origin) {
        callback(null, true);
        return;
      }

      if (/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(origin)) {
        callback(null, true);
        return;
      }

      callback(new Error("Origen no permitido."));
    }
  })
);

app.get("/api/health", (_request, response) => {
  response.json({
    ok: true,
    host: HOST,
    port: PORT
  });
});

app.get("/api/processes", async (_request, response, next) => {
  try {
    const result = await scanProcesses();
    response.json(result);
  } catch (error) {
    next(error);
  }
});

app.post("/api/processes/:pid/terminate", async (request, response, next) => {
  try {
    const pid = Number(request.params.pid);
    const scan = await scanProcesses();
    const target = scan.processes.find((item) => item.pid === pid);

    if (!target) {
      response.status(404).json({
        ok: false,
        error: "El proceso ya no está disponible o no pertenece al dashboard."
      });
      return;
    }

    const result = await terminateProcess(pid, {
      force: Boolean(request.body?.force)
    });

    response.status(result.ok ? 200 : 409).json(result);
  } catch (error) {
    next(error);
  }
});

app.post("/api/projects/terminate", async (request, response, next) => {
  try {
    const result = await terminateProjectByCwd(request.body?.cwd, {
      force: Boolean(request.body?.force)
    });

    response.status(result.ok ? 200 : 409).json(result);
  } catch (error) {
    next(error);
  }
});

app.use((error, _request, response, _next) => {
  response.status(500).json({
    ok: false,
    error: error.message || "Unexpected server error."
  });
});

app.listen(PORT, HOST, () => {
  console.log(`Dev Dashboard API listening on http://${HOST}:${PORT}`);
});
