(() => {
  'use strict';

  const EXPECTED_SERVER_URL = 'wss://veltsapp-j8mqf7tp.livekit.cloud';
  const PRIVATE_ROOM_PATTERN = /^velts-bad-[0-9a-f]{16}$/;
  const params = new URLSearchParams(window.location.search);
  const serverInput = document.getElementById('server');
  const roomInput = document.getElementById('roomName');
  const tokenInput = document.getElementById('token');
  const tokenFallback = document.getElementById('tokenFallback');
  const connectButton = document.getElementById('connect');
  const disconnectButton = document.getElementById('disconnect');
  const status = document.getElementById('status');
  const remoteAudio = document.getElementById('remoteAudio');

  serverInput.value = params.get('server') || '';
  roomInput.value = params.get('room') || '';

  let room = null;

  function setStatus(message, kind) {
    status.textContent = message;
    status.className = kind || 'muted';
  }

  async function overwriteClipboard() {
    try {
      await navigator.clipboard.writeText('[cleared]');
      return true;
    } catch (_) {
      return false;
    }
  }

  async function readToken() {
    let token = tokenInput.value.trim();
    if (token) return token;

    try {
      token = (await navigator.clipboard.readText()).trim();
    } catch (_) {
      tokenFallback.hidden = false;
      tokenInput.focus();
      throw new Error('O navegador nao permitiu ler o clipboard. Cole o token no campo que apareceu e clique Conectar novamente.');
    }

    if (!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token)) {
      tokenFallback.hidden = false;
      tokenInput.focus();
      throw new Error('O clipboard nao contem um token temporario valido. Rode novamente o helper e clique Conectar.');
    }

    return token;
  }

  connectButton.addEventListener('click', async () => {
    const serverUrl = serverInput.value.trim().replace(/\/$/, '');
    const roomName = roomInput.value.trim();

    if (serverUrl !== EXPECTED_SERVER_URL) {
      setStatus('LiveKit URL invalida para este projeto. Feche esta pagina e rode o helper novamente.', 'error');
      return;
    }
    if (!PRIVATE_ROOM_PATTERN.test(roomName)) {
      setStatus('Sala privada invalida. Feche esta pagina e rode o helper novamente.', 'error');
      return;
    }

    connectButton.disabled = true;
    setStatus('Conectando...', 'muted');

    try {
      const token = await readToken();
      const { Room, RoomEvent, Track } = LivekitClient;
      room = new Room();

      room.on(RoomEvent.TrackSubscribed, (track) => {
        if (track.kind !== Track.Kind.Audio) return;
        const element = track.attach();
        element.autoplay = true;
        element.controls = true;
        remoteAudio.replaceChildren(element);
        setStatus('Conectado. Audio remoto do agente recebido.', 'ok');
      });

      room.on(RoomEvent.Disconnected, () => {
        connectButton.disabled = false;
        disconnectButton.disabled = true;
        setStatus('Desconectado.', 'muted');
      });

      await room.connect(serverUrl, token, { autoSubscribe: true });
      tokenInput.value = '';
      tokenFallback.hidden = true;
      await overwriteClipboard();
      await room.startAudio();
      await room.localParticipant.setMicrophoneEnabled(true);

      disconnectButton.disabled = false;
      setStatus('Conectado. Microfone ativo. Fale com a Stella.', 'ok');
    } catch (error) {
      connectButton.disabled = false;
      disconnectButton.disabled = true;
      if (room) {
        try { await room.disconnect(); } catch (_) {}
      }
      room = null;
      setStatus(error && error.message ? error.message : String(error), 'error');
    }
  });

  disconnectButton.addEventListener('click', async () => {
    if (!room) return;
    try {
      await room.localParticipant.setMicrophoneEnabled(false);
    } catch (_) {}
    await room.disconnect();
    room = null;
  });
})();
