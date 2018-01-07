self: super: {

backblaze-b2 = with super; pythonPackages.buildPythonApplication rec {
  name = "backblaze-b2-${version}";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "Backblaze";
    repo = "B2_Command_Line_Tool";
    rev = "5ddc920940344200cf335c7a7336d5e0582b1cc0";
    sha256 = "0697rcdsmxz51p4b8m8klx2mf5xnx6vx56vcf5jmzidh8mc38a6z";
  };

  propagatedBuildInputs = with pythonPackages;
    [ futures requests six tqdm logfury arrow funcsigs ];

  checkPhase = ''
    python test_b2_command_line.py test
  '';

  postInstall = ''
    mv "$out/bin/b2" "$out/bin/backblaze-b2"

    sed 's/^have b2 \&\&$/have backblaze-b2 \&\&/'   -i contrib/bash_completion/b2
    sed 's/^\(complete -F _b2\) b2/\1 backblaze-b2/' -i contrib/bash_completion/b2

    mkdir -p "$out/etc/bash_completion.d"
    cp contrib/bash_completion/b2 "$out/etc/bash_completion.d/backblaze-b2"
  '';

  meta = with stdenv.lib; {
    description = "Command-line tool for accessing the Backblaze B2 storage service";
    homepage = https://github.com/Backblaze/B2_Command_Line_Tool;
    license = licenses.mit;
    maintainers = with maintainers; [ hrdinka kevincox ];
    platforms = platforms.unix;
  };
};

}
