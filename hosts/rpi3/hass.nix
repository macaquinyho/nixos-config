{
  config,
  pkgs,
  flake-root,
  private,
  ...
}:
{
  systemd.services.home-assistant.serviceConfig.AmbientCapabilities = "CAP_NET_BIND_SERVICE";
  systemd.services.home-assistant.serviceConfig.CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";

  # bind home-assistant directly to save on resources cuz poor pi3
  services.home-assistant = {
    enable = true;
    openFirewall = true;
    port = 443;
    customComponents = [
      pkgs.home-assistant-custom-components.tuya_local
    ];
    extraComponents = [
      # Components required to complete the onboarding
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"
      "tuya"
      "androidtv"
      "xiaomi_miio"
    ];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      universal-remote-card
      mini-media-player
    ];

    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };

    };
  };
}
