// vibe2prod demo app. Plain node:http + pg — this is a placeholder for YOUR
// app. See "Bring your own app" in the README.
import { createServer } from "node:http";
import pg from "pg";

const { Pool } = pg;
const port = Number(process.env.PORT ?? 3000);

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 5,
  connectionTimeoutMillis: 3000,
});

const page = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>vibe2prod — it works</title>
<style>
  body { background: #0d1117; color: #e6edf3; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
         display: grid; place-items: center; min-height: 100vh; margin: 0; }
  main { max-width: 34rem; padding: 2rem; }
  h1 { font-size: 1.6rem; margin: 0 0 .25rem; }
  h1 span { color: #3fb950; }
  p { color: #8b949e; line-height: 1.6; }
  ul { list-style: none; padding: 0; }
  li { padding: .25rem 0; }
  li::before { content: "✔ "; color: #3fb950; }
  a { color: #58a6ff; }
  code { background: #161b22; padding: .15rem .4rem; border-radius: 4px; }
</style>
</head>
<body>
<main>
  <h1>vibe2prod <span>· it works</span></h1>
  <p>You are looking at a container behind TLS on a hardened host.
     Total effort: one command.</p>
  <ul>
    <li>HTTPS via Let's Encrypt (auto-renewing)</li>
    <li>Traefik v3 reverse proxy</li>
    <li>Postgres 18 — check <a href="/health"><code>/health</code></a></li>
    <li>Firewalled, fail2ban'd, auto-patched Ubuntu</li>
  </ul>
  <p>Next step: replace this demo with your app.<br>
     <a href="https://github.com/westart/vibe2prod#bring-your-own-app">github.com/westart/vibe2prod</a></p>
</main>
</body>
</html>
`;

function sendJson(res, code, body) {
  res.writeHead(code, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

const server = createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;

  if (path === "/health") {
    // A real round trip to Postgres, not a static 200.
    try {
      const started = process.hrtime.bigint();
      const { rows } = await pool.query("SELECT version() AS version");
      const ms = Number(process.hrtime.bigint() - started) / 1e6;
      sendJson(res, 200, {
        status: "ok",
        postgres: "connected",
        postgres_version: rows[0].version.split(" on ")[0],
        query_ms: Math.round(ms * 10) / 10,
      });
    } catch (err) {
      sendJson(res, 503, { status: "error", postgres: "unreachable", detail: err.message });
    }
    return;
  }

  if (path === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
    res.end(page);
    return;
  }

  sendJson(res, 404, { status: "not_found" });
});

server.listen(port, () => {
  console.log(`vibe2prod demo app listening on :${port}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    console.log(`${signal} received, shutting down`);
    server.close(() => process.exit(0));
    pool.end().catch(() => {});
    setTimeout(() => process.exit(0), 5000).unref();
  });
}
