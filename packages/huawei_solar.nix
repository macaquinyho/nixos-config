{
  lib,
  buildHomeAssistantComponent,
  fetchFromGitHub,
  huawei-solar,
  pyserial,
}:

buildHomeAssistantComponent rec {
  owner = "wlcrs";
  domain = "huawei_solar";
  version = "2.1.1";

  src = fetchFromGitHub {
    owner = "wlcrs";
    repo = "huawei_solar";
    rev = version;
    hash = "sha256-GM49nLXBhTWwlSayyE5de9iQhUX7lmCuByYyNxmWkLI=";
  };

  dependencies = [
    huawei-solar
    # config_flow imports serial.tools.list_ports but the manifest doesn't declare it
    pyserial
  ];

  meta = with lib; {
    description = "Home Assistant integration for Huawei Solar inverters via Modbus";
    homepage = "https://github.com/wlcrs/huawei_solar";
    changelog = "https://github.com/wlcrs/huawei_solar/releases/tag/${version}";
    maintainers = with maintainers; [ Toomoch ];
    license = licenses.agpl3Only;
  };
}
