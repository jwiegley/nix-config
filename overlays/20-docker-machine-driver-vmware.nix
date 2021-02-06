self: super: {

docker-machine-driver-vmware = super.buildGoModule rec {

  pname = "docker-machine-driver-vmware";
  version = "0.1.1";

  src = super.fetchFromGitHub {
    owner = "machine-drivers";
    repo = pname;
    rev = "v" + version;
    sha256 = "1sgdmqmqb2c6dfzrhq73dghliic06nbk30i0bggqm24gzp0iqdlg";
  };

  modSha256 = "1sgdmqmqb2c6dfzrhq73dghliic06nbk30i0bggqm24gzp0iqdlg";

  outputs = [ "out" "man" ];

  buildInputs = [ ];

  buildPhase = ''
    make build
  '';

  doCheck = true;
  checkPhase = ''
    make test
  '';


  installPhase = ''
    find .
  '';

  meta = with super.lib; {
    homepage = https://github.com/machine-drivers/docker-machine-driver-vmware;
    description = "Docker machine driver for VMware Fusion and Workstation";
    license = licenses.asl20;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
