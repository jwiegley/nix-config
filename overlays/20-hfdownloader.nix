self: super: {

hfdownloader = with super; buildGoModule rec {
  pname = "hfdownloader";
  version = "1.4.2";
  vendorHash = "sha256-0tAJEPJQJTUYoV0IU2YYmSV60189rDRdwoxQsewkMEU=";

  src = fetchFromGitHub {
    owner = "bodaay";
    repo = "HuggingFaceModelDownloader";
    rev = "${version}";
    hash = "sha256-sec+NGh1I5YmQif+ifm+AJmG6TVKOW/enffh8UE0I+E=";
  };

  meta = with lib; {
    description = "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
    homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
    license = licenses.asl20;
    maintainers = [ maintainers.jwiegley ];
  };
};

}
