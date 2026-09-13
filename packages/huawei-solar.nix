{
  buildPythonPackage,
  fetchFromGitHub,
  lib,
  hatchling,
  hatch-vcs,
  tmodbus,
  pytest-asyncio,
  pytestCheckHook,
}:

buildPythonPackage rec {
  pname = "huawei-solar";
  version = "3.0.6";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "wlcrs";
    repo = "huawei-solar-lib";
    tag = "v${version}";
    hash = "sha256-BpA3zYgFcIvP+6SYbFlc685mJK1E3ro/qIF4la5BgnU=";
  };

  build-system = [
    hatchling
    hatch-vcs
  ];

  dependencies = [
    tmodbus
  ]
  ++ tmodbus.optional-dependencies.async-serial
  # tmodbus unconditionally imports its smart transport, which needs tenacity
  ++ tmodbus.optional-dependencies.smart;

  nativeCheckInputs = [
    pytest-asyncio
    pytestCheckHook
  ];

  pythonImportsCheck = [ "huawei_solar" ];

  meta = with lib; {
    description = "Python library for connecting to Huawei SUN2000 Inverters over Modbus";
    homepage = "https://github.com/wlcrs/huawei-solar-lib";
    changelog = "https://github.com/wlcrs/huawei-solar-lib/releases/tag/v${version}";
    maintainers = with maintainers; [ Toomoch ];
    license = licenses.agpl3Only;
  };
}
