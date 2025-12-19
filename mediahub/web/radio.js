(function () {
  const STATIONS = [
    {
      id: "ff",
      name: "Foo Fighters Radio",
      stream: "/foofighters",
      status: "/status-json.xsl",
      mount: "/foofighters",
      colorClass: "radio-color-youtube",
    },
    {
      id: "th",
      name: "Thievery Corporation Radio",
      stream: "/thievery",
      status: "/status-json.xsl",
      mount: "/thievery",
      colorClass: "radio-color-blue",
    },
  ];

  const grid = document.getElementById("radioGrid");
  const audio = document.getElementById("audio");
  const globalNow = document.getElementById("globalNow");

  function setText(el, value) {
    if (!el) return;
    const v = (value || "").toString().trim();
    el.textContent = v;
  }

  function render() {
    grid.innerHTML = "";
    STATIONS.forEach((s, idx) => {
      const tile = document.createElement("div");
      tile.className = "tile radio-tile";
      tile.tabIndex = 0;
      tile.dataset.stationId = s.id;

      const inner = document.createElement("div");
      inner.className = `radio-inner ${s.colorClass || "radio-color-gray"}`;

      const name = document.createElement("div");
      name.className = "radio-name";
      name.textContent = s.name;

      const now = document.createElement("div");
      now.className = "radio-now";
      now.id = `now-${s.id}`;
      now.textContent = ""; // leer statt Platzhalter

      inner.appendChild(name);
      inner.appendChild(now);
      tile.appendChild(inner);

      tile.addEventListener("click", () => toggleStation(s));
      tile.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          toggleStation(s);
        }
      });

      grid.appendChild(tile);

      if (idx === 0) setTimeout(() => tile.focus(), 0);
    });
  }

  async function toggleStation(station) {
    const active = audio.dataset.activeStation;

    // wenn gleiche Station aktiv: Toggle Play/Pause
    if (active === station.id) {
      if (audio.paused) {
        try { await audio.play(); } catch (_) {}
      } else {
        audio.pause();
      }
      return;
    }

    // neue Station starten
    audio.dataset.activeStation = station.id;
    audio.src = station.stream;

    try { await audio.play(); } catch (_) {}

    // globalNow sofort auf aktuelle Tile-Anzeige setzen (falls vorhanden)
    const t = document.getElementById(`now-${station.id}`)?.textContent?.trim();
    setText(globalNow, t || "");
  }

  function extractNowPlaying(data, mountPath) {
    const stats = data && data.icestats ? data.icestats : null;
    if (!stats || !stats.source) return null;

    const sources = Array.isArray(stats.source) ? stats.source : [stats.source];

    // mountPath erwartet "/foofighters" oder "/thievery"
    const want = (mountPath || "").toString().trim();
    const wantNoSlash = want.startsWith("/") ? want.slice(1) : want;

    // robustes Matching:
    // 1) listenurl Pfad endet mit "/<mount>"
    // 2) mount Feld (falls vorhanden) matcht "/<mount>" oder "<mount>"
    // 3) server_name matcht grob (optional)
    let match =
      sources.find(s => {
        const lu = (s.listenurl || "").toString();
        return want && lu.endsWith(want);
      }) ||
      sources.find(s => {
        const m = (s.mount || "").toString();
        return m === want || m === wantNoSlash || (want && m.endsWith(want));
      }) ||
      sources[0];

    const title = (match.title || match.yp_currently_playing || match.streamtitle || "")
      .toString()
      .trim();

    return title || null;
  }

  async function pollStation(station) {
    const target = document.getElementById(`now-${station.id}`);
    if (!target) return;

    try {
      const res = await fetch(station.status, { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const data = await res.json();

      const title = extractNowPlaying(data, station.mount);

      // Tile: leer statt Platzhalter
      setText(target, title || "");

      // Wenn Station aktiv ist: global spiegeln
      if (audio.dataset.activeStation === station.id) {
        setText(globalNow, title || "");
      }
    } catch (_) {
      setText(target, "");
      if (audio.dataset.activeStation === station.id) setText(globalNow, "");
    }
  }

  function pollAll() {
    STATIONS.forEach(pollStation);
  }

  render();
  pollAll();
  setInterval(pollAll, 5000);
})();
