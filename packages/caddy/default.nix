{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/duckdns@v0.5.0"
    "github.com/caddy-dns/desec@v1.1.0"
  ];
  hash = "sha256-aAl05t+jtBQDUwrOu8f1at00mPCu/YwJVnTm46futeE=";
}
