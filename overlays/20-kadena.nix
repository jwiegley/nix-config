self: pkgs:

let

chainweb-data-src = pkgs.fetchFromGitHub {
  owner = "kadena-io";
  repo = "chainweb-data";
  rev = "5d815a70c544eead5964ba4e84d8f71fb8977300";
  sha256 = "111mczhhq7fqk784raa7zg1g9fd2gknph01265hyf4vzmxgr0y6r";
  # date = "2022-08-04T20:20:13-07:00";
};

toYAML = name: data:
  pkgs.writeText name (pkgs.lib.generators.toYAML {} data);

configFile = toYAML "chainweb-node.config" {
  logging = {
    telemetryBackend = {
      enabled = true;
      configuration = {
        handle = "stdout";
        color = "auto";
        format = "text";
      };
    };

    backend = {
      handle = "stdout";
      color = "auto";
      format = "text";
    };

    logger = {
      log_level = "info";
    };

    filter = {
      rules = [
        { key = "component";
          value = "cut-monitor";
          level = "info"; }
        { key = "component";
          value = "pact-tx-replay";
          level = "info"; }
        { key = "component";
          value = "connection-manager";
          level = "info"; }
        { key = "component";
          value = "miner";
          level = "info"; }
        { key = "component";
          value = "local-handler";
          level = "info"; }
      ];
      default = "warn";
    };
  };

  chainweb = {
    allowReadsInLocal = true;
    headerStream = true;
    throttling = {
      global = 10000;
    };
  };
};

in {

start-kadena = with self; stdenv.mkDerivation rec {
  name = "start-kadena-${version}";
  version = "2022-09-01";

  src = chainweb-data-src;

  buildInputs = [
    chainweb-node
    postgresql
    chainweb-data
    tmux
  ];

  phases = [ "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin

    cat <<'EOF' > $out/bin/start-kadena
#!${bash}/bin/bash

NODE=$HOME/.local/share/chainweb-node
DATA=$HOME/.local/share/chainweb-data

if [[ ! -f "$DATA/pgdata/PG_VERSION" ]]; then
    mkdir -p $DATA/pgdata
    ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" initdb
fi

if ! ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" status; then
    ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" \
        -l $DATA/chainweb-pgdata.log start
    sleep 5
    ${postgresql}/bin/createdb chainweb-data || echo "OK: db already exists"
fi

if ! ${postgresql}/bin/pg_ctl -D "$DATA/pgdata" status; then
    echo "Postgres failed to start; see $DATA/chainweb-pgdata.log"
    exit 1
fi

cd $DATA

if [[ ! -f scripts/richlist.sh ]]; then
    mkdir -p scripts
    cp ${src}/scripts/richlist.sh scripts/richlist.sh
fi

if [[ ! -d $NODE/mainnet01 ]]; then
    mkdir -p $NODE
fi

exec ${tmux}/bin/tmux new-session \; \
  send-keys "cd $NODE && ${chainweb-node}/bin/chainweb-node --config-file ${configFile} --disable-node-mining" C-m \; \
  split-window -v \; \
  send-keys "sleep 30 ; cd $DATA && ${chainweb-data}/bin/chainweb-data server --port 9696 -f --service-host=127.0.0.1 --service-port=1848 --p2p-host=127.0.0.1 --p2p-port=1789 --dbuser=$(whoami) --dbname=chainweb-data -m" C-m \;
EOF
    chmod +x $out/bin/start-kadena
  '';

  env = pkgs.buildEnv { inherit name; paths = buildInputs; };
};

chainweb-node = pkgs.haskell.lib.compose.justStaticExecutables
  (import (pkgs.fetchFromGitHub {
     owner = "kadena-io";
     repo = "chainweb-node";
     rev = "33de69e617c8693af90652ac78f4667fd6273e48";
     sha256 = "1ljzcqic051da2988djndr6c59ck1bha55kc5wr06zrnknib0zrc";
     # date = "2022-08-16T15:06:28-07:00";
   }) {});

chainweb-data = pkgs.haskell.lib.compose.justStaticExecutables
  (import chainweb-data-src {});

pact = pkgs.haskell.lib.compose.justStaticExecutables
  (import (pkgs.fetchFromGitHub {
     owner = "kadena-io";
     repo = "pact";
     rev = "657c0b592053e85a46e35c830aad8686657d595d";
     sha256 = "1ij13wlhcvw3i6v3x92xwqmna362dg0g0qv9bn0lv77phmk659qg";
   }) {});

}
