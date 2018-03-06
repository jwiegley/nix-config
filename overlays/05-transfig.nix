self: super: let libpng = super.libpng12; in {

transfig = with super; stdenv.mkDerivation rec {
  name = "transfig-3.2.6a";
  src = fetchurl {
    url = https://sourceforge.net/projects/mcj/files/xfig-3.2.6a.tar.xz;
    sha256 = "0z1636w27hvgjpq98z40k8h535b4x2xr2whkvr7bibaa89fynym8";
  };

  buildInputs = with xorg;
    [ zlib libjpeg libpng Xaw3d
      libX11 libXau libXaw libXext libXft libXmu libXpm libXt ];

  hardeningDisable = [ "format" ];

  meta = {
    platforms = stdenv.lib.platforms.unix;
  };
};

fig2dev = with super; stdenv.mkDerivation {
  name = "fig2dev-3.2.6a";
  src = fetchurl {
    url = https://sourceforge.net/projects/mcj/files/fig2dev-3.2.6a.tar.xz;
    sha256 = "19v72vvlri064s5f7s7id51m8nxn9gajvs4y36rv8ggqlkcs6qay";
  };

  buildInputs = [ zlib libjpeg libpng xorg.libXpm ];

  hardeningDisable = [ "format" ];

  meta = {
    platforms = stdenv.lib.platforms.unix;
  };
};

}
