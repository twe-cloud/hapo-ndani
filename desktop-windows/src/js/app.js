// ── Ndani Desktop — Dashboard Controller ──────────────────────
// Manages: navigation, models, offers, folders, participant id, payouts

// ── State ──────────────────────────────────────────────────────
let currentPage = 'overview';
let selectedOfferId = null;
// Participant identity for the optional rail. Not a licence — the app is free.
let participant = null;
let userBalance = null;
let offerHistory = [];

// ── Offers ───────────────────────────────────────────────────
// Deliberately empty. Offers come from the configured rail via
// GET /api/offers/available and from nowhere else. Do not seed placeholder
// buyers here: a person looking at this screen must be seeing real demand or
// nothing at all.
const AVAILABLE_OFFERS = [];

// ── Navigation ─────────────────────────────────────────────────
document.querySelectorAll('.sidebar-nav a').forEach(link => {
  link.addEventListener('click', (e) => {
    e.preventDefault();
    const page = link.dataset.page;
    navigate(page);
  });
});

function navigate(page) {
  currentPage = page;

  // Update sidebar
  document.querySelectorAll('.sidebar-nav a').forEach(a => a.classList.remove('active'));
  const active = document.querySelector(`.sidebar-nav a[data-page="${page}"]`);
  if (active) active.classList.add('active');

  // Update pages
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const pageEl = document.getElementById(`page-${page}`);
  if (pageEl) pageEl.classList.add('active');

  // Update topbar
  const titles = {
    overview: 'Overview',
    models: 'Local Models',
    offers: 'Data Offers',
    folders: 'Folders & Permissions',
    settings: 'Settings',
  };
  document.getElementById('topbar-title').textContent = titles[page] || page;

  // Refresh page data
  if (page === 'overview') refreshOverview();
  if (page === 'models') detectModels();
  if (page === 'offers') loadOffers();
  if (page === 'folders') loadFolders();
  if (page === 'settings') loadSettings();
}

// ── Overview ───────────────────────────────────────────────────
async function refreshOverview() {
  // System info
  const info = await ndani.system.info();
  document.getElementById('system-info').innerHTML = `
    <div><strong>Platform:</strong> ${info.platform === 'win32' ? 'Windows' : info.platform}</div>
    <div><strong>Architecture:</strong> ${info.arch}</div>
    <div><strong>Memory:</strong> ${info.totalMemoryGB} GB total, ${info.freeMemoryGB} GB free</div>
    <div><strong>CPUs:</strong> ${info.cpus} cores</div>
    <div><strong>Models directory:</strong> ${info.modelsDir}</div>
  `;

  // Model stats
  const models = await ndani.models.detect();
  const ready = models.filter(m => m.status === 'ready').length;
  document.getElementById('stat-models').textContent = ready;
  document.getElementById('stat-models-total').textContent = models.length;

  // Folder stats
  const folders = await ndani.folders.list();
  document.getElementById('stat-folders').textContent = folders.length;

  // Ledger stats
  const ledger = await ndani.ledger.list();
  document.getElementById('stat-ledger').textContent = ledger.length;

  // Earnings
  document.getElementById('stat-earnings').textContent = 'Unverified';

  // Recent activity
  renderRecentActivity(ledger);

  // Overview offers (show first 3)
  const offersHTML = AVAILABLE_OFFERS.slice(0, 3).map(o => `
    <div style="display:flex; justify-content:space-between; align-items:center; padding:8px 0; border-bottom:1px solid var(--border);">
      <div>
        <div style="font-size:0.88rem; font-weight:600;">${o.title}</div>
        <div style="font-size:0.78rem; color:var(--text-3);">${o.buyer}</div>
      </div>
      <div style="font-weight:700; color:var(--teal);">$${o.payoutUSD.toFixed(2)}</div>
    </div>
  `).join('');
  document.getElementById('overview-offers').innerHTML = offersHTML || '<div style="color:var(--text-3)">No offers available</div>';
}

function renderRecentActivity(ledger) {
  const tbody = document.getElementById('recent-activity');
  if (!ledger.length) {
    tbody.innerHTML = '<tr><td colspan="4" style="color:var(--text-3)">No reads yet</td></tr>';
    return;
  }
  tbody.innerHTML = ledger.slice(-10).reverse().map(e => `
    <tr>
      <td>${new Date(e.timestamp).toLocaleString()}</td>
      <td>${e.fileName || '—'}</td>
      <td style="font-size:0.82rem; color:var(--text-3);">${e.folderPath || '—'}</td>
      <td><span class="badge badge-${e.status === 'ready' ? 'ready' : 'missing'}">${e.status}</span></td>
    </tr>
  `).join('');
}

// ── Models ─────────────────────────────────────────────────────
async function detectModels() {
  const models = await ndani.models.detect();
  const grid = document.getElementById('models-grid');

  grid.innerHTML = models.map(m => {
    const statusClass = {
      ready: 'ready', missing: 'missing',
      invalid: 'missing', 'loader-missing': 'loader',
    }[m.status] || 'pending';

    const statusLabel = {
      ready: 'Ready', missing: 'Not Downloaded',
      invalid: 'Invalid File', 'loader-missing': 'Loader Missing',
    }[m.status] || m.status;

    const canDownload = m.status === 'missing' && m.downloadURL;
    const canTest = m.status === 'ready';

    return `
      <div class="model-card">
        <div style="display:flex; justify-content:space-between; align-items:start;">
          <div>
            <div class="model-name">${m.name}</div>
            <div class="model-tier">${m.tier} tier</div>
          </div>
          <span class="badge badge-${statusClass}">${statusLabel}</span>
        </div>
        <div class="model-size">${m.sizeMB ? m.sizeMB + ' MB' : 'Size unknown'} &middot; ${m.adapter}</div>
        <div id="progress-${m.id}" style="display:none;">
          <div class="progress-bar"><div class="progress-fill" id="fill-${m.id}" style="width:0%"></div></div>
          <div style="font-size:0.78rem; color:var(--text-3); margin-top:4px;" id="progress-text-${m.id}">0%</div>
        </div>
        <div class="model-actions">
          ${canDownload ? `<button class="btn btn-primary btn-sm" onclick="downloadModel('${m.id}')">Download</button>` : ''}
          ${canTest ? `<button class="btn btn-sm" onclick="smokeTest('${m.id}')">Test</button>` : ''}
        </div>
      </div>
    `;
  }).join('');
}

async function downloadModel(modelId) {
  const progressEl = document.getElementById(`progress-${modelId}`);
  if (progressEl) progressEl.style.display = 'block';

  // Start download
  ndani.models.download(modelId);

  // Poll progress
  const interval = setInterval(async () => {
    const prog = await ndani.models.downloadProgress(modelId);
    if (!prog) return;

    const pct = prog.total > 0 ? Math.round((prog.progress / prog.total) * 100) : 0;
    const fillEl = document.getElementById(`fill-${modelId}`);
    const textEl = document.getElementById(`progress-text-${modelId}`);
    if (fillEl) fillEl.style.width = pct + '%';
    if (textEl) textEl.textContent = `${pct}% (${Math.round(prog.progress / 1048576)} MB / ${Math.round(prog.total / 1048576)} MB)`;

    if (prog.status === 'done' || prog.status === 'error' || prog.status === 'hash-mismatch') {
      clearInterval(interval);
      if (prog.status === 'done') {
        showToast('Model downloaded successfully');
      } else {
        showToast('Download failed: ' + prog.status);
      }
      detectModels();
    }
  }, 500);
}

async function smokeTest(modelId) {
  showToast('Running smoke test...');
  const result = await ndani.models.smokeTest(modelId);
  if (result.ok) {
    showToast('Smoke test passed! Output: ' + result.output.slice(0, 80));
  } else {
    showToast('Smoke test failed: ' + (result.error || 'no output'));
  }
}

// ── Offers ─────────────────────────────────────────────────────
async function loadOffers() {
  // Render available offers
  const list = document.getElementById('offers-list');
  const emptyState = `
    <div class="offer-card">
      <div class="offer-title">No offers</div>
      <div class="offer-desc">
        Offers come from a configured rail. This build has none configured, so
        there is nothing to show — and nothing placeholder is shown in its
        place. Your files and notes stay on this machine either way.
      </div>
    </div>`;
  list.innerHTML = (AVAILABLE_OFFERS.length ? '' : emptyState) + AVAILABLE_OFFERS.map(o => `
    <div class="offer-card">
      <div style="display:flex; justify-content:space-between; align-items:start;">
        <div>
          <div class="offer-payout">$${o.payoutUSD.toFixed(2)}</div>
          <div class="offer-buyer">${o.buyer}</div>
        </div>
        <span class="badge badge-ready">${o.spotsLeft} spots</span>
      </div>
      <div class="offer-title">${o.title}</div>
      <div class="offer-desc">${o.description}</div>
      <div class="offer-tags">
        ${o.tags.map(t => `<span class="offer-tag">${t}</span>`).join('')}
      </div>
      <div class="offer-footer">
        <span style="font-size:0.78rem; color:var(--text-3);">Expires ${new Date(o.expiresAt).toLocaleDateString()}</span>
        <button class="btn btn-primary btn-sm" disabled title="Secure per-offer consent is not connected">Submission unavailable</button>
      </div>
    </div>
  `).join('');

  // Load history from backend
  await loadOfferHistory();

  // Update earnings
  document.getElementById('total-earnings').textContent = 'Unverified';
  document.getElementById('total-offers-count').textContent = 'Unverified';
  document.getElementById('available-balance').textContent = 'Unverified';

  document.getElementById('payout-btn').style.display = 'none';
  document.getElementById('payout-min-notice').textContent = 'Payouts are unavailable in this build.';
}

function acceptOffer() {
  showToast('Secure per-offer consent is not connected. Submission is unavailable.');
}

function closeOfferForm() {
  selectedOfferId = null;
  document.getElementById('offer-submit-section').style.display = 'none';
}

// Character counter
document.addEventListener('DOMContentLoaded', () => {
  const textarea = document.getElementById('offer-summary');
  if (textarea) {
    textarea.addEventListener('input', () => {
      document.getElementById('summary-count').textContent = textarea.value.length;
    });
  }
});

async function submitOffer() {
  showToast('Secure per-offer consent is not available in this build. Nothing was submitted.');
}

async function loadOfferHistory() {
  userBalance = null;
  offerHistory = [];
  document.getElementById('offer-history').innerHTML =
    '<tr><td colspan="5">History is unavailable until secure participant identity is connected.</td></tr>';
}

async function requestPayout() {
  showToast('Payouts are not available in this build. Nothing was submitted.');
}

// ── Folders ────────────────────────────────────────────────────
async function loadFolders() {
  const folders = await ndani.folders.list();
  const container = document.getElementById('folders-list');

  if (!folders.length) {
    container.innerHTML = `
      <div class="empty-state">
        <div class="empty-icon">&#128193;</div>
        <div class="empty-text">No folders approved yet</div>
        <button class="btn btn-primary" onclick="addFolder()">Add Your First Folder</button>
      </div>
    `;
  } else {
    container.innerHTML = folders.map(f => `
      <div class="folder-item">
        <div class="folder-info">
          <div class="folder-icon">&#128193;</div>
          <div>
            <div class="folder-name">${f.name}</div>
            <div class="folder-path">${f.path}</div>
          </div>
        </div>
        <div style="display:flex; gap:8px;">
          <button class="btn btn-sm" onclick="previewFolder('${f.id}')">Preview</button>
          <button class="btn btn-sm btn-danger" onclick="removeFolder('${f.id}')">Revoke</button>
        </div>
      </div>
    `).join('');
  }

  // Load ledger
  const ledger = await ndani.ledger.list();
  const ltbody = document.getElementById('ledger-table');
  if (!ledger.length) {
    ltbody.innerHTML = '<tr><td colspan="5" style="color:var(--text-3)">No reads yet</td></tr>';
  } else {
    ltbody.innerHTML = ledger.slice().reverse().map(e => `
      <tr>
        <td>${new Date(e.timestamp).toLocaleString()}</td>
        <td>${e.fileName || '—'}</td>
        <td style="font-size:0.82rem; color:var(--text-3);">${e.folderPath || '—'}</td>
        <td>${e.previewLength || 0} chars</td>
        <td style="color:var(--teal); font-weight:600;">${e.notSent ? 'No' : 'Yes'}</td>
      </tr>
    `).join('');
  }
}

async function addFolder() {
  const result = await ndani.folders.add();
  if (result && !result.exists) {
    showToast(`Folder approved: ${result.name}`);
  } else if (result?.exists) {
    showToast('Folder already approved');
  }
  loadFolders();
}

async function removeFolder(id) {
  await ndani.folders.remove(id);
  showToast('Folder access revoked');
  loadFolders();
}

async function previewFolder(id) {
  const result = await ndani.folders.readPreview(id);
  if (result.status === 'ready') {
    showToast(`Preview: ${result.fileName} (${result.previewLength} chars)`);
  } else {
    showToast(`Preview failed: ${result.status}`);
  }
  loadFolders(); // Refresh ledger
}

// ── Settings ───────────────────────────────────────────────────
async function loadSettings() {
  participant = await ndani.participant.load();
  if (participant) {
    document.getElementById('participant-id').value = participant.participant_id || '';
    document.getElementById('participant-sig').value = participant.signature || '';
    document.getElementById('participant-status').innerHTML =
      '<span>Legacy identifier saved locally; unverified and unable to authorize sales.</span>';
    if (participant.payout_email) {
      document.getElementById('payout-email').value = participant.payout_email;
    }
  }
}

// The app is free, so nothing is activated and nothing is verified. This saves
// a participant id locally so a rail can attribute a payout. No network call.
async function saveParticipantID() {
  const id = document.getElementById('participant-id').value.trim();
  const sig = document.getElementById('participant-sig').value.trim();
  if (!id) {
    showToast('Secure participant identity is unavailable; a saved identifier cannot authorize a sale.');
    return;
  }
  participant = { participant_id: id, signature: sig, payout_email: participant?.payout_email };
  await ndani.participant.save(participant);
  showToast('Saved on this device');
  loadSettings();
}

async function setupStripeConnect() {
  const email = document.getElementById('payout-email').value.trim();
  if (!email) {
    showToast('Enter your payout email first');
    return;
  }

  // Save email locally
  if (participant) {
    participant.payout_email = email;
    await ndani.participant.save(participant);
  }

  // NOT IMPLEMENTED — no Stripe Connect onboarding link is created here.
  showToast('Payout setup is not available in this build. Your email was saved locally only.');
  document.getElementById('stripe-connect-status').innerHTML = `
    <span style="color:var(--amber);">Pending — email saved: ${email}</span>
  `;
}

// ── Toast ──────────────────────────────────────────────────────
function showToast(msg) {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = 'toast';
  toast.textContent = msg;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

// ── Init ───────────────────────────────────────────────────────
async function init() {
  participant = await ndani.participant.load();
  refreshOverview();
}

init();
