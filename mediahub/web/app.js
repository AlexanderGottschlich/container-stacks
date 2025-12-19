(function () {
  // Clock + Date
  const clockEl = document.getElementById("clock");
  const dateEl  = document.getElementById("date");

  function tick() {
    const d = new Date();
    clockEl.textContent = d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
    dateEl.textContent  = d.toLocaleDateString("de-DE", { weekday: "short", day: "2-digit", month: "2-digit", year: "numeric" });
  }
  tick();
  setInterval(tick, 1000);

  // Views (Topbar navigation)
  const viewIds = ["start", "radio", "jellyfin"];
  const buttons = Array.from(document.querySelectorAll(".navbtn"));
  const views = new Map(viewIds.map(v => [v, document.getElementById(`view-${v}`)]));

  function setActive(view) {
    viewIds.forEach(v => views.get(v)?.classList.toggle("is-active", v === view));
    buttons.forEach(b => b.classList.toggle("is-active", b.dataset.view === view));
  }

  buttons.forEach(btn => btn.addEventListener("click", () => setActive(btn.dataset.view)));

  // Tiles click-to-open
  document.querySelectorAll(".tile").forEach(tile => {
    tile.addEventListener("click", () => {
      const url = tile.dataset.url;
      if (url) location.href = url;
    });
  });

  // Radio wiring
  const RADIO_BASE = "http://localhost:8001";
  const RADIO_MOUNT = "/radio";
  const RADIO_STREAM = RADIO_BASE + RADIO_MOUNT;
  const ICECAST_STATUS = RADIO_BASE + "/status-json.xsl";

  const audio = document.getElementById("audio");
  const btnPlay = document.getElementById("btnPlay");
  const btnStop = document.getElementById("btnStop");
  const nowPlaying = document.getElementById("nowPlaying");

  if (audio) audio.src = RADIO_STREAM;

  btnPlay?.addEventListener("click", async () => {
    try { await audio.play(); } catch { /* ignore */ }
  });

  btnStop?.addEventListener("click", () => {
    audio.pause();
    audio.currentTime = 0;
  });

  function extractNowPlaying(statusJson) {
    const stats = statusJson?.icestats ?? null;
    if (!stats) return null;
    const src = stats.source;
    if (!src) return null;

    const sources = Array.isArray(src) ? src : [src];
    const match = sources.find(s => {
      const listenUrl = (s.listenurl || "").toString();
      const mount = (s.mount || "").toString();
      return mount === RADIO_MOUNT || listenUrl.endsWith(RADIO_MOUNT);
    }) || sources[0];

    const title = (match?.title || match?.yp_currently_playing || match?.streamtitle || "").toString().trim();
    return title || null;
  }

  async function pollIcecast() {
    if (!nowPlaying) return;
    try {
      const res = await fetch(ICECAST_STATUS, { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const data = await res.json();
      nowPlaying.textContent = extractNowPlaying(data) ?? "–";
    } catch {
      nowPlaying.textContent = "–";
    }
  }

  pollIcecast();
  setInterval(pollIcecast, 5000);

  // Exit button -> local exit server (wenn vorhanden)
  document.getElementById("exitBtn")?.addEventListener("click", () => {
    location.href = "http://127.0.0.1:9333/exit";
  });
})();
