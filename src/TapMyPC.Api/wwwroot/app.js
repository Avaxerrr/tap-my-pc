'use strict';
const $ = id => document.getElementById(id);
// Migrate the browser credential without requiring an already paired phone to pair again.
let token = localStorage.getItem('tapMyPcToken') || localStorage.getItem('pcRemoteToken') || '';
if (token) localStorage.setItem('tapMyPcToken', token);
localStorage.removeItem('pcRemoteToken');
let state = null, busy = false, connected = false, refreshPromise = null;
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
    if (!token) throw new Error('Pair this phone again before sending commands.');
    const result = await api(path, method, body);
    const feedback = result.feedback;
    if (feedback?.audio) { if (state) state.audio = feedback.audio; renderAudio(feedback.audio); }
    if (feedback) lastSequence = feedback.sequence;
    notice(feedback?.message || (method === 'DELETE' ? 'Canceled. The pending power action will not run.' : body?.action + ' scheduled on your PC. You can cancel it below.'), 'success');
  } catch (error) {
    notice(error.name === 'TimeoutError' ? 'No response yet. The command may have reached your PC; check its status before retrying.' : error.message, 'error');
  } finally {
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
