export const HOST = process.env.HOST || "127.0.0.1";
export const PORT = Number(process.env.PORT || 7000);

export const EXCLUDED_PORTS = new Set([7000, 7001]);

export const TYPICAL_DEV_PORTS = new Set([
  3000,
  3001,
  4000,
  4100,
  4173,
  4200,
  4321,
  5000,
  5173,
  5174,
  8000,
  8080,
  8787
]);

export const FRONTEND_HINTS = [
  "vite",
  "next dev",
  "next/dist/bin/next",
  "webpack-dev-server",
  "astro dev",
  "nuxt dev",
  "parcel",
  "react-scripts start"
];

export const PYTHON_SERVER_HINTS = [
  "http.server",
  "uvicorn",
  "gunicorn",
  "flask",
  "manage.py runserver",
  "django",
  "hypercorn",
  "streamlit",
  "fastapi"
];

export const NODE_BACKEND_HINTS = [
  "express",
  "fastify",
  "koa",
  "hono",
  "nest",
  "nodemon",
  "tsx",
  "ts-node",
  "server",
  "api",
  "dev"
];

export const GENERIC_DEV_HINTS = [
  "node",
  "npm",
  "pnpm",
  "yarn",
  "bun",
  "vite",
  "next",
  "python",
  "uvicorn",
  "gunicorn",
  "flask",
  "django",
  "webpack",
  "astro",
  "nuxt",
  "parcel",
  "remix",
  "serve",
  "dev server"
];

export const IGNORE_COMMAND_HINTS = [
  "electron",
  "chrome",
  "firefox",
  "language_server",
  "controlcenter",
  "rapportd",
  "gitnexus mcp",
  "cloudflared",
  "codex",
  "claude",
  "cursor"
];
