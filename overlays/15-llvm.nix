self: super: {

clang = super.clang.overrideAttrs (attrs: { man = null; });
llvm  = super.llvm.overrideAttrs (attrs: { man = null; });

}
