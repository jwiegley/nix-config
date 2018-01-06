self: super: {

home-manager = self.callPackage ~/oss/home-manager/home-manager {
  path = toString ~/oss/home-manager;
};

}
