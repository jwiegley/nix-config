{ fetchFromGitHub, makeWrapper, pythonPackages, stdenv }:

pythonPackages.buildPythonApplication rec {
  name = "backblaze-b2-${version}";
  version = "0.6.3-pre";

  src = fetchFromGitHub {
    owner = "Backblaze";
    repo = "B2_Command_Line_Tool";
    rev = "bbbf473931a3cd04a801e77dfa86000bc39693c9";
    sha256 = "0rsqkp5q9ri2zapgv4glmfm6whqsws3gyvpx5jcnzjcz23hdymi9";
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
}
