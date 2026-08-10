# The structural form of a typed environment reference — the only shape in
# which a credential may appear in catalog transports. Renderers apply this
# predicate before projecting a reference into their client's own form (a
# `${NAME}` interpolation, a bare variable name in argv, or an `env_vars`
# entry); a literal secret value never reaches a generated document. The
# catalog layers roster membership on top (isEnvReference). One definition,
# shared by the catalog and every renderer, so the recognizer cannot drift
# into weaker per-client copies.
{
  isTypedEnv =
    value:
    builtins.isAttrs value
    && builtins.attrNames value == [ "env" ]
    && builtins.isString value.env
    && builtins.match "^[A-Z][A-Z0-9_]*$" value.env != null;
}
