{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/duckdns@v0.5.0"
    "github.com/caddy-dns/desec@v1.1.0"
  ];
  hash = "sha256-9B8RL+ZCFCXhl/ANR0Dq4YfY5RV5sO7qZcqypWdN1dk=";
}
