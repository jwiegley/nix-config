{ lib, runCommand }:

let
  overlay = import ../../../overlays/ai/30-ai-llm.nix;
  source = (import ../../../packages/source-catalog.nix "ai").llama-cpp;

  linuxPackages = overlay { } {
    stdenv.hostPlatform.isDarwin = false;
    llama-cpp = {
      marker = "linux-upstream";
      override = _: throw "llama-cpp must not be overridden on Linux";
    };
  };
  linuxResult = linuxPackages.llama-cpp;
  linuxValidation = builtins.tryEval linuxPackages.llama-cpp-update-validator;

  darwinPackages = overlay { nodejs_22 = "nodejs-22"; } {
    stdenv.hostPlatform.isDarwin = true;
    llama-cpp.override = {
      __functionArgs.nodejs_latest = false;
      __functor = _self: args: {
        overrideAttrs =
          update:
          let
            attrs = update {
              patches = [ "existing.patch" ];
              cmakeFlags = [
                "-DKEEP=ON"
                "-DLLAMA_BUILD_NUMBER:STRING=${source.version}"
              ];
            };
          in
          {
            inherit args attrs;
            marker = "darwin-override";
          };
      };
    };
    inherit lib;
    fetchFromGitHub = args: args;
    fetchNpmDeps = args: args;
  };
  darwinResult = darwinPackages.llama-cpp;
  darwinValidation = darwinPackages.llama-cpp-update-validator;

  legacyDarwinPackages = overlay { } {
    stdenv.hostPlatform.isDarwin = true;
    lib.warn = message: value: builtins.trace message value;
    llama-cpp = {
      marker = "legacy-darwin-upstream";
      override = {
        __functionArgs = { };
        __functor = _self: _: throw "legacy llama-cpp must not be overridden";
      };
    };
  };
  legacyDarwinResult = legacyDarwinPackages.llama-cpp;
  legacyDarwinValidation = builtins.tryEval legacyDarwinPackages.llama-cpp-update-validator;
in
assert linuxResult.marker == "linux-upstream";
assert !linuxValidation.success;
assert legacyDarwinResult.marker == "legacy-darwin-upstream";
assert !legacyDarwinValidation.success;
assert darwinResult.marker == "darwin-override";
assert darwinValidation.marker == "darwin-override";
assert darwinResult.args.nodejs_latest == "nodejs-22";
assert darwinResult.attrs.version == source.version;
assert
  darwinResult.attrs.cmakeFlags == [
    "-DKEEP=ON"
    "-DLLAMA_BUILD_NUMBER:STRING=0"
    "-DLLAMA_BUILD_IS_DEV:BOOL=OFF"
  ];
assert !(lib.hasInfix "LLAMA_BUILD_COMMIT" darwinResult.attrs.preConfigure);
assert darwinResult.attrs.npmRoot == "tools/ui";
assert darwinResult.attrs.npmDeps.patches == [ "existing.patch" ];
runCommand "llama-cpp-platform-compat" { } "touch $out"
