'use strict';
const $ = id => document.getElementById(id);
// Migrate the browser credential without requiring an already paired phone to pair again.
let token = localStorage.getItem('tapMyPcToken') || localStorage.getItem('pcRemoteToken') || '';
if (token) localStorage.setItem('tapMyPcToken', token);
localStorage.removeItem('pcRemoteToken');
let state = null, busy = false, connected = false, refreshPromise = null;
let controlsPromise = null, controlsLoading = false;
let toastTimer, lastSequence = null, pendingDueAt = null, clockOffset = 0;

function notice(message, phase = 'info', popup = true) {
  $('notice').textContent = message;
  $('notice').classList.toggle('error', phase === 'error');
  if (!popup) return;
  clearTimeout(toastTimer);
  $('action-toast').hidden = false;
  $('action-toast').dataset.phase = phase;
  $('action-indicator').textContent = phase === 'running' ? '' : phase === 'error' ? '!' : '✓';
  $('action-message').textContent = message;
  if (phase !== 'running' && phase !== 'error') toastTimer = setTimeout(() => { $('action-toast').hidden = true; }, 5000);
}

function setConnected(value) {
  connected = value;
  $('connection').textContent = value ? busy ? '● Sending…' : '● Connected' : 'Not connected';
  $('connection').classList.toggle('online', value);
  $('remote').setAttribute('aria-busy', String(busy));
  document.querySelectorAll('#remote button,#remote input,#remote select').forEach(el => { el.disabled = !value || busy; });
  $('disconnect').disabled = false;
  if (value && state) {
    ['volume', 'mute', 'volume-down', 'volume-up'].forEach(id => { $(id).disabled ||= !state.capabilities.audio; });
    document.querySelectorAll('[data-power],#timer-action option').forEach(el => {
      const action = el.dataset.power || el.value;
      el.disabled ||= action === 'Sleep' && !state.capabilities.sleep || action === 'Hibernate' && !state.capabilities.hibernate;
    });
    document.querySelectorAll('[data-device-control],#audio-output,#apply-output,#refresh-devices').forEach(el => { el.disabled ||= controlsLoading; });
    $('apply-output').disabled ||= !$('audio-output').value;
    document.querySelectorAll('[data-supported]').forEach(el => { el.disabled ||= el.dataset.supported !== 'true'; });
    $('bluetooth-on').disabled ||= !state.bluetooth?.canControl || state.bluetooth?.state === 'On';
    $('bluetooth-off').disabled ||= !state.bluetooth?.canControl || state.bluetooth?.state === 'Off';
    $('display-off').disabled ||= !state.capabilities.display;
    document.querySelectorAll('[data-media]').forEach(el => { el.disabled ||= !state.capabilities.media; });
  }
}

async function api(path, method = 'GET', body) {
  const response = await fetch('/api/v1' + path, {
    method,
    headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(8000)
  });
  let result = {};
  try { result = await response.json(); } catch { /* HTTP status remains authoritative. */ }
  if (!response.ok) {
    if (response.status === 401 && path !== '/pair') { localStorage.removeItem('tapMyPcToken'); token = ''; renderPairing(); }
    throw new Error(result.error || 'Request failed (' + response.status + ').');
  }
  return result;
}

function renderPairing() {
  $('pairing').hidden = !!token;
  $('remote').hidden = !token;
  if (!token) { setConnected(false); pendingDueAt = null; }
}

function renderAudio(audio) {
  $('volume-value').textContent = audio ? audio.volume + '%' : '—';
  if (document.activeElement !== $('volume') && audio) $('volume').value = audio.volume;
  $('mute').textContent = audio?.muted ? 'Unmute' : 'Mute';
}

function renderCountdown() {
  if (!state?.scheduler.pending || !pendingDueAt || !token) return;
  const seconds = Math.max(0, Math.ceil((pendingDueAt - (Date.now() + clockOffset)) / 1000));
  const action = state.scheduler.pending.action;
  const remaining = Math.floor(seconds / 60) + 'm ' + seconds % 60 + 's';
  $('pending-label').textContent = seconds ? action + ' in ' + remaining : action + ' request is due. Waiting for the PC…';
  $('live-action-title').textContent = action + (seconds ? ' scheduled' : ' is due');
  $('live-action-time').textContent = seconds ? remaining + ' remaining · cancel before it starts' : 'The PC may disconnect as Windows handles the request.';
}

async function refresh(force = false) {
  if (!token || busy || (!force && document.hidden)) return;
  if (refreshPromise) return refreshPromise;
  refreshPromise = (async () => {
    try {
      const wasConnected = connected;
      state = await api('/status');
      $('pc-name').textContent = state.pcName;
      renderAudio(state.audio);
      const bluetooth = state.bluetooth;
      $('bluetooth-state').textContent = bluetooth?.state || 'Unavailable';
      $('bluetooth-detail').textContent = bluetooth?.message || "Control the PC's Bluetooth. Turning it off disconnects Bluetooth headphones, mice, and keyboards.";
      const pending = state.scheduler.pending;
      $('pending').hidden = !pending;
      $('live-action').hidden = !pending;
      pendingDueAt = pending ? Date.parse(pending.dueAt) : null;
      clockOffset = Date.parse(state.serverTime) - Date.now();
      renderCountdown();
      const latest = state.activity?.[0];
      if (latest && lastSequence !== null && latest.sequence > lastSequence) {
        notice(latest.message, latest.phase === 'Failed' ? 'error' : latest.phase === 'Running' ? 'running' : 'success');
      } else if (!wasConnected) notice('Connected. Your remote is ready.', 'info', false);
      if (latest) lastSequence = latest.sequence;
      setConnected(true);
      if (!wasConnected) await refreshControls();
    } catch (error) {
      setConnected(false);
      const power = state?.scheduler.pending;
      notice(power ? 'PC disconnected. The scheduled ' + power.action.toLowerCase() + ' may have started; completion cannot be confirmed.' : error.message + ' Check that the PC is awake and the host is running.', 'error');
    } finally { refreshPromise = null; }
  })();
  return refreshPromise;
}

async function command(path, method, body, pendingMessage, button) {
  if (busy || !connected) return;
  // Let an in-flight status read finish before sending a new mutation, so an older snapshot cannot overwrite its result.
  busy = true;
  setConnected(connected);
  button?.classList.add('is-running');
  notice(pendingMessage, 'running');
  try {
    if (refreshPromise) await refreshPromise;
    if (controlsPromise) await controlsPromise;
    if (!token) throw new Error('Pair this phone again before sending commands.');
    const result = await api(path, method, body);
    const feedback = result.feedback;
    if (feedback?.audio) { if (state) state.audio = feedback.audio; renderAudio(feedback.audio); }
    if (feedback) lastSequence = feedback.sequence;
    notice(feedback?.message || (method === 'DELETE' ? 'Canceled. The pending power action will not run.' : body?.action + ' scheduled on your PC. You can cancel it below.'), 'success');
  } catch (error) {
    notice(error.name === 'TimeoutError' ? 'No response yet. The command may have reached your PC; check its status before retrying.' : error.message, 'error');
  } finally {
    if (/^\/(audio\/output|monitors\/|shortcuts\/)/.test(path)) await refreshControls();
    busy = false;
    button?.classList.remove('is-running');
    setConnected(connected);
    await refresh(true);
  }
}

async function confirmPower(action, delaySeconds, button) {
  if (!connected || busy) return;
  $('confirm-title').textContent = action + ' this PC?';
  $('confirm-description').textContent = 'This will run in ' + delaySeconds + ' seconds. Both devices will show the pending action. You can cancel before it starts. Unsaved work may block shutdown or restart.';
  const dialog = $('confirm-dialog');
  dialog.returnValue = 'cancel';
  const accepted = new Promise(resolve => dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true }));
  dialog.showModal();
  if (await accepted) await command('/power', 'POST', { action, delaySeconds, confirmed: true }, 'Scheduling ' + action.toLowerCase() + '…', button);
}

$('pair-form').addEventListener('submit', async event => {
  event.preventDefault();
  const button = event.submitter;
  button.disabled = true;
  notice('Connecting to your PC…', 'running');
  try {
    const result = await api('/pair', 'POST', { code: $('pair-code').value, name: $('device-name').value });
    token = result.token;
    localStorage.setItem('tapMyPcToken', token);
    $('pair-code').value = '';
    renderPairing();
    await refresh(true);
    if (connected) notice('Paired. Your phone is ready to control this PC.', 'success');
  } catch (error) { notice(error.message, 'error'); }
  finally { button.disabled = false; }
});
$('volume').addEventListener('input', () => { $('volume-value').textContent = $('volume').value + '%'; });
$('volume').addEventListener('change', event => command('/audio/volume', 'PUT', { volume: Number($('volume').value) }, 'Setting volume to ' + $('volume').value + '%…', event.currentTarget));
for (const [id, direction] of [['volume-down', 'Down'], ['volume-up', 'Up']]) $(id).addEventListener('click', event => command('/audio/step', 'POST', { direction }, 'Turning volume ' + direction.toLowerCase() + '…', event.currentTarget));
$('mute').addEventListener('click', event => command('/audio/mute', 'PUT', { muted: !state?.audio?.muted }, state?.audio?.muted ? 'Unmuting audio…' : 'Muting audio…', event.currentTarget));
document.querySelectorAll('[data-media]').forEach(button => button.addEventListener('click', () => command('/media', 'POST', { action: button.dataset.media }, 'Sending media command…', button)));
for (const [id, enabled] of [['bluetooth-on', true], ['bluetooth-off', false]]) $(id).addEventListener('click', async event => {
  if (!enabled && !window.confirm('Turn off Bluetooth on this PC? Bluetooth headphones, mice, and keyboards will disconnect.')) return;
  await command('/bluetooth', 'PUT', { enabled }, 'Turning Bluetooth ' + (enabled ? 'on' : 'off') + '…', event.currentTarget);
});
$('display-off').addEventListener('click', event => command('/display/off', 'POST', {}, 'Requesting monitors off…', event.currentTarget));
document.querySelectorAll('[data-power]').forEach(button => button.addEventListener('click', () => confirmPower(button.dataset.power, ['Shutdown', 'Restart'].includes(button.dataset.power) ? 10 : 3, button)));
$('timer-form').addEventListener('submit', event => { event.preventDefault(); confirmPower($('timer-action').value, Number($('timer-minutes').value) * 60, event.submitter); });
function cancelTimer(event) { if (state?.scheduler.pending) command('/power/' + state.scheduler.pending.id, 'DELETE', undefined, 'Canceling the pending action…', event.currentTarget); }
$('cancel-timer').addEventListener('click', cancelTimer);
$('cancel-live-action').addEventListener('click', cancelTimer);
$('dismiss-toast').addEventListener('click', () => { $('action-toast').hidden = true; });
$('disconnect').addEventListener('click', () => {
  if (busy) return;
  localStorage.removeItem('tapMyPcToken'); token = ''; state = null; lastSequence = null;
  renderPairing();
  notice('Connection forgotten on this phone. Revoke it on the PC to invalidate its credential.');
});
renderPairing();
refresh();
setInterval(refresh, 2000);
setInterval(renderCountdown, 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}

async function refreshControls() {
  if (!token) return;
  if (controlsPromise) return controlsPromise;
  controlsLoading = true;
  setConnected(connected);
  const requestToken = token;
  controlsPromise = (async () => {
    try {
      const results = await Promise.allSettled([api('/audio/outputs'), api('/monitors'), api('/shortcuts')]);
      if (requestToken !== token) return;
      if (results[0].status === 'fulfilled') {
        const outputs = results[0].value;
        const select = $('audio-output');
        select.replaceChildren();
        for (const output of outputs) {
          const option = element('option', output.name + (output.isDefault ? ' · Current' : ''));
          option.value = output.id;
          option.selected = output.isDefault;
          select.append(option);
        }
        if (!outputs.length) {
          const option = element('option', 'No audio outputs available'); option.value = ''; select.append(option);
        }
      }
      if (results[1].status === 'fulfilled') renderMonitors(results[1].value);
      if (results[2].status === 'fulfilled') {
        const shortcuts = results[2].value;
        $('shortcut-empty').hidden = shortcuts.length > 0;
        $('shortcut-list').replaceChildren();
        for (const shortcut of shortcuts) {
          const button = element('button', shortcut.name);
          button.dataset.deviceControl = '';
          button.dataset.shortcut = shortcut.id;
          button.append(element('small', shortcut.kind === 'Website' ? 'Website ↗' : 'Application ↗'));
          button.addEventListener('click', () => command('/shortcuts/' + encodeURIComponent(shortcut.id) + '/launch', 'POST', {}, 'Opening ' + shortcut.name + '…', button));
          $('shortcut-list').append(button);
        }
      }
      const failures = results.filter(r => r.status === 'rejected');
      if (failures.length) notice('Some device controls could not load. ' + failures[0].reason.message, 'error');
    } catch (error) {
      notice('Could not refresh devices. ' + error.message, 'error');
    } finally {
      controlsLoading = false; controlsPromise = null; setConnected(connected);
    }
  })();
  return controlsPromise;
}

function renderMonitors(monitors) {
  const list = $('monitor-list');
  list.replaceChildren();
  if (!monitors.length) { list.append(element('p', 'No monitors detected.')); return; }
  for (const monitor of monitors) {
    const card = element('div', undefined, 'monitor-controls');
    card.dataset.monitor = monitor.id;
    card.append(element('h3', monitor.name));
    const label = element('label', 'Brightness');
    const value = element('span', monitor.brightness === null ? 'Unavailable' : monitor.brightness + '%');
    label.append(value);
    const slider = element('input');
    slider.type = 'range'; slider.min = '0'; slider.max = '100'; slider.value = monitor.brightness ?? 50;
    slider.setAttribute('aria-label', monitor.name + ' brightness');
    slider.dataset.deviceControl = ''; slider.dataset.supported = String(monitor.canSetBrightness);
    slider.addEventListener('input', () => { value.textContent = slider.value + '%'; });
    slider.addEventListener('change', () => command('/monitors/brightness', 'PUT', { id: monitor.id, brightness: Number(slider.value) }, 'Setting monitor brightness…', slider));
    card.append(label, slider);
    const row = element('div', undefined, 'row');
    for (const enabled of [true, false]) {
      const button = element('button', enabled ? 'Turn on' : 'Turn off');
      button.dataset.deviceControl = '';
      button.dataset.supported = String(monitor.canSetPower && monitor.isOn !== enabled);
      button.dataset.monitorPower = String(enabled);
      button.addEventListener('click', () => command('/monitors/power', 'PUT', { id: monitor.id, enabled }, 'Turning monitor ' + (enabled ? 'on' : 'off') + '…', button));
      row.append(button);
    }
    card.append(row);
    if (monitor.message) card.append(element('p', monitor.message, 'device-note'));
    list.append(card);
  }
}
$('refresh-devices').addEventListener('click', () => { if (!busy) refreshControls(); });
$('apply-output').addEventListener('click', event => command('/audio/output', 'PUT', { id: $('audio-output').value }, 'Switching audio output…', event.currentTarget));
