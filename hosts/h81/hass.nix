{
  config,
  pkgs,
  flake-root,
  ...
}:
let

  huawei_solar = pkgs.callPackage (flake-root + "/packages/huawei_solar.nix") {
    inherit huawei-solar;
    inherit (pkgs.home-assistant.python3Packages) pyserial;
  };
  tmodbus = pkgs.callPackage (flake-root + "/packages/tmodbus.nix") {
    inherit (pkgs.home-assistant.python3Packages)
      buildPythonPackage
      hatchling
      hatch-vcs
      pytest-asyncio
      pytestCheckHook
      serialx
      tenacity
      ;
  };
  huawei-solar = pkgs.callPackage (flake-root + "/packages/huawei-solar.nix") {
    inherit (pkgs.home-assistant.python3Packages)
      buildPythonPackage
      hatchling
      hatch-vcs
      pytest-asyncio
      pytestCheckHook
      ;
    inherit tmodbus;
  };
  som-energia-hass = pkgs.callPackage (flake-root + "/packages/som-energia-hass.nix") {
    inherit (pkgs.home-assistant.python3Packages) holidays;
  };

in
{
  #virtualisation.oci-containers.containers.homeassistant = {
  #  image = "ghcr.io/home-assistant/home-assistant:stable";
  #  ports = [ "8123:8123" ];
  #  volumes = [
  #    "${config.custom.homelab.serviceDataDir}/hass:/config:Z"
  #    "${./homeassistant-configuration.yaml}:/config/configuration.yaml:ro"
  #  ];
  #  environment = { TZ = "Europe/Madrid"; };
  #  extraOptions = [

  #    "--pull=always"
  #    "--network=host"
  #    #"--device=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0:/dev/ttyUSB0:rw"
  #  ];

  #};
  users.users.hass = {
    extraGroups = [
      "dialout" # Allow access to serial device (for Arduino dev)
    ];
  };

  services.caddy.virtualHosts."homeassistant.${config.custom.homelab.primaryDomain}" = {
    extraConfig = ''
      reverse_proxy localhost:${toString config.services.home-assistant.config.http.server_port}
    '';
  };

  systemd.services.home-assistant = {
    serviceConfig.DeviceAllow = "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0 rw";
  };

  services.home-assistant = {
    enable = true;
    openFirewall = true;
    customComponents = [
      huawei_solar
      som-energia-hass
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
      "melcloud"
      "lg_netcast"
      "tuya"
      "androidtv"
      # huawei_solar's config flow imports homeassistant.components.usb and pyserial
      "usb"
    ];
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      universal-remote-card
      mini-media-player
    ];

    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };

      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "::1"
          "127.0.0.1"
        ];
      };
    };
  };
}
