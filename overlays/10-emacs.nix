self: pkgs:

let
  myEmacsPackageOverrides = self: super:
    let
      inherit (pkgs) fetchurl fetchgit fetchFromGitHub stdenv;
      inherit (stdenv) lib mkDerivation;

      withPatches = pkg: patches:
        pkg.overrideAttrs(attrs: { inherit patches; });

      compileEmacsFiles = pkgs.callPackage ./emacs/builder.nix;

      addBuildInputs = pkg: inputs: pkg.overrideAttrs (attrs: {
        buildInputs = attrs.buildInputs ++ inputs;
      });

      compileLocalFile = name: compileEmacsFiles {
        inherit name;
        src = ./emacs + ("/" + name);
      };

      fetchFromEmacsWiki = pkgs.callPackage ({ fetchurl, name, sha256 }:
        fetchurl {
          inherit sha256;
          url = "https://www.emacswiki.org/emacs/download/" + name;
        });

      compileEmacsWikiFile = { name, sha256, buildInputs ? [], patches ? [] }:
        compileEmacsFiles {
          inherit name buildInputs patches;
          src = fetchFromEmacsWiki { inherit name sha256; };
        };

    in {

    seq = if super.emacs.version == "27.0"
      then mkDerivation rec {
        name = "seq-stub";
        version = "stub";
        src = ./.;
        phases = [ "installPhase" ];
        installPhase = ''
          mkdir $out
          touch $out/.empty
        '';
      }
      else super.seq;


    edit-env        = compileLocalFile "edit-env.el";
    edit-var        = compileLocalFile "edit-var.el";
    ox-extra        = compileLocalFile "ox-extra.el";
    rs-gnus-summary = compileLocalFile "rs-gnus-summary.el";
    supercite       = compileLocalFile "supercite.el";


    magit-annex      = addBuildInputs super.magit-annex        [ pkgs.git ];
    magit-filenotify = addBuildInputs super.magit-filenotify   [ pkgs.git ];
    magit-gitflow    = addBuildInputs super.magit-gitflow      [ pkgs.git ];
    magit-imerge     = addBuildInputs super.magit-imerge       [ pkgs.git ];
    magit-lfs        = addBuildInputs super.magit-lfs          [ pkgs.git ];
    magit-tbdiff     = addBuildInputs super.magit-tbdiff       [ pkgs.git ];
    orgit            = addBuildInputs super.orgit              [ pkgs.git ];


    company-coq   = withPatches super.company-coq   [ ./emacs/patches/company-coq.patch ];
    esh-buf-stack = withPatches super.esh-buf-stack [ ./emacs/patches/esh-buf-stack.patch ];
    helm-google   = withPatches super.helm-google   [ ./emacs/patches/helm-google.patch ];
    magit         = withPatches super.magit         [ ./emacs/patches/magit.patch ];
    noflet        = withPatches super.noflet        [ ./emacs/patches/noflet.patch ];
    org-ref       = withPatches super.org-ref       [ ./emacs/patches/org-ref.patch ];
    pass          = withPatches super.pass          [ ./emacs/patches/pass.patch ];


    ascii = compileEmacsWikiFile {
      name = "ascii.el";
      sha256 = "1ijpnk334fbah94vm7dkcd2w4zcb0l7yn4nr9rwgpr2l25llnr0f";
      # date = 2019-10-16T16:51:27-0700;
    };

    backup-each-save = compileEmacsWikiFile {
      name = "backup-each-save.el";
      sha256 = "0b9vvi2m0fdv36wj8mvawl951gjmg3pypg08a8n6rzn3rwg0fwz7";
      # date = 2019-04-03T08:43:18-0700;
    };

    browse-kill-ring-plus = compileEmacsWikiFile {
      name = "browse-kill-ring+.el";
      sha256 = "14118rimjsps94ilhi0i9mwx7l69ilbidgqfkfrm5c9m59rki2gq";
      # date = 2019-04-03T08:43:20-0700;

      buildInputs = [ self.browse-kill-ring ];
      patches = [ ./emacs/patches/browse-kill-ring-plus.patch ];
    };

    col-highlight = compileEmacsWikiFile {
      name = "col-highlight.el";
      sha256 = "0na8aimv5j66pzqi4hk2jw5kk00ki99zkxiykwcmjiy3h1r9311k";
      # date = 2019-04-03T08:43:22-0700;

      buildInputs = [ self.vline ];
    };

    crosshairs = compileEmacsWikiFile {
      name = "crosshairs.el";
      sha256 = "0032v3ry043wzvbacm16liykc362pza1bc46x37b307bvbv12qlg";
      # date = 2019-04-03T08:43:25-0700;

      buildInputs = [ self.hl-line-plus self.col-highlight self.vline ];
    };

    cursor-chg = compileEmacsWikiFile {
      name = "cursor-chg.el";
      sha256 = "1zmwh0z4g6khb04lbgga263pqa51mfvs0wfj3y85j7b08f2lqnqn";
      # date = 2019-04-03T08:43:27-0700;
    };

    dired-plus = compileEmacsWikiFile {
      name = "dired+.el";
      sha256 = "15g6nbfkb0p4irgk3jjmbaayrvqp39jyhd2yg361hy4gjh9gl8ln";
      # date = 2020-02-11T09:10:20-0800;
    };

    erc-highlight-nicknames = compileEmacsWikiFile {
      name = "erc-highlight-nicknames.el";
      sha256 = "01r184q86aha4gs55r2vy3rygq1qnxh1bj9qmlz97b2yh8y17m50";
      # date = 2019-04-03T08:43:29-0700;
    };

    fetchmail-mode = compileEmacsWikiFile {
      name = "fetchmail-mode.el";
      sha256 = "19lqkc35kgzm07xjpb9nrcayg69qyijn159lak0mg45fhnybf4a6";
      # date = 2019-04-03T08:43:31-0700;
    };

    hexrgb = compileEmacsWikiFile {
      name = "hexrgb.el";
      sha256 = "18hb8brf7x92aidjfgczxangri6rkqq4x5d06lh41193f97rslm8";
      # date = 2019-04-03T08:43:33-0700;
    };

    highlight = compileEmacsWikiFile {
      name = "highlight.el";
      sha256 = "1a94xsjd98qdl06vmq8mi7rsygbngh97iqk5hbibxhbpwjz0njfw";
      # date = 2019-08-21T17:38:13-0700;
    };

    highlight-cl = compileEmacsWikiFile {
      name = "highlight-cl.el";
      sha256 = "0r3kzs2fsi3kl5gqmsv75dc7lgfl4imrrqhg09ij6kq1ri8gjxjw";
      # date = 2019-08-21T17:38:10-0700;
    };

    hl-line-plus = compileEmacsWikiFile {
      name = "hl-line+.el";
      sha256 = "0crkmjah8i61z6c15sgn2cbpbj8xqfx0py1y84pxkcjh1cj7hx7q";
      # date = 2019-04-03T08:43:37-0700;
    };

    message-x = compileEmacsWikiFile {
      name = "message-x.el";
      sha256 = "05ic97plsysh4nqwdrsl5m9f24m11w24bahj8bxzfdawfima2bkf";
      # date = 2019-04-03T08:43:39-0700;
    };

    palette = compileEmacsWikiFile {
      name = "palette.el";
      sha256 = "149y6bmn0njgq632m9zdnaaw7wrvxvfqndpqlgcizn6dwzixiih6";
      # date = 2019-04-03T08:43:41-0700;

      buildInputs = [ self.hexrgb ];
    };

    popup-pos-tip = compileEmacsWikiFile {
      name = "popup-pos-tip.el";
      sha256 = "0dhyzfsl01y61m53iz38a1vcvclr98wamsh0nishw0by1dnlb17x";
      # date = 2019-04-03T08:51:23-0700;

      buildInputs = [ self.popup self.pos-tip ];
    };

    popup-ruler = compileEmacsWikiFile {
      name = "popup-ruler.el";
      sha256 = "0fszl969savcibmksfkanaq11d047xbnrfxd84shf9z9z2i3dr43";
      # date = 2019-04-03T08:51:26-0700;
    };

    pp-c-l = compileEmacsWikiFile {
      name = "pp-c-l.el";
      sha256 = "03mhd8lja71163jg6fj4d4hy2dwb1c5j46sn9yq6m9wz413a4pmd";
      # date = 2019-04-03T08:51:27-0700;
    };

    tidy = compileEmacsWikiFile {
      name = "tidy.el";
      sha256 = "0psci55a3angwv45z9i8wz8jw634rxg1xawkrb57m878zcxxddwa";
      # date = 2019-04-03T08:51:29-0700;
    };

    vline = compileEmacsWikiFile {
      name = "vline.el";
      sha256 = "1ys6928fgk8mswa4gv10cxggir8acck27g78cw1z3pdz5gakbgnj";
      # date = 2019-04-03T08:51:30-0700;
    };

    xml-rpc = compileEmacsWikiFile {
      name = "xml-rpc.el";
      sha256 = "0mdqa9w1p6cmli6976v4wi0sw9r4p5prkj7lzfd1877wk11c9c73";
      # date = 2019-11-02T12:59:10-0700;
    };

    xray = compileEmacsWikiFile {
      name = "xray.el";
      sha256 = "1s25z9iiwpm1sp3yj9mniw4dq7dn0krk4678bgqh464k5yvn6lyk";
      # date = 2019-10-16T16:58:04-0700;
    };

    yaoddmuse = compileEmacsWikiFile {
      name = "yaoddmuse.el";
      sha256 = "0h3s3mdfz0czgz1cj415k170g7mbbqmsinw0xr7qmk050i154iis";
      # date = 2019-04-03T08:51:34-0700;
    };


    bytecomp-simplify = compileEmacsFiles {
      name = "bytecomp-simplify.el";
      src = fetchurl {
        url = https://download.tuxfamily.org/user42/bytecomp-simplify.el;
        sha256 = "1yq0wqgva8yidyd46cqag0ds0cyzl7q8rpd2cmksp68k4zlsxwyv";
        # date = 2019-06-25T12:42:17-0700;
      };
    };

    # jww (2018-01-16): This is present in melpaPackages, but does not build.
    cmake-mode = compileEmacsFiles {
      name = "cmake-mode.el";
      src = fetchurl {
        url = https://raw.githubusercontent.com/Kitware/CMake/master/Auxiliary/cmake-mode.el;
        sha256 = "1a0dsw8cs29v6j7iji24d9k089f6q5wxjy5a0p1vfflfwa6i20ch";
        # date = 2019-08-21T17:37:59-0700;
      };
    };

    jobhours = compileEmacsFiles {
      name = "jobhours";
      src = ~/src/hours;
    };

    nf-procmail-mode = compileEmacsFiles {
      name = "nf-procmail-mode.el";
      src = fetchurl {
        url = http://www.splode.com/~friedman/software/emacs-lisp/src/nf-procmail-mode.el;
        sha256 = "1a7byym62g2rjh2grrqh1g51p05cibp6k83581xyn7fai5f4hxx3";
        # date = 2019-04-03T08:51:58-0700;
      };
    };

    tablegen-mode = compileEmacsFiles {
      name = "tablegen-mode.el";
      src = fetchurl {
        url = https://raw.githubusercontent.com/llvm-mirror/llvm/master/utils/emacs/tablegen-mode.el;
        sha256 = "0dy0diiqfz91blrkpbfxc5ky0l7ghkqi72ah7sh9jkrqa8ss7isy";
        # date = 2019-10-16T16:55:59-0700;
      };
    };


    anki-editor = compileEmacsFiles {
      name = "anki-editor";
      src = fetchFromGitHub {
        owner = "louietan";
        repo = "anki-editor";
        rev = "084ffad14fa700ad1ba95d8cbfe4a8f6052e2408";
        sha256 = "0zjd5yid333shvjm4zy3p7zdpa09xcl96gc4wvi2paxjad6iqhwz";
        # date = 2019-09-22T20:23:39+08:00;
      };
      buildInputs = with self; [ dash request ];
    };

    asoc = compileEmacsFiles {
      name = "asoc";
      src = fetchFromGitHub {
        owner = "troyp";
        repo = "asoc.el";
        rev = "4a3309a9f250656da6f4a9d34feedf4f5666b17a";
        sha256 = "1ls4j4fqx33wd2y2fwdh6bagpp04zqhc35p2wy77axmkz9lv5qpv";
        # date = 2017-09-17T22:08:18+10:00;
      };
    };

    bookmark-plus = compileEmacsFiles {
      name = "bookmark-plus";
      src = fetchFromGitHub {
        owner = "emacsmirror";
        repo = "bookmark-plus";
        rev = "b09ceff50417051f9b720e3da1e49e102a434fd6";
        sha256 = "0z5qspy01lr54ajfspfviah6l7lhyfnmgbjji76k5alpcxb7s4hw";
        # date = 2019-10-29T21:32:58+01:00;
      };
    };

    cell-mode = compileEmacsFiles {
      name = "cell-mode";
      src = fetchgit {
        url = http://gitlab.com/dto/cell.el.git;
        rev = "c7094eb2d8101988339b0a95ca7a4d4708901e68";
        sha256 = "00kgish9q8j5l6kg6n80a83a3dpbmkqqm2idqws41gsniyxaa93b";
        # date = 2019-09-15T23:00:16-04:00;
      };
    };

    counsel-jq = compileEmacsFiles {
      name = "counsel-jq";
      src = fetchFromGitHub {
        owner = "200ok-ch";
        repo = "counsel-jq";
        rev = "b14dfc5c18d991c3b3051c3cbb244d5923b3a327";
        sha256 = "0f5h7nnqrkzbyxi4mgzahqzylszrqb25l3i24ml8yra2a23nl2w8";
        # date = 2019-12-07T14:34:24+01:00;
      };
      buildInputs = with self; [ swiper ivy ];
    };

    deadgrep = compileEmacsFiles {
      name = "deadgrep";
      src = fetchFromGitHub {
        owner = "Wilfred";
        repo = "deadgrep";
        rev = "06764269582b2f844ae2a163d2fece8143b1c578";
        sha256 = "0q3gjwi803xaw79y37nz0bccyss6n520bfkfr6z0ncya422la0hz";
        # date = 2020-01-12T11:14:54+00:00;
      };
      buildInputs = with self; [ s dash spinner ];
    };

    emacs-load-time = compileEmacsFiles {
      name = "emacs-load-time";
      src = fetchFromGitHub {
        owner = "fniessen";
        repo = "emacs-load-time";
        rev = "9d31686a76e9792bd06e49ff77c662065ded015c";
        sha256 = "0zhrfidcxqfld7y67pysdlcvrprrka9sq8065ygqx5yxjb7mxs32";
        # date = 2014-10-10T16:52:58+02:00;
      };
    };

    erc-yank = compileEmacsFiles {
      name = "erc-yank";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "erc-yank";
        rev = "d4dfcf3a0386c3a4a28f8d4de4ae664f253e817c";
        sha256 = "0sa1qx549wlswa3xnmmpb8a3imny0q8mfvqw8iki5l3sh60rfax9";
        # date = 2017-01-20T15:26:06-08:00;
      };
    };

    feebleline = compileEmacsFiles {
      name = "feebleline";
      src = fetchFromGitHub {
        owner = "tautologyclub";
        repo = "feebleline";
        rev = "b2f2db25cac77817bf0c49ea2cea6383556faea0";
        sha256 = "0f2nynx9sib29qi3zkfkgxlcfrwz607pgg6qvvk4nnads033p1yn";
        # date = 2019-08-22T16:01:05+02:00;
      };
    };

    fence-edit = compileEmacsFiles {
      name = "fence-edit";
      src = fetchFromGitHub {
        owner = "aaronbieber";
        repo = "fence-edit.el";
        rev = "d05f82fb99f787b24cdf5f77dc90fab0d6e00761";
        sha256 = "0sdmc89ycrxnfj25dva86sqa8x5rjfs6jg7gvpwrvgq2126hzqvh";
        # date = 2019-04-03T06:20:48-04:00;
      };
    };

    git-undo = compileEmacsFiles {
      name = "git-undo";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "git-undo-el";
        rev = "cf31e38e7889e6ade7d2d2b9f8719fd44f52feb5";
        sha256 = "10f9h8dby3ygkjqwizrif7v1wpwc8iqam5bvayahrabs87s0lnbi";
        # date = 2019-12-21T11:05:45-08:00;
      };
    };

    github-review = compileEmacsFiles {
      name = "github-review";
      src = fetchFromGitHub {
        owner = "charignon";
        repo = "github-review";
        rev = "e8a275939e1a774c84b71ab3df2ce1599445dab0";
        sha256 = "1swpfk3p82nj2rsnfdzllkrf5i0ya4s3zpi96w6afy1vp5kcgf2r";
        # date = 2020-01-11T13:41:10-08:00;
      };
      buildInputs = with self; [ ghub dash graphql treepy s ];
    };

    ghub-plus = compileEmacsFiles {
      name = "ghub-plus";
      src = fetchFromGitHub {
        owner = "vermiculus";
        repo = "ghub-plus";
        rev = "b1adef2402d7599911d4dd447a987a0cea04e6fe";
        sha256 = "0bzri6s5mwvgir9smkz68d5cgcf4glpdmcj8dz8rjxziwrg6k5bz";
        # date = 2019-12-29T11:48:21-06:00;
      };
      buildInputs = with self; [ ghub apiwrap dash graphql treepy ];
    };

    gnus-harvest = compileEmacsFiles {
      name = "gnus-harvest";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "gnus-harvest";
        rev = "feda071a87b799bd5d23cacde3ee71f0b166e75d";
        sha256 = "08zb7vc3v3wdxkzgi902vlc5ybfvm8fxrvm5drnwfsjj9873pbcb";
        # date = 2018-02-08T11:20:21-08:00;
      };
    };

    goto-line-preview = compileEmacsFiles {
      name = "goto-line-preview";
      src = fetchFromGitHub {
        owner = "jcs090218";
        repo = "goto-line-preview";
        rev = "1f0afb261a4e4a1b0a2fae3959b0ce5d30bce2a1";
        sha256 = "03csbs9mh9jjw21sncvnlmm97waazy0c57jp1jynwhzzsbp0k0rs";
        # date = 2019-12-19T14:43:02+08:00;
      };
    };

    gud-lldb = compileEmacsFiles {
      name = "gud-lldb";
      src = fetchFromGitHub {
        owner = "jojojames";
        repo = "gud-lldb";
        rev = "8e68eef3a14f2a372577fd160d38d438a533c6a9";
        sha256 = "19ab404khsiflhczc2xzdhsqrxlhzi90m4b2wzwb5q5mizivl2y6";
        # date = 2017-04-14T17:22:24-07:00;
      };
    };

    indent-shift = compileEmacsFiles {
      name = "indent-shift";
      src = fetchFromGitHub {
        owner = "ryuslash";
        repo = "indent-shift";
        rev = "292993d61d88d80c4a4429aa97856f612e0402b2";
        sha256 = "13shcwpx52cgbh68zqw4yzxccdds532mmkffiz24jc34aridax5z";
        # date = 2014-06-04T02:04:46+02:00;
      };
      patches = [ ./emacs/patches/indent-shift.patch ];
    };

    initsplit = compileEmacsFiles {
      name = "initsplit";
      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "initsplit";
        rev = "e488e8f95661a8daf9c66241ce58bb6650d91751";
        sha256 = "1qvkxpxdv0n9qlzigvi25iw485824pgbpb10lwhh8bs2074dvrgq";
        # date = 2015-03-21T23:29:07-05:00;
      };
    };

    info-lookmore = compileEmacsFiles {
      name = "info-lookmore";
      src = fetchFromGitHub {
        owner = "emacsmirror";
        repo = "info-lookmore";
        rev = "5e2e62feea2b5149a82365be5580f9e328dd36cc";
        sha256 = "1gfsblgwxszmnx1pf29czvik92ywprvryb57g89zwf31486gjb21";
        # date = 2017-01-20T12:58:03+01:00;
      };
    };

    ivy-compile = compileEmacsFiles {
      name = "ivy-compile.el";
      src = fetchurl {
        url = https://bitbucket.org/holgerschurig/emacsconf/raw/74d428aa2f9be88b14a503f6c3a816ae7cd13644/elisp/ivy-compile.el;
        sha256 = "0igi5p9s6w9yqaxirl286ms9zxad1njw0c6q1b7nry0mh12f7327";
        # date = 2019-04-03T08:52:31-0700;
      };
      buildInputs = with self; [ ivy ];
    };

    ivy-explorer = compileEmacsFiles {
      name = "ivy-explorer";
      src = fetchFromGitHub {
        owner = "clemera";
        repo = "ivy-explorer";
        rev = "a413966cfbcecacc082d99297fa1abde0c10d3f3";
        sha256 = "1720g8i6jq56myv8m9pnr0ab7wagsflm0jgkg7cl3av7zc90zq8r";
        # date = 2019-09-09T21:21:25+02:00;
      };
      buildInputs = with self; [ ivy ];
    };

    makefile-runner = compileEmacsFiles {
      name = "makefile-runner";
      src = fetchFromGitHub {
        owner = "danamlund";
        repo = "emacs-makefile-runner";
        rev = "300ba3820aa0536ef4622f78d67ff1730f7e8521";
        sha256 = "14ncli24x6g25krgjhx46bp1hc0x2hgavcl5ssgj2k2mn8zimkmf";
        # date = 2017-07-29T16:05:20+02:00;
      };
    };

    magit-todos = compileEmacsFiles {
      name = "magit-todos";
      src = fetchFromGitHub {
        owner = "alphapapa";
        repo = "magit-todos";
        rev = "a64e36574bcb77a86726922df905307e55ea62ed";
        sha256 = "18qm376i13gkls7y5qfszv57i0cn3w4q6d0lqjgbn0rq3hi29ca0";
        # date = 2020-01-08T08:44:22-06:00;
      };
      buildInputs = with self; [
        magit magit-popup a anaphora dash f s hl-todo kv with-editor git-commit
        ghub graphql treepy
      ];
    };

    mmm-mode = compileEmacsFiles {
      name = "mmm-mode";
      src = fetchFromGitHub {
        owner = "purcell";
        repo = "mmm-mode";
        rev = "981795bdde53fecf35c6b1179a1618b1e05dbf87";
        sha256 = "1cjylw2jkd13ygvagjx732dsp1d68shgp1diapy29gjawqwc0gsz";
        # date = 2019-12-15T11:05:55+02:00;
      };
    };

    moccur-edit = compileEmacsFiles {
      name = "moccur-edit";
      src = fetchFromGitHub {
        owner = "myuhe";
        repo = "moccur-edit.el";
        rev = "026f5dd4159bd1b68c430ab385757157ba01a361";
        sha256 = "1qikrqs69zqzjpz8bchjrg96bzhj7cbcwkvgsrrx113p420k90zx";
        # date = 2015-03-01T18:04:32+09:00;
      };
      buildInputs = [ self.color-moccur ];
    };

    nix-mode = compileEmacsFiles {
      name = "nix-mode";
      src = fetchFromGitHub {
        owner = "NixOS";
        repo = "nix-mode";
        rev = "5b5961780f3b1c1b62453d2087f775298980f10d";
        sha256 = "0lyf9vp6sivy321z8l8a2yf99kj5g15p6ly3f8gkyaf6dcq3jgnc";
        # date = 2019-09-04T10:40:40-04:00;
      };
      buildInputs = with self; [ company json-mode mmm-mode json-snatcher json-reformat ];
    };

    org-mind-map = compileEmacsFiles {
      name = "org-mind-map";
      src = fetchFromGitHub {
        owner = "theodorewiles";
        repo = "org-mind-map";
        rev = "95347b2f9291f5c5eb6ebac8e726c03634c61de3";
        sha256 = "0mkmh1ascxhfgbqdzcr6d60k4ldnh3l8dylw4m7wglz15hm3ixbm";
        # date = 2019-12-01T10:24:01-05:00;
      };
      buildInputs = [ self.dash ];
    };

    org-opml = compileEmacsFiles {
      name = "org-opml";
      src = fetchFromGitHub {
        owner = "edavis";
        repo = "org-opml";
        rev = "d9019be8653a4406eacf15a06afb8b162d2625a6";
        sha256 = "1nj0ccjyj4yn5b77m9p1asgx41fpgpypsxfnqwhqwgxywhap00w1";
        # date = 2017-06-10T11:37:25-07:00;
      };
    };

    org-pdftools = compileEmacsFiles {
      name = "org-pdftools";
      src = fetchFromGitHub {
        owner = "fuxialexander";
        repo = "org-pdftools";
        rev = "ba2d1eb2e8835c4eaf3bb2b10c8a7c476e3cb1db";
        sha256 = "1wd400l4bnkh7ghiwnz5s2m5mxc8mrdq7l4yb75izvpnbsybc4ms";
        # date = 2020-01-14T17:21:12+08:00;
      };
      buildInputs = with self; [ org org-noter pdf-tools tablist ];
    };

    org-rich-yank = compileEmacsFiles {
      name = "org-rich-yank";
      src = fetchFromGitHub {
        owner = "unhammer";
        repo = "org-rich-yank";
        rev = "d2f350c5296cf05d6c84b02762ba44f09a02b4e3";
        sha256 = "0gxb0fnh5gxjmld0hnk5hli0cvdd8gjd27m30bk2b80kwldxlq1z";
        # date = 2018-11-20T14:54:52+01:00;
      };
    };

    ovpn-mode = compileEmacsFiles {
      name = "ovpn-mode";
      src = fetchFromGitHub {
        owner = "collarchoke";
        repo = "ovpn-mode";
        rev = "8457f72de59929d6c176883e92d1a706163d3170";
        sha256 = "0qcinx4gpfzngirwfis7byrdbgbwk3pak7f8mx5fsbcdnybkk8sj";
        # date = "2019-12-13T22:10:16-05:00";
      };
    };

    ox-slack = compileEmacsFiles {
      name = "ox-slack";
      src = fetchFromGitHub {
        owner = "titaniumbones";
        repo = "ox-slack";
        rev = "89cedb9da6ea08b78bc1fe77d6a39aa078172c1e";
        sha256 = "0a97la3hwkb792a26c6byavwzg8gca6s0ccajd7pi9p430ys1i9y";
        # date = 2020-01-08T10:48:48-05:00;
      };
      buildInputs = [ self.ox-gfm ];
    };

    ox-texinfo-plus = compileEmacsFiles {
      name = "ox-texinfo-plus";
      src = fetchFromGitHub {
        owner = "tarsius";
        repo = "ox-texinfo-plus";
        rev = "3ffceac08c4c690399b85598a5d22cf5bb06c405";
        sha256 = "1jqvzdd3cs4fmkfn3qxw0pv9j3xh87pb4wnzy42yrsq3vs6403gl";
        # date = 2020-01-03T13:38:18+01:00;
      };
    };

    per-window-point = compileEmacsFiles {
      name = "per-window-point";
      src = fetchFromGitHub {
        owner = "alpaker";
        repo = "Per-Window-Point";
        rev = "bd780d0e76814280bc055560e04bc6e606afa69a";
        sha256 = "1kkm957a89fszbikjm1w6dwwnklxn2vwzk3jk9bqzhkpacsqcr16";
        # date = 2013-08-07T09:14:20-04:00;
      };
    };

    peval = compileEmacsFiles {
      name = "peval";
      src = fetchFromGitHub {
        owner = "Wilfred";
        repo = "peval";
        rev = "36af7344121d0d7826ae2516dc831fd90c9909ef";
        sha256 = "1xwfbmm08sbf3fcc7viaysl6rsg4dx3wlmyrv0cfncscxg8x1f1c";
        # date = 2017-12-19T22:30:41+00:00;
      };
      buildInputs = [ self.dash ];
    };

    sdcv-mode = compileEmacsFiles {
      name = "sdcv-mode";
      src = fetchFromGitHub {
        owner = "gucong";
        repo = "emacs-sdcv";
        rev = "c51569ebf3fd1f8c02c33c289d229996bf2ff186";
        sha256 = "0qkvapiaprv9p5zrzr7xfy2prwjnhc3rq3r21zcppcb5habbvy8q";
        # date = 2012-01-28T14:08:32-06:00;
      };
    };

    sky-color-clock = compileEmacsFiles {
      name = "sky-color-clock";
      src = fetchFromGitHub {
        owner = "zk-phi";
        repo = "sky-color-clock";
        rev = "d39f3209faee629bbf140277ce897bae16818602";
        sha256 = "0qha6x595bpc149bs8ra5zq0jndqimc6bhxssb8rbdxvpakqq553";
        # date = 2019-11-06T11:53:28+09:00;
      };
      patches = [ ./emacs/patches/sky-color-clock.patch ];
    };

    spinner = compileEmacsFiles {
      name = "spinner";
      src = fetchFromGitHub {
        owner = "Malabarba";
        repo = "spinner.el";
        rev = "a5d721eea578abb0f13e2a7ba668033d6009f38f";
        sha256 = "19v28czki4dw4wbh9hrp8nbyx3xkjhz90w200ll9vxwrprjl51lj";
        # date = 2019-09-30T09:43:44-03:00;
      };
    };

    slidify-pages = compileEmacsFiles {
      name = "slidify-pages";
      src = fetchFromGitHub {
        owner = "enaeher";
        repo = "slidify-pages";
        rev = "de0c7d58779e5f8355efcbcfed3f0d4cd98a1a73";
        sha256 = "1cjmcwqyczvapsn0bsal1f3xdzzzcqmc2srhzvpb0ph2m51z1fz7";
        # date = 2015-07-07T18:43:40-05:00;
      };
    };

    stopwatch = compileEmacsFiles {
      name = "stopwatch";
      src = fetchFromGitHub {
        owner = "lalopmak";
        repo = "stopwatch";
        rev = "107bdbafdc11128112169b41cf001384a203408a";
        sha256 = "05k16z4w552rspdngjs5c74ng010zmdiwqjn0iahk05l5apx6wd8";
        # date = 2013-08-11T19:22:20-05:00;
      };
    };

    sunrise-commander = compileEmacsFiles {
      name = "sunrise-commander";
      src = fetchFromGitHub {
        owner = "escherdragon";
        repo = "sunrise-commander";
        rev = "cf8305a149a321d028858057e7a7c92f0038a06a";
        sha256 = "1jkdrs3rpn520daskvr7kdm29zwb8rrbbcaqgvai2rcj3dbqa8f8";
        # date = 2017-12-17T20:09:39+01:00;
      };
    };

    tla-mode = compileEmacsFiles {
      name = "tla-mode";
      src = fetchFromGitHub {
        owner = "ratish-punnoose";
        repo = "tla-mode";
        rev = "28c915aa49e043358a29bde045a68357027d96de";
        sha256 = "1vvha5ahdq2jnhwn1s4kx6wf74iz7fvfwk4sl7nb8afy0gp06f9k";
        # date = 2019-06-03T00:38:56-07:00;
      };
    };

    undo-propose = compileEmacsFiles {
      name = "undo-propose";
      src = fetchFromGitHub {
        owner = "jackkamm";
        repo = "undo-propose-el";
        rev = "71002612480fe5cb2b139e73d18c87ddf1fd76b2";
        sha256 = "0mlmck46cgm95hsdqskadd975fdq03mh6pq6lfgzl1ffd0nfqm0z";
        # date = 2019-12-29T14:29:53-08:00;
      };
    };

    verb = compileEmacsFiles {
      name = "verb";
      src = fetchFromGitHub {
        owner = "federicotdn";
        repo = "verb";
        rev = "f9199768e55849cbe5a879a530b33bce88ac4c2c";
        sha256 = "1zpsvjsr5mvi0l0mgfwirxg5bkhkp305h85fbv5g3hr4g0vnr448";
        # date = 2020-02-23T23:18:06+01:00;
      };
    };

    wat-mode = compileEmacsFiles {
      name = "wat-mode";
      src = fetchFromGitHub {
        owner = "devonsparks";
        repo = "wat-mode";
        rev = "f34fc84879a99130283a124cd196041b474213e1";
        sha256 = "11j7cawvy1g9llslgmyk3bnqw6qjxiil1g6jq7bza97ckfrcc1if";
        # date = 2018-10-22T18:26:10-07:00;
      };
    };

    word-count-mode = compileEmacsFiles {
      name = "word-count-mode";
      src = fetchFromGitHub {
        owner = "tomaszskutnik";
        repo = "word-count-mode";
        rev = "6267c98e0d9a3951e667da9bace5aaf5033f4906";
        sha256 = "1pvwy6dm6pwm0d8dd4l1d5rqk31w39h5n4wxqmq2ipwnxrlxp0nh";
        # date = 2015-07-16T22:37:17+02:00;
      };
    };

    yari-with-buttons = compileEmacsFiles {
      name = "yari-with-buttons";
      src = fetchFromGitHub {
        owner = "pedz";
        repo = "yari-with-buttons";
        rev = "9d5bbf59f6ea8dece493cbe609d9c510698eee41";
        sha256 = "1ipk881150152hzhha37sp8162lazw08rkkiahcr5s85f177dkih";
        # date = 2013-11-28T19:05:23-06:00;
      };
    };

    agda2-mode =
      let Agda = pkgs.haskell.lib.dontHaddock pkgs.haskellPackages.Agda; in
      self.trivialBuild {
        pname = "agda-mode";
        version = Agda.version;

        phases = [ "buildPhase" "installPhase" ];

        # already byte-compiled by Agda builder
        buildPhase = ''
          agda=`${Agda}/bin/agda-mode locate`
          cp `dirname $agda`/*.el* .
        '';

        meta = {
          description = "Agda2-mode for Emacs extracted from Agda package";
          longDescription = ''
            Wrapper packages that liberates init.el from `agda-mode locate` magic.
            Simply add this to user profile or systemPackages and do `(require 'agda2)` in init.el.
          '';
          homepage = Agda.meta.homepage;
          license = Agda.meta.license;
        };
      };

    color-theme = super.color-theme.overrideAttrs(attrs: rec {
      name = "emacs-color-theme-${version}";
      version = "6.6.0";
      src = fetchurl {
        url = "http://download.savannah.nongnu.org/releases/color-theme/color-theme-${version}.tar.gz";
        sha256 = "0yx1ghcjc66s1rl0v3d4r1k88ifw591hf814ly3d73acvh15zlsn";
        # date = 2018-10-31T10:46:05-0700;
      };
    });

    doxymacs = mkDerivation rec {
      name = "emacs-doxymacs-${version}";
      version = "2017-12-10";

      src = fetchgit {
        url = git://git.code.sf.net/p/doxymacs/code.git;
        rev = "914d5cc98129d224e15bd68c39ec8836830b08a2";
        sha256 = "1xqjga5pphcfgqzj9lxfkm50sc1qag1idf54lpa23z81wrxq9dy3";
        # date = 2010-03-07T21:45:41+00:00;
      };

      buildInputs = [ self.emacs ] ++ (with pkgs; [ texinfo perl which ]);

      meta = {
        description = "Doxymacs is Doxygen + {X}Emacs";
        longDescription = ''
          The purpose of the doxymacs project is to create a LISP package that
          will make using Doxygen from within {X}Emacs easier.
        '';
        homepage = http://doxymacs.sourceforge.net/;
        license = lib.licenses.gpl2Plus;
        platforms = lib.platforms.unix;
      };
    };

    elfeed = self.melpaBuild {
      pname = "elfeed";
      version = "20180127.1742";
      src = fetchFromGitHub {
        owner = "skeeto";
        repo = "elfeed";
        rev = "fb7de7b6d299bb4190fed3cab541dbf5a5a1bbcd";
        sha256 = "1wx55myyj15mii4zgczm1qpx2fa864ri87c1jr6fbl8vwcg4k0xq";
        # date = 2019-12-27T12:26:39+08:00;
      };
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/407ae027fcec444622c2a822074b95996df9e6af/recipes/elfeed";
        sha256 = "1psga7fcjk2b8xjg10fndp9l0ib72l5ggf43gxp62i4lxixzv8f9";
        name = "elfeed";
        # date = 2019-09-25T11:38:28+0200;
      };
      packageRequires = [ self.emacs ];
      meta = {
        homepage = "https://melpa.org/#/elfeed";
        license = lib.licenses.free;
      };
    };

    emacsql-sqlite = self.melpaBuild {
      pname = "emacsql-sqlite";
      ename = "emacsql-sqlite";
      version = "20181111";
      src = fetchFromGitHub {
        owner = "skeeto";
        repo = "emacsql";
        rev = "a118b6c95af1306f0288a383d274b5dd93efbbda";
        sha256 = "1qz74rk2pskpc1k6kdpqv823i5zc39i885rww05n8lrqw456cpn0";
        # date = 2019-07-27T13:10:42-04:00;
      };
      preBuild = ''
        make LDFLAGS="-L ${self.pg}/share/emacs/site-lisp/elpa/$(echo ${self.pg.name} | sed 's/^emacs-//')"
      '';
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/13d1a86dfe682f65daf529f9f62dd494fd860be9/recipes/emacsql-sqlite";
        sha256 = "1y81nabzzb9f7b8azb9giy23ckywcbrrg4b88gw5qyjizbb3h70x";
        name = "recipe";
        # date = 2018-12-26T15:42:41-0800;
      };
      packageRequires = with self; [ emacs emacsql ];
      meta = {
        homepage = "https://melpa.org/#/emacsql-sqlite";
        license = lib.licenses.free;
      };
    };

    lua-mode = super.lua-mode.overrideAttrs(attrs: rec {
      name = "lua-mode-${version}";
      version = "20190113.1350";
      src = fetchFromGitHub {
        owner = "immerrr";
        repo = "lua-mode";
        rev = "1f596a93b3f1caadd7bba01030f8c179b029600b";
        sha256 = "0i4adlaik3qjx1wkb7rwk2clvj7ci2g8pm0siyb3yk90r6z5mspi";
        fetchSubmodules = true;
        # date = 2019-12-04T15:34:26+01:00;
      };
    });

    multi-term = self.melpaBuild {
      pname = "multi-term";
      ename = "multi-term";
      version = "20160619.233";
      src = fetchFromGitHub {
        owner = "milkypostman";
        repo = "multi-term";
        rev = "8b163b5277f69a46184787feab9a54402622c6fc";
        sha256 = "1h39cld2p82pz80sdnzsajcs03k25ml5ld4d8hdx8hv4v96ismfz";
        # date = 2012-03-06T15:42:35-06:00;
      };
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/ae489be43b1aee93614e40f492ebdf0b98a3fbc1/recipes/multi-term";
        sha256 = "16idk4nd7qpyrvyspbrdl8gdfaclng6ny0xigk6fqdv352djalal";
        name = "recipe";
      };
      packageRequires = [];
      meta = {
        homepage = "https://melpa.org/#/multi-term";
        license = lib.licenses.free;
      };
    };

    org = mkDerivation rec {
      name = "emacs-org-${version}";
      version = "20160421";
      src = fetchFromGitHub {
        owner  = "jwiegley";
        repo   = "org-mode";
        rev    = "db5257389231bd49e92e2bc66713ac71b0435eec";
        sha256 = "073cmwgxga14r4ykbgp8w0gjp1wqajmlk6qv9qfnrafgpxic366m";
      };
      preBuild = ''
        rm -f contrib/lisp/org-jira.el
        makeFlagsArray=(
          prefix="$out/share"
          ORG_ADD_CONTRIB="org* ox*"
        );
      '';
      preInstall = ''
        perl -i -pe "s%/usr/share%$out%;" local.mk
      '';
      buildInputs = [ self.emacs ] ++ (with pkgs; [ texinfo perl which ]);
      meta = {
        homepage = "https://elpa.gnu.org/packages/org.html";
        license = lib.licenses.free;
      };
    };

    proof-general =
      let texinfo = pkgs.texinfo4 ;
          texLive = pkgs.texlive.combine {
            inherit (pkgs.texlive) scheme-basic cm-super ec;
          }; in mkDerivation rec {
      name = "emacs-proof-general-${version}";
      version = "2020-01-13";

      # This is the main branch
      src = fetchFromGitHub {
        owner = "ProofGeneral";
        repo = "PG";
        rev = "bee3f802ada921fb8988edb96a8b41429f7c622c";
        sha256 = "0swajipbssa78dknmgwwr5gvn1y6bbkbhr37aryssrysv82wb275";
        # date = 2020-01-13T15:35:51+01:00;
      };

      # src = ~/src/proof-general;

      buildInputs = [ self.emacs ] ++ (with pkgs; [ texinfo perl which ]);

      prePatch =
        '' sed -i "Makefile" \
               -e "s|^\(\(DEST_\)\?PREFIX\)=.*$|\1=$out|g ; \
                   s|/sbin/install-info|install-info|g"
           sed -i '94d' doc/PG-adapting.texi
           sed -i '96d' doc/ProofGeneral.texi
        '';

      meta = {
        description = "Proof General, an Emacs front-end for proof assistants";
        longDescription = ''
          Proof General is a generic front-end for proof assistants (also known as
          interactive theorem provers), based on the customizable text editor Emacs.
        '';
        homepage = http://proofgeneral.inf.ed.ac.uk;
        license = lib.licenses.gpl2Plus;
        platforms = lib.platforms.unix;
      };
    };

    use-package = self.melpaBuild {
      pname = "use-package";
      version = "20180127.1411";
      src = ~/src/dot-emacs/lisp/use-package;
      recipe = fetchurl {
        url = "https://raw.githubusercontent.com/milkypostman/melpa/51a19a251c879a566d4ae451d94fcb35e38a478b/recipes/use-package";
        sha256 = "0d0zpgxhj6crsdi9sfy30fn3is036apm1kz8fhjg1yzdapf1jdyp";
        name = "use-package";
        # date = 2019-04-03T08:54:52-0700;
      };
      packageRequires = [ self.bind-key self.emacs ];
      meta = {
        homepage = "https://melpa.org/#/use-package";
        license = lib.licenses.free;
      };
    };

    w3m = super.w3m.overrideAttrs(attrs: rec {
      name = "emacs-w3m-${version}";
      version = "20200113.2320";
      src = fetchFromGitHub {
        owner = "emacs-w3m";
        repo = "emacs-w3m";
        rev = "6eda3828bb8530ecd69a3823bd5569a5f779c239";
        sha256 = "0ij85i0zy9wi1cgm0j8cvqpv9802kfy7g4ffx381l7k28m35lqh2";
        # date = 2020-01-13T23:20:24+00:00;
      };
    });
  };

  mkEmacsPackages = emacs:
    (self.emacsPackagesFor emacs).overrideScope (super: self:
      pkgs.lib.fix
        (pkgs.lib.extends
           myEmacsPackageOverrides
           (_: super.elpaPackages
            // super.melpaPackages
            // { inherit emacs;
                 inherit (super) melpaBuild trivialBuild; })));

in {

emacs = self.emacs26;
emacsPackagesNg = self.emacs26PackagesNg;

emacs26 = with pkgs;
  (pkgs.emacs26.override {
     imagemagick = self.imagemagickBig;
     srcRepo = true;
   }).overrideAttrs(attrs: rec {
  CFLAGS = "-O3 -Ofast " + attrs.CFLAGS;
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure
  '';
});

emacs26PackagesNg = mkEmacsPackages self.emacs26;

emacs26debug = with pkgs;
  (pkgs.emacs26.override {
     imagemagick = self.imagemagickBig;
     srcRepo = true;
   }).overrideAttrs(attrs: rec {
  name = "${attrs.name}-debug";
  CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure
  '';
  configureFlags = attrs.configureFlags ++
    [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
});

emacs26DebugPackagesNg = mkEmacsPackages self.emacs26debug;

emacsHEAD = with pkgs;
  (pkgs.emacs26.override {
     imagemagick = self.imagemagickBig;
     srcRepo = true;
   }).overrideAttrs(attrs: rec {
  name = "emacs-${version}${versionModifier}";
  version = "27.0";
  versionModifier = ".50";
  src = ~/src/emacs;
  CFLAGS = "-O0 -g3 " + attrs.CFLAGS;
  patches = [
    # ./emacs/tramp-detect-wrapped-gvfsd.patch
    ./emacs/clean-env.patch
  ];
  buildInputs = attrs.buildInputs ++
    [ libpng libjpeg libungif libtiff librsvg
      jansson freetype harfbuzz.dev git ];
  preConfigure = ''
    sed -i -e 's/headerpad_extra=1000/headerpad_extra=2000/' configure.ac
    autoreconf
  '';
  configureFlags = attrs.configureFlags ++
    [ "--enable-checking=yes,glyphs" "--enable-check-lisp-object-type" ];
});

emacsHEADPackagesNg = mkEmacsPackages self.emacsHEAD;

convertForERC = drv: drv.overrideAttrs(attrs: rec {
  name = "erc-${version}${versionModifier}";
  appName = "ERC";
  version = "27.0";
  versionModifier = ".50";
  iconFile = ./emacs/Chat.icns;

  preConfigure = ''
    sed -i 's|/usr/share/locale|${pkgs.gettext}/share/locale|g' \
      lisp/international/mule-cmds.el
    sed -i 's|nextstep/Emacs\.app|nextstep/${appName}.app|' configure.ac
    sed -i 's|>Emacs<|>${appName}<|' nextstep/templates/Info.plist.in
    sed -i 's|Emacs\.app|${appName}.app|' nextstep/templates/Info.plist.in
    sed -i 's|org\.gnu\.Emacs|org.gnu.${appName}|' nextstep/templates/Info.plist.in
    sed -i 's|Emacs @version@|${appName} @version@|' nextstep/templates/Info.plist.in
    sed -i 's|EmacsApp|${appName}App|' nextstep/templates/Info.plist.in
    if [ -n "${iconFile}" ]; then
      sed -i 's|Emacs\.icns|${appName}.icns|' nextstep/templates/Info.plist.in
    fi
    sed -i 's|Name=Emacs|Name=${appName}|' nextstep/templates/Emacs.desktop.in
    sed -i 's|Emacs\.app|${appName}.app|' nextstep/templates/Emacs.desktop.in
    sed -i 's|"Emacs|"${appName}|' nextstep/templates/InfoPlist.strings.in
    rm -fr .git
  '' + attrs.preConfigure;

  postInstall =
    builtins.replaceStrings ["Emacs.app"] ["${appName}.app"] attrs.postInstall + ''
      set -x
      echo moving
      mv $out/Applications/${appName}.app/Contents/MacOS/Emacs \
         $out/Applications/${appName}.app/Contents/MacOS/${appName}
      cp "${iconFile}" $out/Applications/${appName}.app/Contents/Resources/${appName}.icns
  '';
});

emacsERC = self.convertForERC self.emacsHEAD;
emacsERCPackagesNg = mkEmacsPackages self.emacsERC;

emacsHEADEnv = myPkgs: pkgs.myEnvFun {
  name = "emacsHEAD";
  buildInputs = [
    (self.emacsHEADPackagesNg.emacsWithPackages myPkgs)
  ];
};

emacsERCEnv = myPkgs: pkgs.myEnvFun {
  name = "emacsERC";
  buildInputs = [
    (self.emacsERCPackagesNg.emacsWithPackages myPkgs)
  ];
};

emacs26Env = myPkgs: pkgs.myEnvFun {
  name = "emacs26";
  buildInputs = [
    (self.emacs26PackagesNg.emacsWithPackages myPkgs)
  ];
};

emacs26DebugEnv = myPkgs: pkgs.myEnvFun {
  name = "emacs26debug";
  buildInputs = [
    (self.emacs26DebugPackagesNg.emacsWithPackages myPkgs)
  ];
};

}
