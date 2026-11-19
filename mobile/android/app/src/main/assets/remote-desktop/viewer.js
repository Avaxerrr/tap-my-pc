import RFB from './novnc.js';

const bridge = window.tapMyPcRemoteDesktop;
const screen = document.getElementById('screen');
const controls = document.getElementById('controls');

const keyboard = document.getElementById('remote-keyboard');
const quality = document.getElementById('quality');
const qualityPresets = new Map([
  ['save-data', { qualityLevel: 2, compressionLevel: 6 }],
  ['balanced', { qualityLevel: 6, compressionLevel: 2 }],
  ['sharper', { qualityLevel: 8, compressionLevel: 2 }],
]);
let viewer;
let connected = false;
let awaitingPassword = false;

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
  if (!connected || channel.readyState !== 'open') return;
  const canvas = screen.querySelector('canvas');
  if (!canvas?.width || !canvas.height) return;
  // RFB FramebufferUpdateRequest, non-incremental, covering the full desktop.
  const request = new DataView(new ArrayBuffer(10));
  request.setUint8(0, 3);
  request.setUint16(6, canvas.width);
  request.setUint16(8, canvas.height);
  bridge.postMessage(request.buffer);
}

bridge.onmessage = ({ data }) => {
  if (data instanceof ArrayBuffer && channel.readyState === 'open') {
    channel.onmessage?.({ data });
  } else if (data === 'open' && channel.readyState === 'connecting') {
    viewer = new RFB(screen, channel);
    viewer.scaleViewport = true;
    viewer.background = '#000000';
    applyQualityPreset();
    viewer.addEventListener('connect', () => {
      connected = true;
      controls.hidden = false;
      bridge.postMessage('connected');
    });
    viewer.addEventListener('disconnect', () => {
      connected = false;
      awaitingPassword = false;
      controls.hidden = true;
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
    refreshScreen();
  } else if (awaitingPassword && typeof data === 'string' && data.startsWith('password:')) {
    awaitingPassword = false;
    viewer.sendCredentials({ password: data.slice('password:'.length) });
  }
};

document.getElementById('keyboard-button').addEventListener('click', () => {
  if (document.activeElement === keyboard) {
    keyboard.blur();
    viewer?.focus();
  } else {
    keyboard.focus();
  }
});
document.getElementById('secure-attention').addEventListener('click', () => viewer?.sendCtrlAltDel());
document.getElementById('refresh-screen').addEventListener('click', refreshScreen);
function applyQualityPreset() {
  if (!viewer) return;
  const preset = qualityPresets.get(quality.value) ?? qualityPresets.get('balanced');
  viewer.qualityLevel = preset.qualityLevel;
  viewer.compressionLevel = preset.compressionLevel;
}

quality.addEventListener('change', applyQualityPreset);

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
