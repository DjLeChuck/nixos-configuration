{
  nas = {
    hostname = "192.168.0.0";
    port = 22;
    user = "changeme";
  };
  wifi = {
    home = {
      ssid = "my-ssid";
    };
  };
  development = "/path/to/development";
  privateTools = {
    gitlabHost = "gitlab.host.com";
    lockExcel = {
      url = "https://gitlab.host.com/api/v4/projects/<project-path>/packages/generic/<package-name>/<version>/<binary-name>";
      sha256 = "sha256-XXXXX";
    };
    excel2jsonl = {
      url = "https://gitlab.host.com/api/v4/projects/<project-path>/packages/generic/<package-name>/<version>/<binary-name>";
      sha256 = "sha256-XXXXX";
    };
  };
}
