{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/duckdns@v0.5.0"
    "github.com/caddy-dns/desec@v1.1.0"
  ];
  hash = "sha256-u3r3KXarewMKk+IRbsIGmqn6oSQeMRnqwvyveYtAyTw=";
}
