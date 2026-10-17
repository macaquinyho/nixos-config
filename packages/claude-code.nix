{
  lib,
  claude-code,
  mcp-victoriametrics,
  writeText,
  nixd,
  ty,
  rust-analyzer,

  extraMcpServers ? { },
}:
# claude-code is passed in from numtide/llm-agents.nix (see flake.nix). The
# language servers it gets on PATH come from our nixpkgs (callPackage args).
let
  mcpConfig = writeText "claude-mcp.json" (
    builtins.toJSON {
      mcpServers = {
        victoriametrics = {
          command = lib.getExe mcp-victoriametrics;
          env = {
            VM_INSTANCE_ENTRYPOINT = "https://vmetrics.oxigen.smd.dev";
            VM_INSTANCE_TYPE = "single";
          };
        };
        "gitlab.com" = {
          type = "http";
          url = "https://gitlab.com/api/v4/mcp";
        };
      }
      // extraMcpServers;
    }
  );
in
claude-code.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    wrapProgram $out/bin/claude \
      --add-flags "--mcp-config ${mcpConfig}" \
      --prefix PATH : ${
        lib.makeBinPath [
          nixd
          ty
          rust-analyzer
        ]
      }
  '';
})
