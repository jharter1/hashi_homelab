job "playwright" {
  datacenters = ["dc1"]
  type        = "service"

  spread {
    attribute = "${node.unique.name}"
  }

  group "playwright" {
    count = 1

    network {
      mode = "host"
      port "http" {
        static = 3456
      }
    }

    restart {
      attempts = 3
      delay    = "30s"
      interval = "10m"
      mode     = "fail"
    }

    update {
      max_parallel      = 1
      health_check      = "checks"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
      auto_revert       = true
    }

    volume "playwright_screenshots" {
      type      = "host"
      read_only = false
      source    = "playwright_screenshots"
    }

    task "playwright" {
      driver = "docker"

      config {
        image        = "registry.lab.hartr.net/playwright:v1.50.0-noble"
        network_mode = "host"
        ports        = ["http"]
        privileged   = true
        entrypoint   = ["sh", "/local/start.sh"]
      }

      volume_mount {
        volume      = "playwright_screenshots"
        destination = "/screenshots"
      }

      # Resolve homepage service IP via Consul at job start
      template {
        destination = "local/homepage.env"
        env         = true
        change_mode = "restart"
        data        = <<EOH
HOMEPAGE_URL=http://homepage.service.consul:3333
PREVIEW_PORT=3456
EOH
      }

      # Startup: install playwright npm package (skip browser download — already in image)
      # /alloc/data persists across restarts within the same allocation.
      template {
        destination = "local/start.sh"
        data        = <<EOH
#!/bin/sh
DEPS=/alloc/data/playwright-deps
PW_VERSION=$(cat $DEPS/node_modules/playwright/package.json 2>/dev/null | grep '"version"' | head -1 | grep -o '[0-9.]*' || echo "none")
if [ "$PW_VERSION" != "1.50.0" ]; then
  echo "Installing playwright npm package (first start)..."
  mkdir -p $DEPS
  cd $DEPS
  npm init -y
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install playwright@1.50.0 --no-fund
fi
export NODE_PATH=$DEPS/node_modules
export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
exec node /local/server.js
EOH
      }

      # The screenshot server — no Go template delimiters used in this JS
      template {
        destination = "local/server.js"
        change_mode = "restart"
        data        = <<EOH
'use strict';

const http = require('http');
const fs   = require('fs');
const { chromium } = require('playwright');

const SCREENSHOT_PATH = '/screenshots/homepage.png';
const PORT            = parseInt(process.env.PREVIEW_PORT || '3456', 10);
const HOMEPAGE_URL    = process.env.HOMEPAGE_URL || 'http://localhost:3333';
const REFRESH_MS      = 30 * 60 * 1000; // 30 minutes

let lastUpdated  = null;
let screenshotting = false;

async function takeScreenshot() {
  if (screenshotting) return;
  screenshotting = true;
  console.log('[' + new Date().toISOString() + '] Taking screenshot of ' + HOMEPAGE_URL);
  let browser;
  try {
    browser = await chromium.launch({ args: ['--no-sandbox', '--disable-setuid-sandbox'] });
    const page = await browser.newPage();
    await page.setViewportSize({ width: 1920, height: 1080 });
    await page.goto(HOMEPAGE_URL, { waitUntil: 'networkidle', timeout: 60000 });
    // Let widget data finish loading
    await page.waitForTimeout(5000);
    await page.screenshot({ path: SCREENSHOT_PATH, fullPage: false });
    lastUpdated = new Date();
    console.log('[' + lastUpdated.toISOString() + '] Screenshot saved to ' + SCREENSHOT_PATH);
  } catch (err) {
    console.error('Screenshot failed: ' + err.message);
  } finally {
    if (browser) await browser.close();
    screenshotting = false;
  }
}

const server = http.createServer(async (req, res) => {
  // Trigger a refresh
  if (req.method === 'POST' && req.url === '/refresh') {
    takeScreenshot().catch(console.error);
    res.writeHead(303, { Location: '/' });
    res.end();
    return;
  }

  // Serve the raw screenshot
  if (req.url && req.url.startsWith('/screenshot.png')) {
    if (!fs.existsSync(SCREENSHOT_PATH)) {
      res.writeHead(503, { 'Content-Type': 'text/plain' });
      res.end('No screenshot yet — starting now, check back in ~15 seconds');
      return;
    }
    res.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-store' });
    fs.createReadStream(SCREENSHOT_PATH).pipe(res);
    return;
  }

  // Health check
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', lastUpdated: lastUpdated }));
    return;
  }

  // Main preview page
  const ts   = lastUpdated ? lastUpdated.toLocaleString() : 'Never';
  const busy = screenshotting ? ' (refreshing…)' : '';
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta http-equiv="refresh" content="300">
  <title>Homepage Preview</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { background: #0d1117; color: #c9d1d9; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
    .bar {
      display: flex; align-items: center; gap: 12px;
      padding: 10px 16px; background: #161b22; border-bottom: 1px solid #30363d;
    }
    h1 { font-size: 1rem; font-weight: 600; flex: 1; }
    .ts { font-size: 0.8rem; color: #8b949e; }
    button {
      background: #238636; color: #fff; border: none;
      padding: 5px 14px; border-radius: 6px; cursor: pointer; font-size: 0.85rem;
    }
    button:hover { background: #2ea043; }
    .frame {
      width: 100%; height: calc(100vh - 45px);
      overflow: hidden; background: #010409;
      display: flex; align-items: flex-start; justify-content: center;
    }
    img { width: 100%; display: block; }
  </style>
</head>
<body>
  <div class="bar">
    <h1>Homepage Widget Preview</h1>
    <span class="ts">Last updated: $${ts}$${busy}</span>
    <form method="POST" action="/refresh">
      <button type="submit">Refresh Now</button>
    </form>
  </div>
  <div class="frame">
    <img src="/screenshot.png?t=$${Date.now()}" alt="Homepage screenshot">
  </div>
</body>
</html>`);
});

server.listen(PORT, () => {
  console.log('Preview server on port ' + PORT + ', targeting ' + HOMEPAGE_URL);
  takeScreenshot().catch(console.error);
  setInterval(function() { takeScreenshot().catch(console.error); }, REFRESH_MS);
});
EOH
      }

      resources {
        cpu        = 500
        memory     = 512
        memory_max = 1024
      }

      service {
        name = "playwright-preview"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.playwright.rule=Host(`preview.lab.hartr.net`)",
          "traefik.http.routers.playwright.entrypoints=websecure",
          "traefik.http.routers.playwright.tls=true",
          "traefik.http.routers.playwright.tls.certresolver=letsencrypt",
          "traefik.http.routers.playwright.middlewares=authelia@file",
        ]

        check {
          type     = "http"
          path     = "/health"
          interval = "30s"
          timeout  = "10s"
          check_restart {
            limit           = 3
            grace           = "120s"
            ignore_warnings = false
          }
        }
      }
    }
  }
}
