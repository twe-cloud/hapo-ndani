const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { spawn } = require('child_process');
const https = require('https');
const http = require('http');

// ── Paths ──────────────────────────────────────────────────────────
const NDANI_HOME = path.join(app.getPath('home'), '.ndani');
const MODELS_DIR = path.join(NDANI_HOME, 'models');
const DATA_DIR = path.join(app.getPath('userData'));
const ALLOWED_FOLDERS_PATH = path.join(DATA_DIR, 'allowed-folders.json');
const READ_LEDGER_PATH = path.join(DATA_DIR, 'read-ledger.json');
const PARTICIPANT_PATH = path.join(DATA_DIR, 'participant.json');

// Ensure directories exist
for (const dir of [NDANI_HOME, MODELS_DIR, DATA_DIR]) {
  fs.mkdirSync(dir, { recursive: true });
}

// ── Optional account backend ───────────────────────────────────────
// Local chat, journal, memory and model loading never touch this. It only
// serves the hosted extras (the offers marketplace and payouts), and
// that service is not part of this repository. Supply an origin to switch
// those features on, via either:
//   * the NDANI_BACKEND_BASE_URL environment variable, or
//   * a config.json next to this file, copied from config.example.json.
// Leave it unset and hosted features stay off instead of failing oddly.
const BACKEND_BASE_URL = (() => {
  const fromEnvironment = process.env.NDANI_BACKEND_BASE_URL;
  if (fromEnvironment) return fromEnvironment.replace(/\/+$/, '');
  try {
    const configPath = path.join(__dirname, 'config.json');
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    if (config.backendBaseURL) return String(config.backendBaseURL).replace(/\/+$/, '');
  } catch { /* no config.json — local-only build */ }
  return '';
})();

const BACKEND_NOT_CONFIGURED = {
  ok: false,
  error: 'no_backend_configured',
  detail:
    'This build has no account backend configured, so hosted features are turned off. '
    + 'Local chat, journal, and memory are unaffected.',
};

// ── Runtime Adapters ───────────────────────────────────────────────
const RUNTIME_ROOTS = [
  path.join(NDANI_HOME, 'runtimes'),
  path.join(app.getPath('home'), 'AppData', 'Local', 'ndani', 'runtimes'),
];

const ADAPTERS = {
  'litertlm': {
    id: 'litertlm',
    dirName: 'litertlm',
    exe: process.platform === 'win32' ? 'litertlm.exe' : 'litertlm',
    extensions: ['.litertlm'],
    minBytes: 500_000,
  },
  'llamacpp': {
    id: 'llamacpp',
    dirName: 'llamacpp',
    exe: process.platform === 'win32' ? 'llama-cli.exe' : 'llama-cli',
    extensions: ['.gguf'],
    minBytes: 1_000_000,
  },
};

// ── Model Packages ─────────────────────────────────────────────────
const RECOMMENDED_MODELS = [
  {
    id: 'gemma-4-e2b-it',
    name: 'Gemma 4 E2B IT',
    tier: 'phone',
    adapter: 'litertlm',
    fileName: 'gemma-4-E2B-it.litertlm',
    // Pinned to an immutable commit revision, not a moving branch ref.
    downloadURL: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm',
    expectedSHA256: null,
    sizeMB: 2588,
  },
  {
    id: 'gemma-4-e4b-it',
    name: 'Gemma 4 E4B IT',
    tier: 'desktop',
    adapter: 'litertlm',
    fileName: 'gemma-4-E4B-it.litertlm',
    // Pinned to an immutable commit revision, not a moving branch ref.
    downloadURL: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/gemma-4-E4B-it.litertlm',
    expectedSHA256: null,
    sizeMB: 3660,
  },
  {
    id: 'qwen3-4b-gguf',
    name: 'Qwen3 4B',
    tier: 'desktop',
    adapter: 'llamacpp',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    downloadURL: 'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/bc640142c66e1fdd12af0bd68f40445458f3869b/Qwen3-4B-Q4_K_M.gguf',
    expectedSHA256: null,
    sizeMB: 2700,
  },
  {
    id: 'hermes-3-8b-gguf',
    name: 'Hermes 3 8B',
    tier: 'desktop',
    adapter: 'llamacpp',
    fileName: 'Hermes-3-Llama-3.1-8B.Q4_K_M.gguf',
    downloadURL: 'https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF/resolve/307a5dfb59aa38d88b6cfd32f44b8ad7c1da9fb8/Hermes-3-Llama-3.1-8B.Q4_K_M.gguf',
    expectedSHA256: null,
    sizeMB: 4900,
  },
];

// ── Window ─────────────────────────────────────────────────────────
let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: '#0b0f19',
    titleBarStyle: 'hidden',
    titleBarOverlay: process.platform === 'win32' ? {
      color: '#0b0f19',
      symbolColor: '#8899aa',
      height: 36,
    } : undefined,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'src', 'index.html'));
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// ── IPC: Participant ───────────────────────────────────────────────
// The app is free. There is no licence, no activation and nothing to verify.
// A participant id exists only so a rail can attribute a payout to the person
// who earned it, and it is stored locally like any other preference.
function loadParticipant() {
  try {
    return JSON.parse(fs.readFileSync(PARTICIPANT_PATH, 'utf8'));
  } catch { return null; }
}

function saveParticipant(data) {
  fs.writeFileSync(PARTICIPANT_PATH, JSON.stringify(data, null, 2));
}

ipcMain.handle('participant:load', () => loadParticipant());

ipcMain.handle('participant:save', (_e, data) => {
  saveParticipant(data);
  return { ok: true };
});

// ── IPC: Models ────────────────────────────────────────────────────
ipcMain.handle('models:list', () => RECOMMENDED_MODELS);

ipcMain.handle('models:detect', () => {
  const results = [];
  for (const pkg of RECOMMENDED_MODELS) {
    const filePath = path.join(MODELS_DIR, pkg.fileName);
    let status = 'missing';
    let sizeBytes = 0;

    if (fs.existsSync(filePath)) {
      const stat = fs.statSync(filePath);
      sizeBytes = stat.size;
      const adapter = ADAPTERS[pkg.adapter];

      if (sizeBytes < adapter.minBytes) {
        status = 'invalid';
      } else {
        // Check if adapter executable exists
        let loaderFound = false;
        for (const root of RUNTIME_ROOTS) {
          const exePath = path.join(root, adapter.dirName, adapter.exe);
          if (fs.existsSync(exePath)) { loaderFound = true; break; }
        }
        status = loaderFound ? 'ready' : 'loader-missing';
      }
    }
    results.push({ ...pkg, status, sizeBytes, localPath: filePath });
  }
  return results;
});

// Model download tracking
const _downloads = {};

ipcMain.handle('models:download', async (_e, modelId) => {
  const pkg = RECOMMENDED_MODELS.find(m => m.id === modelId);
  if (!pkg || !pkg.downloadURL) return { error: 'No download URL' };

  const dest = path.join(MODELS_DIR, pkg.fileName);
  const tmpDest = dest + '.download';

  _downloads[modelId] = { progress: 0, total: 0, status: 'downloading' };

  return new Promise((resolve) => {
    const file = fs.createWriteStream(tmpDest);
    const doRequest = (url) => {
      const mod = url.startsWith('https') ? https : http;
      mod.get(url, { headers: { 'User-Agent': 'Ndani/0.2.0' } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          doRequest(res.headers.location);
          return;
        }
        const total = parseInt(res.headers['content-length'] || '0', 10);
        _downloads[modelId].total = total;
        let downloaded = 0;

        res.on('data', (chunk) => {
          downloaded += chunk.length;
          _downloads[modelId].progress = downloaded;
          file.write(chunk);
        });

        res.on('end', () => {
          file.end();
          // Verify SHA-256 if expected
          if (pkg.expectedSHA256) {
            const hash = crypto.createHash('sha256');
            const stream = fs.createReadStream(tmpDest);
            stream.on('data', d => hash.update(d));
            stream.on('end', () => {
              const digest = hash.digest('hex');
              if (digest !== pkg.expectedSHA256) {
                fs.unlinkSync(tmpDest);
                _downloads[modelId].status = 'hash-mismatch';
                resolve({ error: 'SHA-256 mismatch' });
                return;
              }
              fs.renameSync(tmpDest, dest);
              _downloads[modelId].status = 'done';
              resolve({ ok: true, path: dest });
            });
          } else {
            fs.renameSync(tmpDest, dest);
            _downloads[modelId].status = 'done';
            resolve({ ok: true, path: dest });
          }
        });

        res.on('error', (err) => {
          file.end();
          _downloads[modelId].status = 'error';
          resolve({ error: err.message });
        });
      }).on('error', (err) => {
        file.end();
        _downloads[modelId].status = 'error';
        resolve({ error: err.message });
      });
    };
    doRequest(pkg.downloadURL);
  });
});

ipcMain.handle('models:download-progress', (_e, modelId) => {
  return _downloads[modelId] || { progress: 0, total: 0, status: 'idle' };
});

// ── IPC: Smoke test ────────────────────────────────────────────────
ipcMain.handle('models:smoke-test', async (_e, modelId) => {
  const pkg = RECOMMENDED_MODELS.find(m => m.id === modelId);
  if (!pkg) return { error: 'Unknown model' };

  const modelPath = path.join(MODELS_DIR, pkg.fileName);
  if (!fs.existsSync(modelPath)) return { error: 'Model not found locally' };

  const adapter = ADAPTERS[pkg.adapter];
  let exePath = null;
  for (const root of RUNTIME_ROOTS) {
    const candidate = path.join(root, adapter.dirName, adapter.exe);
    if (fs.existsSync(candidate)) { exePath = candidate; break; }
  }
  if (!exePath) return { error: 'Runtime loader not found' };

  return new Promise((resolve) => {
    const args = adapter.id === 'llamacpp'
      ? ['-m', modelPath, '-p', 'Hello', '-n', '16', '--no-display-prompt']
      : [modelPath, 'Hello'];

    const child = spawn(exePath, args, {
      timeout: 8000,
      env: { PATH: '' },  // sanitized
    });

    let output = '';
    child.stdout.on('data', d => { output += d.toString().slice(0, 240); });
    child.stderr.on('data', () => {});
    child.on('close', (code) => {
      resolve({
        ok: code === 0 && output.length > 0,
        output: output.slice(0, 240),
        exitCode: code,
      });
    });
    child.on('error', (err) => resolve({ error: err.message }));
  });
});

// ── IPC: Folders ───────────────────────────────────────────────────
function loadAllowedFolders() {
  try {
    return JSON.parse(fs.readFileSync(ALLOWED_FOLDERS_PATH, 'utf8'));
  } catch { return []; }
}

function saveAllowedFolders(folders) {
  fs.writeFileSync(ALLOWED_FOLDERS_PATH, JSON.stringify(folders, null, 2));
}

ipcMain.handle('folders:list', () => loadAllowedFolders());

ipcMain.handle('folders:add', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: 'Choose a folder to allow Ndani to read',
  });
  if (result.canceled || !result.filePaths.length) return null;

  const folderPath = result.filePaths[0];
  const folders = loadAllowedFolders();
  if (folders.find(f => f.path === folderPath)) return { exists: true };

  const entry = {
    id: crypto.randomUUID(),
    name: path.basename(folderPath),
    path: folderPath,
    addedAt: new Date().toISOString(),
  };
  folders.push(entry);
  saveAllowedFolders(folders);
  return entry;
});

ipcMain.handle('folders:remove', (_e, folderId) => {
  let folders = loadAllowedFolders();
  folders = folders.filter(f => f.id !== folderId);
  saveAllowedFolders(folders);
  return { ok: true };
});

ipcMain.handle('folders:read-preview', (_e, folderId) => {
  const folders = loadAllowedFolders();
  const folder = folders.find(f => f.id === folderId);
  if (!folder) return { error: 'Folder not found' };

  if (!fs.existsSync(folder.path)) return { status: 'missing', path: folder.path };

  // Find first .txt or .md file
  const entries = fs.readdirSync(folder.path).filter(f => !f.startsWith('.'));
  const textFile = entries.find(f => f.endsWith('.txt') || f.endsWith('.md'));
  if (!textFile) return { status: 'no-text-files', path: folder.path };

  const filePath = path.join(folder.path, textFile);
  // Prevent symlink escape
  const resolved = fs.realpathSync(filePath);
  const resolvedFolder = fs.realpathSync(folder.path);
  if (!resolved.startsWith(resolvedFolder)) {
    return { status: 'symlink-escape', path: filePath };
  }

  try {
    const content = fs.readFileSync(filePath, 'utf8');
    const preview = content.slice(0, 500);

    // Log to read ledger
    const ledger = loadReadLedger();
    ledger.push({
      timestamp: new Date().toISOString(),
      folderPath: folder.path,
      filePath,
      fileName: textFile,
      previewLength: preview.length,
      status: 'ready',
      notSent: true,
    });
    // Keep max 25 entries
    while (ledger.length > 25) ledger.shift();
    saveReadLedger(ledger);

    return { status: 'ready', fileName: textFile, preview, previewLength: preview.length };
  } catch {
    return { status: 'unreadable', path: filePath };
  }
});

function loadReadLedger() {
  try { return JSON.parse(fs.readFileSync(READ_LEDGER_PATH, 'utf8')); }
  catch { return []; }
}

function saveReadLedger(ledger) {
  fs.writeFileSync(READ_LEDGER_PATH, JSON.stringify(ledger, null, 2));
}

ipcMain.handle('ledger:list', () => loadReadLedger());

// ── IPC: System info ───────────────────────────────────────────────
ipcMain.handle('system:info', () => {
  const os = require('os');
  return {
    platform: process.platform,
    arch: process.arch,
    totalMemoryGB: Math.round(os.totalmem() / (1024 ** 3)),
    freeMemoryGB: Math.round(os.freemem() / (1024 ** 3)),
    cpus: os.cpus().length,
    // Deliberately no machine hostname here. The hardware matcher needs arch,
    // memory and core count; a hostname routinely carries a person's real
    // name and nothing here consumes it. Don't add it back.
    ndaniHome: NDANI_HOME,
    modelsDir: MODELS_DIR,
  };
});

// ── IPC: External links ───────────────────────────────────────────
ipcMain.handle('shell:open', (_e, url) => shell.openExternal(url));

// ── Utility: fetch JSON ────────────────────────────────────────────
function fetchJSON(url, options = {}) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http;
    const req = mod.request(url, {
      method: options.method || 'GET',
      headers: { 'Content-Type': 'application/json', ...options.headers },
    }, (res) => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try { resolve(JSON.parse(body)); }
        catch { resolve({ error: body }); }
      });
    });
    req.on('error', (err) => resolve({ error: err.message }));
    if (options.body) req.write(JSON.stringify(options.body));
    req.end();
  });
}

// ── IPC: Backend API proxy ─────────────────────────────────────────
ipcMain.handle('api:fetch', async (_e, endpoint, options = {}) => {
  if (!BACKEND_BASE_URL) return BACKEND_NOT_CONFIGURED;
  return fetchJSON(`${BACKEND_BASE_URL}${endpoint}`, options);
});
