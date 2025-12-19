set("log.stdout", true)
set("log.level", 2)

ff = playlist(
  mode="shuffle",
  reload_mode="watch",
  "/music/foofighters"
)

th = playlist(
  mode="shuffle",
  reload_mode="watch",
  "/music/thievery"
)

ff_radio = fallback(track_sensitive=false, [ff, blank()])
th_radio = fallback(track_sensitive=false, [th, blank()])

output.icecast(
  %mp3(bitrate=96),
  host="icecast",
  port=8000,
  password="changeme",
  mount="foofighters",
  name="Foo Fighters Radio",
  description="Privater Icecast-Stream mit Titelanzeige",
  genre="Rock",
  ff_radio
)

output.icecast(
  %mp3(bitrate=96),
  host="icecast",
  port=8000,
  password="changeme",
  mount="thievery",
  name="Thievery Corporation Radio",
  description="Privater Icecast-Stream (Thievery) mit Titelanzeige",
  genre="Downtempo",
  th_radio
)
