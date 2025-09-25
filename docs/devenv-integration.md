# Devenv Integration Guide

This document outlines how to integrate [devenv](https://devenv.sh) with your existing nix-darwin configuration, complementing the current `bin/de` script for project-specific development environments.

## Current Setup

Your current `bin/de` script provides excellent functionality:
- **Kadena-specific builds** with custom substituters and trusted keys
- **Remote builder support** via the `BUILDER` environment variable
- **Product directory separation** for build artifacts
- **Environment variable preservation** across direnv reloads
- **Cargo/Cabal integration** with custom target directories

## Devenv Benefits

Devenv would complement your existing setup by providing:
- **Declarative project environments** in `devenv.nix` files
- **Service management** (databases, Redis, etc.)
- **Language-specific tooling** with automatic version management
- **Reproducible development environments** shared across team members
- **Testing frameworks** for validating environments

## Integration Strategy

### 1. Hybrid Approach (Recommended)

Keep your existing `bin/de` script for:
- Simple shell environments
- Kadena-specific projects requiring custom substituters
- Projects where remote builders are essential
- Quick temporary environments

Add devenv for:
- Complex projects requiring multiple services
- Team projects needing reproducible environments
- Projects with specific language toolchain requirements
- Full-stack applications with databases

### 2. Example devenv.nix Templates

#### Basic Go Project
```nix
{ pkgs, ... }: {
  languages.go.enable = true;
  packages = [ pkgs.mockgen ];

  scripts.test.exec = ''
    go test ./...
  '';

  enterShell = ''
    echo "Go development environment loaded"
    go version
  '';
}
```

#### Full-Stack Project with Services
```nix
{ pkgs, ... }: {
  languages = {
    javascript = {
      enable = true;
      npm.enable = true;
    };
    go.enable = true;
  };

  services = {
    postgres = {
      enable = true;
      package = pkgs.postgresql_17;
      initialDatabases = [{ name = "myapp"; }];
    };

    redis.enable = true;
  };

  packages = with pkgs; [
    mockgen
    air  # Hot reload for Go
  ];

  scripts = {
    dev.exec = ''
      npm run dev &
      air
    '';

    migrate.exec = ''
      go run ./cmd/migrate
    '';
  };

  enterTest = ''
    echo "Testing database connection..."
    psql myapp -c "SELECT 1;"
  '';
}
```

#### Kadena Project (Using Both Systems)
```nix
# devenv.nix - for services and shared tooling
{ pkgs, ... }: {
  packages = with pkgs; [
    z3
    openssl
  ];

  services.postgres = {
    enable = true;
    initialDatabases = [{ name = "chainweb"; }];
  };

  # Use your existing de script for Nix environment
  enterShell = ''
    echo "Kadena development environment"
    echo "Use 'de' script for Nix shell with custom substituters"
  '';
}
```

## Migration Path

### Phase 1: Evaluation
1. **Install devenv**: Add to your packages.nix
2. **Test on simple projects**: Try devenv on 1-2 non-critical projects
3. **Compare workflows**: Document differences with current de script

### Phase 2: Template Creation
1. **Create project templates** in `~/.config/devenv/templates/`
2. **Document common patterns** for your typical project types
3. **Establish conventions** for when to use devenv vs de script

### Phase 3: Team Integration
1. **Share devenv configurations** via git
2. **Document setup process** for team members
3. **Establish best practices** for mixed environments

## Configuration Examples

### Adding devenv to packages.nix
```nix
# Add to package-list in config/packages.nix
devenv
```

### Project .envrc with devenv
```bash
# For projects using devenv
use devenv

# For projects using your de script
source <(direnv apply_dump .envrc.cache)
source <(reset_kept)
```

### Conditional Environment Selection
```bash
#!/usr/bin/env bash
# project-env script

if [[ -f devenv.nix ]]; then
    echo "Using devenv environment"
    devenv shell
elif [[ -f shell.nix ]] || [[ -f flake.nix ]]; then
    echo "Using de script environment"
    ~/src/nix/bin/de
else
    echo "No development environment configured"
fi
```

## Recommendations

### When to Use Devenv
- ✅ Projects requiring databases or services
- ✅ Team collaboration with shared environments
- ✅ Complex language toolchain management
- ✅ Testing and CI/CD integration

### When to Keep Using `bin/de`
- ✅ Kadena projects requiring custom substituters
- ✅ Simple shell environments
- ✅ Projects using remote builders
- ✅ Quick temporary development setups
- ✅ Personal scripts and utilities

### Best Practices
1. **Document your choice**: Add README notes explaining environment setup
2. **Keep it simple**: Don't over-engineer for simple projects
3. **Test thoroughly**: Validate environments work across different machines
4. **Maintain compatibility**: Ensure both systems can coexist
5. **Share knowledge**: Document patterns that work well for your use cases

## Integration with Existing Tools

Your current workflow integrates well:
- **Direnv**: Both systems work with direnv
- **Remote builders**: Can be used with devenv via environment variables
- **Project management**: Your `~/.config/projects` file works with both
- **Make commands**: Your Makefile/Justfile `travel-ready` command can handle both

The key is choosing the right tool for each project's complexity and requirements.