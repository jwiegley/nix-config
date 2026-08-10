{
  configured,
  lib,
  runCommand,
}:

let
  overlay = import ../overlays/10-coq.nix;
  attrs = overlay configured configured;
  fakeCoq = version: {
    override = args: { inherit args version; };
  };
  fakePrev = {
    mkCoqPackages = coq: { inherit coq; };
    coq_8_19 = fakeCoq "8.19";
    coq_8_20 = fakeCoq "8.20";
    coq_9_0 = fakeCoq "9.0";
    coq_9_1 = fakeCoq "9.1";
  };
  fakeFinal = fakePrev // fakeAttrs;
  fakeAttrs = overlay fakeFinal fakePrev;
  expected = [
    "coq"
    "coqPackages"
    "coqPackages_8_19"
    "coqPackages_8_20"
    "coqPackages_9_0"
    "coqPackages_9_1"
    "coq_8_19"
    "coq_8_20"
    "coq_9_0"
    "coq_9_1"
  ];
in
assert lib.sort builtins.lessThan (builtins.attrNames attrs) == expected;
assert attrs.coq == configured.coq_9_1;
assert attrs.coqPackages == configured.coqPackages_9_1;
assert lib.all (name: fakeAttrs.${name}.args.buildIde == false) [
  "coq_8_19"
  "coq_8_20"
  "coq_9_0"
  "coq_9_1"
];
runCommand "coq-overlay-contract" { } "touch $out"
