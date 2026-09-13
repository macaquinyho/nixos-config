{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "mcp-victoriametrics";
  version = "1.9.0";

  src = fetchFromGitHub {
    owner = "VictoriaMetrics-Community";
    repo = "mcp-victoriametrics";
    tag = "v${version}";
    hash = "sha256-AmVijE5xadVVgYT3Pnfo4ofTZKoBROE8hkKv80A5Y/o=";
  };

  vendorHash = null; # deps are vendored in-tree

  subPackages = [ "cmd/mcp-victoriametrics" ];

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  meta = {
    description = "MCP server for VictoriaMetrics";
    homepage = "https://github.com/VictoriaMetrics-Community/mcp-victoriametrics";
    license = lib.licenses.asl20;
    mainProgram = "mcp-victoriametrics";
  };
}
