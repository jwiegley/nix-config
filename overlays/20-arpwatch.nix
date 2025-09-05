self: pkgs: with pkgs; {

arpwatch = stdenv.mkDerivation rec {
  pname = "arpwatch";
  version = "3.8";

  src = fetchurl {
    url = "https://ee.lbl.gov/downloads/arpwatch//${pname}-${version}.tar.gz";
    hash = "sha256:175j339kdh2w4l5w0v36dj5kfhlx9cmdjg0p37qv7f1l6ngl0qy7";
  };

  buildInputs = [
    libpcap
  ];

  enableParallelBuilding = true;

  meta = with lib; {
    description = "arpwatch is a computer software tool for monitoring Address Resolution Protocol traffic on a computer network";
    homepage = "https://en.wikipedia.org/wiki/Arpwatch";
    platforms = platforms.unix;
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ jwiegley ];
    mainProgram = "arpwatch";
  };
};

}
