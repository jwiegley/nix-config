self: super: with self;

let libpng = super.libpng12; in {

transfig = stdenv.mkDerivation rec {
  name = "transfig-3.2.7b";
  src = fetchurl {
    url = https://sourceforge.net/projects/mcj/files/xfig-3.2.7b.tar.xz;
    sha256 = "1khbkbrj9kfwbifqlxqr6m0vw8phk13kry2vk9ahdz5pismc9hdv";
    # date = 2020-02-20T07:45:35-0800;
  };

  buildInputs = with xorg;
    [ zlib libjpeg libpng Xaw3d
      libX11 libXau libXaw libXext libXft libXmu libXpm libXt ];

  hardeningDisable = [ "format" ];

  meta = {
    platforms = stdenv.lib.platforms.unix;
  };
};

fig2dev = stdenv.mkDerivation {
  name = "fig2dev-3.2.7b";
  src = fetchurl {
    url = https://sourceforge.net/projects/mcj/files/fig2dev-3.2.7b.tar.xz;
    sha256 = "1ck8gnqgg13xkxq4hrdy706i4xdgrlckx6bi6wxm1g514121pp27";
    # date = 2020-02-20T07:45:41-0800;
  };

  buildInputs = [ zlib libjpeg libpng xorg.libXpm ];

  hardeningDisable = [ "format" ];

  meta = {
    platforms = stdenv.lib.platforms.unix;
  };
};

}
