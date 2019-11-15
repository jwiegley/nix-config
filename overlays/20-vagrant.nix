self: super: {

vagrant = with super; stdenv.mkDerivation rec {
  name = "vagrant-${version}";
  version = "2.2.6";
  src = super.fetchurl {
    url = "https://releases.hashicorp.com/vagrant/${version}/vagrant_${version}_x86_64.dmg";
    sha256 = "1xs7xwlm4y8wlrfjc5d1r8qz2r7d8m25m3794xy02f4rlb08wffm";
    # date = 2019-11-14T09:12:29-0800;
  };
  sourceRoot = ".";
  buildInputs = [ undmg xar cpio gzip gawk ];
  phases = [ "unpackPhase" "installPhase" ];
  installPhase = ''
    xar -xf vagrant.pkg
    gzip -dc core.pkg/Payload | cpio -i
    mkdir -p $out
    cp -R bin embedded $out
    find $out \! -name '*.bundle' \! -name '*.dylib*' -type f -print0 \
        | xargs -0 sed -i -e "s%/opt/vagrant%$out%"
    find $out \( -name '*.bundle' -o -name '*.dylib*' \) -type f | while read exe; do
      echo "exe = $exe"
      (otool -L $exe | grep /opt/vagrant | awk '{print $1}' || exit 0) | while read lib; do
        echo "lib = $lib"
        libname=$(echo $lib | sed "s%/opt/vagrant%$out%")
        chmod u+w $exe
        install_name_tool -change "$lib" "$libname" $exe
      done
    done
  '';
  inherit (super.vagrant) meta;
};

VagrantManager = self.installApplication rec {
  name = "VagrantManager";
  version = "2.7.0";
  sourceRoot = "Vagrant Manager.app";
  src = super.fetchurl {
    url = "https://github.com/lanayotech/vagrant-manager/releases/download/${version}/Vagrant.Manager-${version}.dmg";
    sha256 = "0dh9ch7knk8g1cmimxyz8i8n3a1wbxvrl9z8znhxqb8ggrg67g72";
    # date = 2019-11-14T09:12:29-0800;
  };
  description = "Manage your vagrant machines in one place with Vagrant Manager";
  homepage = http://vagrantmanager.com;
};

vagrant-aws = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "vagrant-aws";
  version = "0.7.2-spot";
  type = "git";
  source = {
    url = https://github.com/mkubenka/vagrant-aws;
    rev = "e6cbf02af8f1de12459dd414f230668b7d7451f7";
    sha256 = "17y7sjxh4ci7jybs72qvzvlfwpsb58jzali3h52dcqr2klaq3dd6";
    fetchSubmodules = false;
  };
  dontBuild = false;
  buildInputs = [ bundler ];
};

# This plugin must be licensed before it can be used, by running:
#
#   vagrant plugin license vagrant-vmware-desktop ~/.config/vagrant/license.lic
#
# It also requires access to the Internet to auto re-license every six weeks.
vagrant-vmware-desktop = with super; buildRubyGem rec {
  inherit ruby;
  name = "${gemName}-${version}";
  gemName = "vagrant-vmware-desktop";
  version = "2.0.3";
  source = {
    remotes = [ "https://gems.hashicorp.com" ];
    sha256 = "0m2jnwxmz7xidb734adkknl1hf7zx2sy7nw2drnqdpqd75kc353y";
  };
  buildInputs = [ bundler ];
};

VagrantVMwareUtility = with super; stdenv.mkDerivation rec {
  name = "VagrantVMwareUtility";
  version = "1.0.7";
  src = super.fetchurl {
    url = "https://releases.hashicorp.com/vagrant-vmware-utility/${version}/vagrant-vmware-utility_${version}_x86_64.dmg";
    sha256 = "09gpqskwzrhffzg8zrqvv6ymwd1lm6l8vvz2plyak8qw7kpkgvqr";
    # date = 2019-11-14T09:12:29-0800;
  };
  sourceRoot = ".";
  buildInputs = [ undmg xar cpio gzip ];
  phases = [ "unpackPhase" "installPhase" ];
  installPhase = ''
    xar -xf VagrantVMwareUtility.pkg
    gzip -dc core.pkg/Payload | cpio -i
    mkdir -p $out
    cp -R bin $out
    $out/bin/vagrant-vmware-utility certificate generate
    cat > $out/bin/install-vagrant-vmware-utility <<EOF
#!${bash}/bin/bash -e
if [[ $EUID != 0 ]]; then
    echo install-vagrant-vmware-utility must be run as root
    exit 1
fi
$out/bin/vagrant-vmware-utility service uninstall
$out/bin/vagrant-vmware-utility service install \
    -service-path=$out/bin/vagrant-vmware-utility
cd /Library/LaunchDaemons
launchctl unload com.vagrant.vagrant-vmware-utility.plist || exit 0
launchctl load com.vagrant.vagrant-vmware-utility.plist
launchctl unload com.vagrant.vagrant-vmware-utility-stopper.plist || exit 0
launchctl load com.vagrant.vagrant-vmware-utility-stopper.plist
rm -fr /opt/vagrant-vmware-desktop
mkdir -p /opt/vagrant-vmware-desktop
ln -s $out/bin/certificates /opt/vagrant-vmware-desktop/certificates
EOF
    chmod +x $out/bin/install-vagrant-vmware-utility
  '';
  meta = with stdenv.lib; {
    description = ''
      The Vagrant VMware Utility installer provides a small utility service
      that Vagrant utilizes for interacting with VMware on the system.
    '';
    homepage = https://www.vagrantup.com/vmware/downloads.html;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.darwin;
  };
};

}
