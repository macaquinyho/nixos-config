{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/caddy-dns/desec@v1.1.0"
  ];
  hash = "sha256-HrLRezw+q5+dRdJS662686n7xsImSxNb3UqlSo61R8E=";
}
