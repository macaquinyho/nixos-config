{
  fetchFromGitHub,
  hugo,
  lib,
  stdenvNoCC,
  src,
}:
let
  # config.toml sets theme = "hugo-theme-stack", so it has to land under that
  # name in themes/. Bump rev and hash together.
  theme = fetchFromGitHub {
    owner = "CaiJimmy";
    repo = "hugo-theme-stack";
    rev = "087989e4274f24a472d16d7c35d394a227fed47a";
    hash = "sha256-YCNAT14hEfVj6yII+FehTvbu0qTAVgR9XLZC/0/rrE4=";
  };
in
stdenvNoCC.mkDerivation {
  name = "blog";
  inherit src;

  nativeBuildInputs = [ hugo ];

  postPatch = ''
    mkdir -p themes
    cp -r ${theme} themes/hugo-theme-stack
  '';

  buildPhase = ''
    hugo --minify
  '';

  installPhase = ''
    cp -r public $out
  '';

  meta = {
    description = "Toomoch help blog";
    platforms = lib.platforms.all;
  };
}
