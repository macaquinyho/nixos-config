{
  lib,
  pkgs,
  niri,
}:
{
  # names of the workspaces declared in niri.kdl
  workspaces = {
    browser = "";
    terminal = "";
    claude = "";
    chat = "";
  };

  # Moved workspaces are appended on the target monitor, so reapply the order afterwards.
  # A single script keeps the steps sequential, kanshi may run separate exec lines concurrently.
  arrange =
    name: layout:
    pkgs.writeShellScript "kanshi-${name}-workspaces" (
      lib.concatMapStrings (
        { output, workspaces }:
        lib.concatMapStrings (ws: ''
          ${niri} msg action move-workspace-to-monitor --reference "${ws}" "${output}"
        '') workspaces
      ) layout
      + lib.concatMapStrings (
        { workspaces, ... }:
        lib.concatImapStrings (i: ws: ''
          ${niri} msg action move-workspace-to-index --reference "${ws}" ${toString i}
        '') workspaces
      ) layout
    );
}
