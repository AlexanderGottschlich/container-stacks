/* radio.js */
(function () {
  // ========= Stationen =========
const STATIONS = [
  {
    id: "ff",
    name: "Foo Fighters Radio",
    stream: "/radio",
    status: "/status-json.xsl",
    mount: "/radio",
    colorClass: "radio-color-youtube",
  },
  {
    id: "th",
    name: "Thievery Corporation Radio",
    stream: "/thievery",
    status: "/status-json.xsl",
    mount: "/thievery",
    colorClass: "radio-color-blue", // oder eine neue Klasse
  },
];


  const grid = document.getElementById("radioGrid");
  const audio = document.getElementById("audio");
  const globalNow = document.getElementById("globalNow");

  // ---------- Helpers ----------
  function setText(el, text) {
    if (!el) return;
    el.textContent = (text && String(text).trim()) ? String(text).trim() : "";
  }

  function setPlayingTile(activeId) {
    const tiles = grid.querySelectorAll(".radio-tile");
    tiles.forEach(t => {
      const isActive = t.dataset.stationId === activeId && !audio.paused;
      t.classList.toggle("is-playing", isActive);
    });
  }

  // ---------- Render ----------
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
      now.textContent = ""; // kein Platzhalter

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

  // ---------- Player ----------
  async function toggleStation(station) {
    const active = audio.dataset.activeStation;

    // gleiche Station: Play/Pause
    if (active === station.id) {
      if (audio.paused) {
        try { await audio.play(); } catch (e) {}
      } else {
        audio.pause();
      }
      setPlayingTile(active);
      return;
    }

    // neue Station starten
    audio.src = station.stream;
    audio.dataset.activeStation = station.id;

    try { await audio.play(); } catch (e) {}

    // sofort Titel aktualisieren
    pollStation(station);

    setPlayingTile(station.id);
  }

  // ---------- Icecast: Now Playing ----------
  function extractNowPlaying(data) {
    const stats = data?.icestats;
    if (!stats || !stats.source) return null;

    const sources = Array.isArray(stats.source) ? stats.source : [stats.source];
    const s = sources[0];

    const title =
      (s.title || s.yp_currently_playing || s.streamtitle || "")
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

      const title = extractNowPlaying(data);

      // Tile immer aktualisieren
      setText(target, title);

      // Global anzeigen:
      // - wenn Station aktiv ist
      // - oder wenn noch nichts angezeigt wird
      if (
        audio.dataset.activeStation === station.id ||
        !globalNow.textContent
      ) {
        setText(globalNow, title);
      }
    } catch (e) {
      setText(target, "");
      if (audio.dataset.activeStation === station.id) {
        setText(globalNow, "");
      }
    }
  }

  function pollAll() {
    STATIONS.forEach(pollStation);
  }

  // ---------- Events ----------
  audio.addEventListener("play", () =>
    setPlayingTile(audio.dataset.activeStation || "")
  );
  audio.addEventListener("pause", () =>
    setPlayingTile(audio.dataset.activeStation || "")
  );
  audio.addEventListener("ended", () =>
    setPlayingTile(audio.dataset.activeStation || "")
  );

  // ---------- Start ----------
  render();
  pollAll();
  setInterval(pollAll, 5000);
})();
