self: super: {

youtube-dl = super.youtube-dl.override {
  phantomjsSupport = false;
};

}
