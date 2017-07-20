{ stdenv, fetchgit, coq, coqPackages, ocamlPackages, compcert, which, unzip
, tools ? stdenv.cc
}:

stdenv.mkDerivation {
  name = "vellvm-dsss-${coq.coq-version}-20170710";
  src = fetchgit {
    url = "https://github.com/vellvm/vellvm.git";
    rev = "5e0f2c979e080513ba829878b7ff38d403809c73";
    sha256 = "07miyimbin31m890i063f8lwln42blljfxkgkim8ms9cm6glyfd3";
  };

  buildInputs = [ coq.ocaml coq.camlp5 which unzip ]
    ++ (with ocamlPackages; [ findlib menhir ]);
  propagatedBuildInputs = [ coq ];

  enableParallelBuilding = true;

  configurePhase = ''
    sh -x
    (cd lib; unzip ${coqPackages.paco.src})
    (cd lib; tar xvzf ${compcert.src})
    mv lib/CompCert-${compcert.version} lib/compcert
    substituteInPlace lib/compcert/configure --replace '{toolprefix}gcc' '{toolprefix}cc'
    (cd lib/compcert; ./configure -clightgen -prefix $out -toolprefix ${tools}/bin/ ''
      + (if stdenv.isDarwin then "ia32-macosx" else "ia32-linux") + '')'';

  buildPhase = ''
    (cd lib/compcert; make)
    (cd lib/paco/src; make)
    (cd src; make)
  '';

  meta = with stdenv.lib; {
    homepage = https://www.cis.upenn.edu/~stevez/vellvm/;
    license = licenses.gpl3;
    maintainers = [ maintainers.jwiegley ];
    platforms = coq.meta.platforms;
  };

}
