# Azure Container Registry Cleanup Script

This script cleans up tags in an Azure Container Registry repository while preserving:
- The `latest` tag
- The 3 most recent semantic version tags (pattern: `X.Y.Z` where X, Y, Z are numbers)
- The 3 most recent 6-character alphanumeric tags (pattern: `1157bb`, `a1b2c3`, `123456`)

## Prerequisites

- Azure CLI installed and configured
- Appropriate permissions to delete tags from the ACR repository

## Usage

```bash
./clean-acr.sh <registry-name> <repository-name> [--dry-run]
```

### Arguments

- `registry-name`: Name of the Azure Container Registry
- `repository-name`: Name of the repository in ACR
- `--dry-run`: (Optional) Preview what would be deleted without actually deleting

### Examples

```bash
# Preview what would be deleted
./clean-acr.sh myregistry myrepo --dry-run

# Actually delete tags
./clean-acr.sh myregistry myrepo
```

## How It Works

1. Fetches all tags from the specified repository, ordered by time (newest first)
2. Identifies tags to keep:
   - Always keeps `latest`
   - Keeps up to 5 most recent semantic version tags (e.g., `1.2.3`, `2.0.1`)
   - Keeps up to 5 most recent 6-character alphanumeric tags (e.g., `1157bb`, `a1b2c3`, `123456`)
3. Deletes all other tags

## Safety Features

- Dry-run mode to preview changes
- Color-coded output for clarity
- Error handling with exit codes
- Summary of operations performed

