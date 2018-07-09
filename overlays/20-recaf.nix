self: super: {

recaf = with self; stdenv.mkDerivation rec {
  pname = "recaf";
  version = "1.4.0";

  name = "${pname}-${version}";

  src = fetchurl {
    url = "https://github.com/Col-E/Recaf/releases/download/${version}/recaf-${version}.jar";
    sha256 = "18hzj87lgp1jhfsfv514086m7h13hi5qmwpk326761sigvvvhqzb";
    # date = 2018-07-05T00:23:27-0700;
  };

  buildInputs = [ jdk8 ];

  jarfile = "$out/share/java/${pname}/Recaf.jar";

  unpackPhase = "true";

  dontBuild = true;

  installPhase = ''
    mkdir -p "$out/bin"
    echo > "$out/bin/${pname}" "#!/bin/sh"
    echo >>"$out/bin/${pname}" "${jdk8}/bin/java -Xmx512m -cp ${jdk8}/lib/tools.jar -jar ${jarfile}"
    chmod +x "$out/bin/${pname}"
    install -D -m644 ${src} ${jarfile}
  '';

  meta = {
    homepage = https://col-e.github.io/Recaf;
    description = "Recaf is an open-source Java bytecode editor based on Objectweb's ASM";
    license = "LGPL";

    longDescription = ''
      Recaf is an open-source Java bytecode editor based on Objectweb's ASM.
      ASM is a library that abstracts away the constant pool and class-file
      attributes. Since keeping track of the constant pool or managing
      proper stackframes are no longer necessary, complex changes can be
      made with relative ease. With additional features to assist in the
      process of editing Recaf is the most feature rich free bytecode editor
      available.
    '';

    platforms = stdenv.lib.platforms.unix;
  };
};

}
