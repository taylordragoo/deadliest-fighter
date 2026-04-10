#!/usr/bin/env node
/**
 * Launches godot-mcp-server on a custom WebSocket port.
 *
 * The upstream server hardcodes port 6505. This wrapper creates a tiny
 * entry-point that overrides the port, running in the original package
 * directory so all imports resolve correctly.
 *
 * Usage:
 *   node launch_server.mjs [port]    (default: 6505)
 *
 * MCP config examples:
 *   Claude: { "command": "node", "args": ["/abs/path/to/launch_server.mjs", "6505"] }
 *   Codex:  { "command": "node", "args": ["/abs/path/to/launch_server.mjs", "6506"] }
 */

import { execSync, spawn } from 'child_process';
import { readFileSync, writeFileSync, unlinkSync } from 'fs';
import path from 'path';

const port = parseInt(process.argv[2] || '6505', 10);

function findServerDir() {
  const cacheDir = path.join(process.env.HOME, '.npm', '_npx');
  try {
    const result = execSync(
      `find "${cacheDir}" -path "*/godot-mcp-server/dist/index.js" -type f 2>/dev/null | head -1`,
      { encoding: 'utf-8' }
    ).trim();
    if (result) return path.dirname(result);
  } catch {}

  // Trigger install
  console.error('[launch_server] Package not cached, fetching...');
  execSync('npx -y godot-mcp-server --version 2>/dev/null || true', { stdio: 'ignore', timeout: 30000 });

  try {
    const result = execSync(
      `find "${cacheDir}" -path "*/godot-mcp-server/dist/index.js" -type f 2>/dev/null | head -1`,
      { encoding: 'utf-8' }
    ).trim();
    if (result) return path.dirname(result);
  } catch {}

  console.error('[launch_server] ERROR: Could not find godot-mcp-server');
  process.exit(1);
}

const distDir = findServerDir();
const entryFile = path.join(distDir, `_port_${port}.mjs`);

// Create a wrapper entry-point that patches the port before the original runs
// We import godot-bridge directly, override the default, then run the main logic
const source = readFileSync(path.join(distDir, 'index.js'), 'utf-8');
const patched = source.replace(
  /const WEBSOCKET_PORT\s*=\s*\d+/,
  `const WEBSOCKET_PORT = ${port}`
);
writeFileSync(entryFile, patched, 'utf-8');

console.error(`[launch_server] Starting godot-mcp-server on port ${port}`);

const child = spawn(process.execPath, [entryFile], {
  stdio: ['pipe', 'pipe', 'inherit'],
  cwd: distDir,
});

process.stdin.pipe(child.stdin);
child.stdout.pipe(process.stdout);

function cleanup() {
  try { unlinkSync(entryFile); } catch {}
}

child.on('exit', (code) => {
  cleanup();
  process.exit(code ?? 1);
});

process.on('SIGINT', () => { child.kill('SIGINT'); });
process.on('SIGTERM', () => { child.kill('SIGTERM'); });
process.on('exit', cleanup);
