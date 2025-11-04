# Widgets Repository Template

A repository for managing external widgets with automated registry generation and multi-branch support.

## Features

**Automated Registry Generation** - Build `widget_registry.json` from individual widget configs

**Multi-Branch Support** - Maintain different widget registries on different Git branches

**Validation** - Built-in validation ensures configs are correct

## Quick Start

### Adding a New Widget

1. Create a directory in `widgets/` with your widget name
2. Add `widget.json` and `content.html` files
3. Run `./config/build-registry.sh` to generate the registry
4. Commit and push your changes

### Building the Registry

```bash
# Generate widget_registry.json (uses current Git branch)
./config/build-registry.sh

# Preview without writing
./config/build-registry.sh --dry-run

# Validate existing registry
./config/build-registry.sh --validate
```

### Multi-Branch Registries

Create separate widget registries for different environments:

```bash
# Create a staging branch with different widgets
git checkout -b staging

# Add/modify widgets (manual work)

# Build registry (URLs will point to 'staging' branch)
./config/build-registry.sh

# Push the branch
git push origin staging
```

Each branch maintains its own `widget_registry.json` with URLs pointing to that branch's widgets. Perfect for staging, feature development, or environment-specific widgets.

## Documentation

See [config/WIDGET_SETUP.md](config/WIDGET_SETUP.md) for complete documentation on:
- File structure and configuration
- Creating and updating widgets
- Build script usage
- Multi-branch workflow
- Troubleshooting

## Files

- `config/defaults.json` - Global configuration and default widget settings
- `config/build-registry.sh` - Registry build script
- `config/WIDGET_SETUP.md` - Complete setup and usage documentation
- `widget_registry.json` - Generated registry (auto-updated, do not edit manually)
- `widgets/` - Individual widget directories

## Requirements

- `jq` for JSON processing
  - macOS: `brew install jq`
  - Linux: `apt-get install jq` or `yum install jq`
