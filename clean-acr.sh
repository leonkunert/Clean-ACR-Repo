#!/bin/bash

# Script to clean Azure Container Registry repository
# Keeps: "latest", 3 most recent semantic version tags (X.Y.Z), and 3 most recent 6-character alphanumeric tags

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    echo "Usage: $0 <registry-name> <repository-name> [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  registry-name    : Name of the Azure Container Registry"
    echo "  repository-name  : Name of the repository in ACR"
    echo "  --dry-run        : Show what would be deleted without actually deleting"
    echo ""
    echo "Example:"
    echo "  $0 myregistry myrepo"
    echo "  $0 myregistry myrepo --dry-run"
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    usage
fi

REGISTRY_NAME="$1"
REPOSITORY_NAME="$2"
DRY_RUN=false

if [ $# -eq 3 ] && [ "$3" == "--dry-run" ]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No tags will be deleted${NC}"
fi

echo "Cleaning ACR repository: ${REPOSITORY_NAME} in registry: ${REGISTRY_NAME}"
echo ""

# Get all tags for the repository, ordered by time (newest first)
echo "Fetching all tags..."
TAGS_JSON=$(az acr repository show-tags \
    --name "$REGISTRY_NAME" \
    --repository "$REPOSITORY_NAME" \
    --output json \
    --orderby time_desc 2>/dev/null || echo "[]")

if [ "$TAGS_JSON" == "[]" ] || [ -z "$TAGS_JSON" ] || [ "$TAGS_JSON" == "null" ]; then
    echo -e "${YELLOW}No tags found in repository${NC}"
    exit 0
fi

# Extract tag names from JSON array (simple array of strings)
TAG_ARRAY=()
if command -v jq &> /dev/null; then
    # Use jq to extract tag names from the array
    while IFS= read -r tag || [ -n "$tag" ]; do
        [ -n "$tag" ] && [ "$tag" != "null" ] && TAG_ARRAY+=("$tag")
    done < <(echo "$TAGS_JSON" | jq -r '.[]' 2>/dev/null | grep -v '^[[:space:]]*$')
elif command -v python3 &> /dev/null || command -v python &> /dev/null; then
    # Use Python to extract tag names
    PYTHON_CMD=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
    while IFS= read -r tag || [ -n "$tag" ]; do
        [ -n "$tag" ] && TAG_ARRAY+=("$tag")
    done < <("$PYTHON_CMD" -c "import sys, json; [print(tag) for tag in json.load(sys.stdin)]" <<< "$TAGS_JSON" 2>/dev/null | grep -v '^[[:space:]]*$')
else
    # Fallback: use sed/awk to extract quoted strings
    while IFS= read -r tag || [ -n "$tag" ]; do
        [ -n "$tag" ] && TAG_ARRAY+=("$tag")
    done < <(echo "$TAGS_JSON" | sed -n 's/.*"\([^"]*\)".*/\1/p' | grep -v '^[[:space:]]*$')
fi

TOTAL_TAGS=${#TAG_ARRAY[@]}

echo "Found ${TOTAL_TAGS} tags"
echo ""

# Tags to keep
KEEP_TAGS=()

# Always keep "latest"
if [[ " ${TAG_ARRAY[@]} " =~ " latest " ]]; then
    KEEP_TAGS+=("latest")
    echo -e "${GREEN}Keeping tag: latest${NC}"
fi

# Find semantic version tags (X.Y.Z pattern)
SEMVER_TAGS=()
for tag in "${TAG_ARRAY[@]}"; do
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.?[0-9]*$ ]]; then
        SEMVER_TAGS+=("$tag")
    fi
done

# Keep the 3 most recent semantic version tags
if [ ${#SEMVER_TAGS[@]} -gt 0 ]; then
    echo "Found ${#SEMVER_TAGS[@]} semantic version tags"
    KEEP_COUNT=$(( ${#SEMVER_TAGS[@]} < 5 ? ${#SEMVER_TAGS[@]} : 5 ))
    for ((i=0; i<KEEP_COUNT; i++)); do
        KEEP_TAGS+=("${SEMVER_TAGS[$i]}")
        echo -e "${GREEN}Keeping semantic version tag: ${SEMVER_TAGS[$i]}${NC}"
    done
fi

# Find 6-character alphanumeric tags (e.g., 1157bb, a1b2c3)
# Exclude "latest" from this list even if it matches the pattern
SIX_CHAR_TAGS=()
for tag in "${TAG_ARRAY[@]}"; do
    if [[ "$tag" =~ ^[0-9a-zA-Z]{6,}$ ]] && [[ "$tag" != "latest" ]]; then
        SIX_CHAR_TAGS+=("$tag")
    fi
done

# Keep the 3 most recent 6-character alphanumeric tags
if [ ${#SIX_CHAR_TAGS[@]} -gt 0 ]; then
    echo "Found ${#SIX_CHAR_TAGS[@]} 6-character alphanumeric tags"
    KEEP_COUNT=$(( ${#SIX_CHAR_TAGS[@]} < 5 ? ${#SIX_CHAR_TAGS[@]} : 5 ))
    for ((i=0; i<KEEP_COUNT; i++)); do
        KEEP_TAGS+=("${SIX_CHAR_TAGS[$i]}")
        echo -e "${GREEN}Keeping 6-character alphanumeric tag: ${SIX_CHAR_TAGS[$i]}${NC}"
    done
fi

echo ""
echo "Tags to keep: ${#KEEP_TAGS[@]}"
echo ""

# Find tags to delete
DELETE_TAGS=()
for tag in "${TAG_ARRAY[@]}"; do
    if [[ ! " ${KEEP_TAGS[@]} " =~ " ${tag} " ]]; then
        DELETE_TAGS+=("$tag")
    fi
done

if [ ${#DELETE_TAGS[@]} -eq 0 ]; then
    echo -e "${GREEN}No tags to delete${NC}"
    exit 0
fi

echo -e "${YELLOW}Tags to delete: ${#DELETE_TAGS[@]}${NC}"
if [ "$DRY_RUN" = true ]; then
    echo "Would delete:"
    for tag in "${DELETE_TAGS[@]}"; do
        echo "  - $tag"
    done
else
    echo "Deleting tags..."
    DELETED=0
    FAILED=0
    for tag in "${DELETE_TAGS[@]}"; do
        if az acr repository delete \
            --name "$REGISTRY_NAME" \
            --image "${REPOSITORY_NAME}:${tag}" \
            --yes \
            --output none 2>/dev/null; then
            ((DELETED++))
            echo -e "${GREEN}Deleted: $tag${NC}"
        else
            ((FAILED++))
            echo -e "${RED}Failed to delete: $tag${NC}"
        fi
    done
    echo ""
    echo "Summary:"
    echo "  Deleted: $DELETED"
    echo "  Failed: $FAILED"
    echo "  Kept: ${#KEEP_TAGS[@]}"
fi

