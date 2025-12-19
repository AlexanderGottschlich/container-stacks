# Logs auf STDOUT
set("log.stdout", true)
set("log.level", 1)

# Playlist aus /music, zufällige Wiedergabe
music = playlist(
  mode = "shuffle",
  #reload_mode = "watch",
  "/music"
)

# Fallback, falls keine Titel geliefert werden
radio = fallback(
  track_sensitive = false,
  [music, blank()]
)

# Stream zu Icecast mit Metadaten
output.icecast(
  %mp3(bitrate = 128),
  host        = "icecast",
  port        = 8000,
  password    = "changeme",
  mount       = "foofighters",
  name        = "Foo Fighters Radio",
  description = "Privater Icecast-Stream mit Titelanzeige",
  genre       = "Rock",
  radio
)

