import RFB from './novnc.js';

const bridge = window.tapMyPcRemoteDesktop;
const viewport = document.getElementById('viewport');
const screen = document.getElementById('screen');
const panX = document.getElementById('pan-x');
const panY = document.getElementById('pan-y');
const keyboard = document.getElementById('remote-keyboard');
const captureSettleMs = 1000;
const scaleReplyGraceMs = 4000;
const scaleFrameStallMs = 4000;
const preferredEncodings = new Map([
  ['tight', 7], ['zrle', 16], ['zlib', 6], ['hextile', 5], ['rre', 2], ['raw', 0],
]);
const encodingLabels = new Map([
  [0, 'Raw'], [1, 'CopyRect'], [2, 'RRE'], [5, 'Hextile'], [6, 'Zlib'],
  [7, 'Tight'], [16, 'ZRLE'], [21, 'JPEG'], [50, 'H.264'], [-260, 'Tight PNG'],
]);
let settings;
let activeScale = 1;
let pendingScale = null;
let scaleTimer;
let startupScaleTimer;
let updateHasPixels = false;
let lastDesktopFrameAt = 0;
let readyToScale = false;
let framebufferSize;
let receivedBytes = 0;
let receivedUpdates = 0;
let sampleStart = performance.now();
let statsTimer;
let jpegChroma;
const recentEncodings = new Set();
let lastEncodings = [];
let viewer;
let connected = false;
let awaitingPassword = false;
let refreshTimer;
let canvas;
const framebufferObserver = new MutationObserver(reportFramebufferSize);
const layoutObserver = new ResizeObserver(updatePanBars);
panX.addEventListener('input', updatePan);
panY.addEventListener('input', updatePan);

function updatePan() {
  screen.style.setProperty('--pan-x', panX.valueAsNumber / 1000);
  screen.style.setProperty('--pan-y', panY.valueAsNumber / 1000);
}

function updatePanBars() {
  panX.hidden = screen.clientWidth - viewport.clientWidth < 2;
  panY.hidden = screen.clientHeight - viewport.clientHeight < 2;
}

function centerPan() {
  panX.value = panY.value = '500';
  updatePan();
}

function streamSettings(message) {
  const request = JSON.parse(message);
  const level = (value, fallback) => Number.isInteger(value) && value >= 0 && value <= 9
    ? value : fallback;
  const encoding = preferredEncodings.get(request.encoding) ?? null;
  // UltraVNC's uncompressed Tight updates are incompatible with the noVNC decoder.
  const minimum = encoding === null || encoding === preferredEncodings.get('tight') ? 1 : 0;
  return {
    quality: level(request.quality, 6),
    compression: Math.max(minimum, level(request.compression, 2)),
    encoding,
    divisor: [2, 3, 4].includes(request.divisor) ? request.divisor : 1,
  };
}

function applyStreamSettings(next) {
  const previous = settings;
  settings = next;
  const encodingChanged = !previous ||
    ['quality', 'compression', 'encoding'].some(key => previous[key] !== next[key]);
  if (encodingChanged) {
    jpegChroma = undefined;
    recentEncodings.clear();
    lastEncodings = [];
    viewer.setStreamEncoding(next.encoding, next.quality, next.compression);
  }
  if (connected && previous?.divisor !== next.divisor) requestServerScale();
  if (encodingChanged) refreshScreen();
}

function requestServerScale() {
  // UltraVNC SetScale changes the streamed size without resizing the Windows desktop.
  if (!readyToScale || pendingScale !== null || activeScale === settings.divisor) return;
  pendingScale = settings.divisor;
  channel.send([8, pendingScale, 0, 0]);
  // Keep the request pending for a late reply. A second request could change
  // the meaning of subsequent rectangles before we receive the first reply.
  scaleTimer = setTimeout(probeServerScale, scaleReplyGraceMs);
}

function probeServerScale() {
  // UltraVNC uses its current framebuffer dimensions for full-frame requests.
  requestFullFrame();
  scaleTimer = setTimeout(checkScaleStall, scaleFrameStallMs, true);
}

function checkScaleStall(showDelay) {
  const quietTime = performance.now() - lastDesktopFrameAt;
  if (quietTime >= scaleFrameStallMs) {
    bridge.postMessage('viewerFailure:scaleStalled');
    channel.close();
    return;
  }
  if (showDelay) bridge.postMessage('scaleUnconfirmed');
  scaleTimer = setTimeout(checkScaleStall, scaleFrameStallMs - quietTime);
}

function serverScaleChanged() {
  if (pendingScale === null) return;
  clearTimeout(scaleTimer);
  activeScale = pendingScale;
  pendingScale = null;
  centerPan();
  queueMicrotask(() => {
    if (connected) requestServerScale();
  });
}

function noteStreamImage(mime, image) {
  if (mime !== 'image/jpeg' || jpegChroma) return;
  // Inspect sampling factors in a JPEG Start of Frame segment. Stop before scan data.
  const end = Math.min(image.length, 65536);
  for (let i = 2; i + 4 < end && image[i++] === 0xff;) {
    while (i < end && image[i] === 0xff) i++;
    const marker = image[i++];
    if (marker === 0xda || marker === 0xd9 || i + 2 > end) break;
    const length = image[i] * 256 + image[i + 1];
    if (length < 2 || i + length > end) break;
    if ([0xc0, 0xc1, 0xc2].includes(marker) && length >= 11) {
      if (image[i + 7] === 1) jpegChroma = 'Grayscale';
      else if (image[i + 7] === 3 && length >= 17 && image[i + 12] === 0x11 && image[i + 15] === 0x11) {
        jpegChroma = { 0x11: '4:4:4', 0x21: '4:2:2', 0x22: '4:2:0' }[image[i + 9]] ?? 'Other';
      }
      break;
    }
    i += length;
  }
}

function desktopUpdated() {
  receivedUpdates++;
  if (!updateHasPixels) return;
  updateHasPixels = false;
  lastDesktopFrameAt = performance.now();
  if (readyToScale || startupScaleTimer !== undefined) return;
  // UltraVNC can still be initializing its capture size during the first update.
  startupScaleTimer = setTimeout(() => {
    if (!connected) return;
    readyToScale = true;
    requestServerScale();
  }, captureSettleMs);
}

function reportStreamStats() {
  const now = performance.now();
  const seconds = (now - sampleStart) / 1000;
  if (recentEncodings.size) lastEncodings = [...recentEncodings];
  bridge.postMessage(`stats:${JSON.stringify({
    kbps: Math.round(receivedBytes * 8 / 1000 / seconds),
    updates: Math.round(receivedUpdates / seconds),
    encodings: lastEncodings,
    jpegChroma,
  })}`);
  receivedBytes = 0;
  receivedUpdates = 0;
  sampleStart = now;
  recentEncodings.clear();
}

const channel = {
  readyState: 'connecting',
  binaryType: 'arraybuffer',
  protocol: '',
  onopen: null,
  onmessage: null,
  onerror: null,
  onclose: null,
  send(bytes) {
    bridge.postMessage(Uint8Array.from(bytes).buffer);
  },
  close() {
    if (this.readyState === 'closed') return;
    this.readyState = 'closed';
    this.onclose?.({ code: 1000 });
  },
};

function refreshScreen() {
  if (pendingScale === null) requestFullFrame();
}

function requestFullFrame() {
  if (!connected || channel.readyState !== 'open') return;
  if (!canvas?.width || !canvas.height) return;
  // RFB FramebufferUpdateRequest, non-incremental, covering the full desktop.
  const request = new DataView(new ArrayBuffer(10));
  request.setUint8(0, 3);
  request.setUint16(6, canvas.width);
  request.setUint16(8, canvas.height);
  bridge.postMessage(request.buffer);
}

function refreshAfterCaptureSettles() {
  // The first update can arrive while UltraVNC is preparing the Windows desktop.
  // A late full frame replaces stale pixels without relying on input or motion.
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(refreshScreen, captureSettleMs);
}

function reportFramebufferSize() {
  if (!connected || !canvas?.width || !canvas.height) return;
  const size = `${canvas.width} × ${canvas.height}`;
  if (framebufferSize === size) return;
  framebufferSize = size;
  screen.style.setProperty('--frame-aspect', canvas.width / canvas.height);
  centerPan();
  bridge.postMessage(`resolution:${size}`);
}

bridge.onmessage = ({ data }) => {
  if (data instanceof ArrayBuffer && channel.readyState === 'open') {
    if (connected) receivedBytes += data.byteLength;
    try {
      channel.onmessage?.({ data });
    } catch (error) {
      bridge.postMessage('viewerFailure:decode');
      channel.close();
    }
  } else if (typeof data === 'string' && data.startsWith('open:') && channel.readyState === 'connecting') {
    const initial = streamSettings(data.slice('open:'.length));
    viewer = new RFB(screen, channel, {
      onServerScaleChanged: serverScaleChanged,
      onStreamFailure: detail => {
        const reason = /decod|infl|rectangle/i.test(detail) ? 'decode' : 'protocol';
        bridge.postMessage(`viewerFailure:${reason}`);
      },
      onStreamRectangle: code => {
        updateHasPixels = true;
        recentEncodings.add(encodingLabels.get(code) ?? 'Other');
      },
      onStreamUpdate: desktopUpdated,
      onStreamImage: noteStreamImage,
    });
    viewer.scaleViewport = true;
    viewer.background = '#0b0c0e';
    applyStreamSettings(initial);
    viewer.addEventListener('connect', () => {
      connected = true;
      canvas = screen.querySelector('canvas');
      if (canvas) {
        framebufferObserver.observe(canvas, { attributeFilter: ['width', 'height'] });
        reportFramebufferSize();
      }
      layoutObserver.observe(viewport);
      layoutObserver.observe(screen);
      sampleStart = performance.now();
      statsTimer = setInterval(reportStreamStats, 1000);
      bridge.postMessage('connected');
      refreshAfterCaptureSettles();
    });
    viewer.addEventListener('disconnect', () => {
      connected = false;
      awaitingPassword = false;
      clearTimeout(refreshTimer);
      framebufferObserver.disconnect();
      layoutObserver.disconnect();
      clearInterval(statsTimer);
      clearTimeout(scaleTimer);
      clearTimeout(startupScaleTimer);
      keyboard.value = '';
      keyboard.blur();
      bridge.postMessage('disconnected');
    });
    viewer.addEventListener('credentialsrequired', ({ detail }) => {
      if (detail.types.length === 1 && detail.types[0] === 'password') {
        if (!awaitingPassword) {
          awaitingPassword = true;
          bridge.postMessage('passwordRequired');
        }
      } else {
        bridge.postMessage('authenticationFailed');
      }
    });
    viewer.addEventListener('securityfailure', () => bridge.postMessage('authenticationFailed'));
    channel.readyState = 'open';
    channel.onopen();
  } else if (data === 'refresh') {
    requestFullFrame();
  } else if (data === 'desktopChanged' && connected) {
    refreshScreen();
    refreshAfterCaptureSettles();
  } else if (data === 'keyboard' && connected) {
    keyboard.focus({ preventScroll: true });
    if (document.activeElement === keyboard) bridge.postMessage('keyboardFocused');
  } else if (data === 'secureAttention' && connected) {
    viewer.sendCtrlAltDel();
  } else if (data === 'scale:fill' || data === 'scale:fit') {
    screen.classList.toggle('fill', data === 'scale:fill');
    centerPan();
  } else if (connected && typeof data === 'string' && data.startsWith('quality:')) {
    applyStreamSettings(streamSettings(data.slice('quality:'.length)));
  } else if (awaitingPassword && typeof data === 'string' && data.startsWith('password:')) {
    awaitingPassword = false;
    viewer.sendCredentials({ password: data.slice('password:'.length) });
  }
};

const specialKeys = new Map([
  ['Backspace', 0xff08], ['Tab', 0xff09], ['Enter', 0xff0d], ['Escape', 0xff1b],
  ['ArrowLeft', 0xff51], ['ArrowUp', 0xff52], ['ArrowRight', 0xff53], ['ArrowDown', 0xff54],
  ['Delete', 0xffff],
]);

function sendText(text) {
  for (const char of text) {
    const codePoint = char.codePointAt(0);
    if (codePoint >= 32 && codePoint !== 127) {
      viewer?.sendKey(codePoint < 256 ? codePoint : 0x01000000 | codePoint);
    }
  }
}
keyboard.addEventListener('keydown', event => {
  const keysym = specialKeys.get(event.key);
  if (keysym !== undefined) {
    event.preventDefault();
    viewer?.sendKey(keysym, event.code);
  }
});
keyboard.addEventListener('beforeinput', event => {
  if (!event.cancelable) return;
  if (event.inputType === 'deleteContentBackward') {
    event.preventDefault();
    viewer?.sendKey(0xff08, 'Backspace');
  } else if (event.data && event.inputType === 'insertText') {
    event.preventDefault();
    sendText(event.data);
  } else if (event.inputType === 'insertFromPaste') {
    event.preventDefault();
  }
});
keyboard.addEventListener('input', event => {
  if (!event.isComposing && event.inputType !== 'insertFromPaste') sendText(keyboard.value);
  if (!event.isComposing) keyboard.value = '';
});
keyboard.addEventListener('blur', () => { keyboard.value = ''; });

bridge.postMessage('ready');
