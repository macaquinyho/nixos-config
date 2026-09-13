{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  holidays,
}:

buildHomeAssistantComponent rec {
  owner = "hectorespert";
  domain = "som_energia";
  version = "2026.4.3";

  src = fetchFromGitHub {
    inherit owner;
    repo = "som-energia-hass";
    rev = version;
    hash = "sha256-Oi/8yBK4IpZEbjVxkK3l88GrBm0RTed+RXDiV2IvSKo=";
  };

  dependencies = [
    holidays
  ];

  meta = with lib; {
    description = "Integration for Home Assistant of Som Energia";
    homepage = "https://github.com/hectorespert/som-energia-hass";
    changelog = "https://github.com/hectorespert/som-energia-hass/releases/tag/${version}";
    maintainers = with maintainers; [ Toomoch ];
    license = licenses.asl20;
  };
}
