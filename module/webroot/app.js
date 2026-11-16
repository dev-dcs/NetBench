/* NetBench WebUI - @Dev_DcS */
'use strict';

const MOD = '/data/adb/modules/netbench';
const NET = `sh ${MOD}/libexec/netctl.sh`;
const UPDATE = `sh ${MOD}/libexec/update-check.sh`;
const CONF = '/data/adb/netbench/netbench.conf';

function exec(cmd, opts) {
  return new Promise((resolve) => {
    const name = 'cb' + Math.random().toString(36).slice(2);
    window[name] = (errno, stdout, stderr) => {
      delete window[name];
      resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
    };
    try { ksu.exec(cmd, JSON.stringify(opts || {}), name); }
    catch (e) { delete window[name]; resolve({ errno: -1, stdout: '', stderr: String(e) }); }
  });
}
const out = (cmd) => exec(cmd).then((r) => (r.stdout || r.stderr || '').trim());

const $ = (s) => document.querySelector(s);
const el = (t, c, txt) => { const e = document.createElement(t); if (c) e.className = c; if (txt != null) e.textContent = txt; return e; };
function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

let snackTimer;
function snack(m) { const s = $('#snack'); s.textContent = m; s.classList.add('show'); clearTimeout(snackTimer); snackTimer = setTimeout(() => s.classList.remove('show'), 2600); }

document.querySelectorAll('.tabs button').forEach((b) => {
  b.addEventListener('click', () => {
    document.querySelectorAll('.tabs button').forEach((x) => x.classList.remove('active'));
    document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
    b.classList.add('active'); $('#view-' + b.dataset.view).classList.add('active');
    const v = b.dataset.view;
    if (v === 'status') loadStatus();
    if (v === 'apps') loadBlocked();
    if (v === 'net') loadNet();
    if (v === 'vpn') loadVpn();
    if (v === 'cell') loadCell();
  });
});

/* ---- status ---- */
async function loadStatus() {
  $('#ver').textContent = (await out(`sed -n 's/^version=//p' ${MOD}/module.prop`)) || '?';
  $('#status').textContent = await out(`${NET} status`);
  const conf = await out(`cat ${CONF} 2>/dev/null`);
  $('#opt-update').checked = /^update_check=1/m.test(conf);
}
$('#check-update').addEventListener('click', async () => {
  $('#update-line').textContent = 'checking…';
  const r = await out(`${UPDATE} --json`);
  try { const d = JSON.parse(r); $('#update-line').textContent = d.available ? `Update: ${d.latest} (have ${d.current})` : `Up to date (${d.current})`; }
  catch { $('#update-line').textContent = r || 'could not check'; }
});

/* ---- apps / block ---- */
async function loadBlocked() {
  const box = $('#blocked'); box.textContent = 'loading…';
  const r = await out(`${NET} block list`);
  box.textContent = '';
  if (/nothing blocked/.test(r)) { box.textContent = 'nothing blocked'; return; }
  r.split('\n').filter(Boolean).forEach((line) => {
    const uid = line.replace(/^uid\s+/, '');
    const row = el('div', 'item');
    row.appendChild(el('div', 'item-main')).appendChild(el('span', 'name', 'uid ' + uid));
    const rm = el('button', 'btn tiny', 'Unblock');
    rm.addEventListener('click', async () => { await exec(`${NET} block rm ${q(uid)}`); loadBlocked(); });
    row.appendChild(rm); box.appendChild(row);
  });
}
$('#btn-add').addEventListener('click', async () => {
  const v = $('#add-pkg').value.trim(); if (!v) return;
  const r = await out(`${NET} block add ${q(v)}`); snack(r.split('\n')[0]); $('#add-pkg').value = ''; loadBlocked();
});
$('#load-apps').addEventListener('click', async () => {
  const box = $('#apps'); box.textContent = 'listing…'; $('#app-filter').hidden = false;
  const r = await out('pm list packages -3');
  const pkgs = r.split('\n').map((l) => l.replace(/^package:/, '').trim()).filter(Boolean).sort();
  box.textContent = '';
  pkgs.forEach((p) => {
    const row = el('div', 'item'); row.dataset.pkg = p;
    row.appendChild(el('div', 'item-main')).appendChild(el('span', 'name', p));
    const b = el('button', 'btn tiny', 'Block');
    b.addEventListener('click', async () => { const x = await out(`${NET} block add ${q(p)}`); snack(x.split('\n')[0]); loadBlocked(); });
    row.appendChild(b); box.appendChild(row);
  });
});
$('#app-filter').addEventListener('input', (e) => {
  const f = e.target.value.toLowerCase();
  $('#apps').querySelectorAll('.item').forEach((r) => { r.style.display = r.dataset.pkg.includes(f) ? '' : 'none'; });
});

/* ---- network / tcp / adb ---- */
async function loadNet() {
  const t = await out(`${NET} tcp show`);
  $('#tcp-now').textContent = t.replace(/\n/g, '   ');
  const avail = (t.match(/available: (.*)/) || [])[1] || '';
  const cur = (t.match(/current  : (.*)/) || [])[1] || '';
  const sel = $('#tcp-cc'); sel.innerHTML = '';
  avail.trim().split(/\s+/).filter(Boolean).forEach((cc) => {
    const o = el('option', null, cc); o.value = cc; if (cc === cur) o.selected = true; sel.appendChild(o);
  });
  const p = await out(`${NET} adb status`);
  $('#adb-state').textContent = 'adb over Wi-Fi: ' + p;
}
$('#tcp-apply').addEventListener('click', async () => {
  const cc = $('#tcp-cc').value, qd = $('#tcp-qdisc').value;
  const r = await out(`${NET} tcp set ${q(cc)} ${qd ? q(qd) : ''}`); snack(r.split('\n')[0]); loadNet();
});
$('#adb-on').addEventListener('click', async () => { const r = await out(`${NET} adb on ${q($('#adb-port').value || '5555')}`); snack(r.split('\n')[0]); loadNet(); });
$('#adb-off').addEventListener('click', async () => { await exec(`${NET} adb off`); snack('adb over Wi-Fi off'); loadNet(); });

/* ---- vpn ---- */
async function loadVpn() {
  $('#ts-status').textContent = await out(`${NET} tailscale status`);
  $('#et-status').textContent = await out(`${NET} easytier status`);
  const conf = await out(`cat ${CONF} 2>/dev/null`);
  const a = (conf.match(/^ET_ARGS=(.*)$/m) || [])[1]; if (a) $('#et-args').value = a;
}
$('#ts-start').addEventListener('click', async () => { snack(await out(`${NET} tailscale start`)); loadVpn(); });
$('#ts-stop').addEventListener('click', async () => { await exec(`${NET} tailscale stop`); loadVpn(); });
$('#ts-up').addEventListener('click', async () => {
  // tailscale up prints a login URL on stderr/stdout; surface it
  const r = await out(`${NET} tailscale up 2>&1`);
  const url = (r.match(/https:\/\/\S+/) || [])[0];
  $('#ts-auth').textContent = url ? ('Open to log in: ' + url) : r.split('\n')[0];
});
$('#et-start').addEventListener('click', async () => { const a = $('#et-args').value.trim(); snack(await out(`${NET} easytier start ${a}`)); loadVpn(); });
$('#et-stop').addEventListener('click', async () => { await exec(`${NET} easytier stop`); loadVpn(); });

/* ---- cellular / ims ---- */
async function loadCell() {
  const s = await out(`${NET} ims status`);
  $('#ims-toggle').checked = /override: on/.test(s);
  $('#ims-status').textContent = s;
}
$('#ims-toggle').addEventListener('change', async (e) => {
  await exec(`${NET} ims ${e.target.checked ? 'enable' : 'disable'}`); snack('IMS ' + (e.target.checked ? 'on' : 'off')); loadCell();
});
$('#save-settings').addEventListener('click', async () => {
  const up = $('#opt-update').checked ? 1 : 0;
  await exec(`mkdir -p /data/adb/netbench; grep -v '^update_check=' ${CONF} 2>/dev/null > ${CONF}.t; echo update_check=${up} >> ${CONF}.t; mv ${CONF}.t ${CONF}`);
  snack('saved');
});

loadStatus().catch((e) => snack('WebUI error: ' + e));
