#!/bin/bash

# build-registry.sh
# Script to generate widget_registry.json from individual widget configs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
WIDGETS_DIR="widgets"
DEFAULTS_FILE="config/defaults.json"
OUTPUT_FILE="widget_registry.json"

# Parse command line arguments
DRY_RUN=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --validate)
      VALIDATE_ONLY=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --dry-run    Preview the output without writing to file"
      echo "  --validate   Validate existing widget_registry.json"
      echo "  --help       Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' for usage information"
      exit 1
      ;;
  esac
done

# Function to print error messages
error() {
  echo -e "${RED}ERROR:${NC} $1" >&2
}

# Function to print success messages
success() {
  echo -e "${GREEN}SUCCESS:${NC} $1"
}

# Function to print warning messages
warning() {
  echo -e "${YELLOW}WARNING:${NC} $1"
}

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  error "jq is required but not installed. Please install it:"
  echo "  macOS: brew install jq"
  echo "  Linux: apt-get install jq or yum install jq"
  exit 1
fi

# Validate mode
if [ "$VALIDATE_ONLY" = true ]; then
  if [ ! -f "$OUTPUT_FILE" ]; then
    error "File $OUTPUT_FILE does not exist"
    exit 1
  fi
  
  if jq empty "$OUTPUT_FILE" 2>/dev/null; then
    success "Valid JSON in $OUTPUT_FILE"
    
    # Check structure
    widget_count=$(jq '.widgets | length' "$OUTPUT_FILE")
    success "Found $widget_count widgets in registry"
    exit 0
  else
    error "Invalid JSON in $OUTPUT_FILE"
    exit 1
  fi
fi

# Check required files
if [ ! -f "$DEFAULTS_FILE" ]; then
  error "Defaults file $DEFAULTS_FILE not found"
  exit 1
fi

if [ ! -d "$WIDGETS_DIR" ]; then
  error "Widgets directory $WIDGETS_DIR not found"
  exit 1
fi

# Read global configuration from defaults
REPO=$(jq -r '.repository' "$DEFAULTS_FILE")
CONTENT_FILE=$(jq -r '.contentFile' "$DEFAULTS_FILE")
CONTENT_METHOD=$(jq -r '.contentMethod' "$DEFAULTS_FILE")
REQUIRES_AUTH=$(jq -r '.requiresAuthentication' "$DEFAULTS_FILE")
CACHE_STRATEGY=$(jq -r '.cacheStrategy' "$DEFAULTS_FILE")

# Auto-detect current Git branch
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  error "Not a git repository. Cannot detect branch."
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)

if [ "$BRANCH" = "HEAD" ]; then
  # Detached HEAD state - try to get the commit SHA
  warning "In detached HEAD state"
  BRANCH=$(git rev-parse --short HEAD)
  warning "Using commit SHA: $BRANCH"
fi

success "Loaded configuration from $DEFAULTS_FILE"
success "Detected Git branch: $BRANCH"

# Initialize widgets array
WIDGETS_JSON="[]"

# Process each widget directory
widget_count=0
error_count=0

for widget_dir in "$WIDGETS_DIR"/*; do
  if [ ! -d "$widget_dir" ]; then
    continue
  fi
  
  widget_name=$(basename "$widget_dir")
  widget_config="$widget_dir/widget.json"
  
  echo ""
  echo "Processing widget: $widget_name"
  
  # Check if widget.json exists
  if [ ! -f "$widget_config" ]; then
    error "  Missing widget.json in $widget_dir"
    ((error_count++))
    continue
  fi
  
  # Validate widget.json is valid JSON
  if ! jq empty "$widget_config" 2>/dev/null; then
    error "  Invalid JSON in $widget_config"
    ((error_count++))
    continue
  fi
  
  # Check required fields
  version=$(jq -r '.version // empty' "$widget_config")
  title=$(jq -r '.title // empty' "$widget_config")
  description=$(jq -r '.description // empty' "$widget_config")
  
  if [ -z "$version" ]; then
    error "  Missing required field: version"
    ((error_count++))
    continue
  fi
  
  if [ -z "$title" ]; then
    error "  Missing required field: title"
    ((error_count++))
    continue
  fi
  
  if [ -z "$description" ]; then
    error "  Missing required field: description"
    ((error_count++))
    continue
  fi
  
  # Check for widget-specific contentFile override
  widget_content_file=$(jq -r '.contentFile // empty' "$widget_config")
  if [ -n "$widget_content_file" ]; then
    content_file_name="$widget_content_file"
  else
    content_file_name="$CONTENT_FILE"
  fi

  content_file="$widget_dir/$content_file_name"

  # Check if content file exists
  if [ ! -f "$content_file" ]; then
    error "  Missing $content_file_name in $widget_dir"
    ((error_count++))
    continue
  fi

  # Generate content endpoint URL with the correct content file
  endpoint="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/${WIDGETS_DIR}/${widget_name}/${content_file_name}"
  
  # Build the widget object by merging defaults + widget.json + auto-generated fields
  # Filter out global config fields from defaults (keep only widget-specific defaults)
  widget=$(jq -n \
    --slurpfile defaults "$DEFAULTS_FILE" \
    --slurpfile widget "$widget_config" \
    --arg type "$widget_name" \
    --arg endpoint "$endpoint" \
    --arg method "$CONTENT_METHOD" \
    --argjson requiresAuth "$REQUIRES_AUTH" \
    --arg cacheStrategy "$CACHE_STRATEGY" \
    '
    # Merge all sources
    ($defaults[0] | del(.repository, .contentFile, .contentMethod, .requiresAuthentication, .cacheStrategy)) * $widget[0] * {
      "type": $type,
      "content": {
        "endpoint": $endpoint,
        "method": ($widget[0].contentMethod // $method),
        "requiresAuthentication": ($widget[0].requiresAuthentication // $requiresAuth),
        "cacheStrategy": ($widget[0].cacheStrategy // $cacheStrategy)
      }
    } |
    # Remove widget-level content fields if they were used (they belong in content object only, or are used for URL generation)
    del(.contentFile, .contentMethod, .requiresAuthentication, .cacheStrategy) |
    # Reorder fields: priority fields first, then the rest
    {
      title,
      description,
      version,
      category,
      type,
      imageName,
      content
    } + .
    ')
  
  # Add to widgets array
  WIDGETS_JSON=$(echo "$WIDGETS_JSON" | jq --argjson widget "$widget" '. + [$widget]')
  
  success "  Processed: $title (v$version)"
  ((widget_count++))
done

echo ""
echo "================================"

if [ $error_count -gt 0 ]; then
  error "Failed to process $error_count widget(s)"
  exit 1
fi

if [ $widget_count -eq 0 ]; then
  error "No widgets found to process"
  exit 1
fi

success "Successfully processed $widget_count widget(s)"

# Create final registry JSON
REGISTRY_JSON=$(jq -n --argjson widgets "$WIDGETS_JSON" '{widgets: $widgets}')

# Output result
if [ "$DRY_RUN" = true ]; then
  echo ""
  warning "DRY RUN MODE - No files will be written"
  echo ""
  echo "$REGISTRY_JSON" | jq .
else
  echo "$REGISTRY_JSON" | jq . > "$OUTPUT_FILE"
  success "Written to $OUTPUT_FILE"
fi

echo ""
success "Build complete!"

