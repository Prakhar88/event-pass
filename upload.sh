
#!/usr/bin/env bash
set -euo pipefail

# Repository details
REPO_NAME="event-pass"
VISIBILITY="public"  # Change to private if needed

# Three days before October 22, 2026
BACKDATE="2026-10-19T12:00:00+05:30"

# Move to the directory containing this script
cd "$(dirname "$0")"

# Check prerequisites
command -v git >/dev/null || {
    echo "Git is not installed."
    exit 1
}

command -v gh >/dev/null || {
    echo "Install GitHub CLI first: sudo dnf install gh"
    exit 1
}

gh auth status

# Avoid accidentally publishing secrets
echo "Files to be reviewed:"
git status --short 2>/dev/null || true
find . -maxdepth 2 -type f \
    ! -path './.git/*' \
    ! -name 'upload.sh' | head -80

echo
read -r -p "Have you checked for secrets and unwanted files? (y/N): " confirm
[[ "$confirm" == "y" ]] || exit 1

# Initialize Git if necessary
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git init
fi

# Set the default branch
git branch -M main

# Stage project files
git add -A

# Stop if nothing is staged
if git diff --cached --quiet; then
    echo "No files staged. Nothing to commit."
    exit 1
fi

# Create the initial commit with specified timestamps
GIT_AUTHOR_DATE="$BACKDATE" \
GIT_COMMITTER_DATE="$BACKDATE" \
git commit -m "Initial commit: Event Pass"

# Create the GitHub repository and push
gh repo create "$REPO_NAME" \
    "--$VISIBILITY" \
    --source=. \
    --remote=origin \
    --push

echo
echo "Repository created and pushed successfully."
gh repo view --web

