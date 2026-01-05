#!/bin/bash
# Clean up git history to remove large files

set -e

echo "🧹 Git History Cleanup"
echo "======================"
echo ""
echo "⚠️  WARNING: This will rewrite git history!"
echo "⚠️  Make sure you have a backup or have pushed to a backup remote!"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Step 1: Removing large files from git tracking..."
git rm --cached assets/models/*.onnx 2>/dev/null || true
git rm --cached assets/models/tokenizer.json 2>/dev/null || true
git rm --cached assets/*.txt 2>/dev/null || true
git rm -r --cached build/ 2>/dev/null || true
git rm -r --cached .dart_tool/ 2>/dev/null || true
git rm -r --cached macos/Pods/ 2>/dev/null || true

echo ""
echo "Step 2: Committing removal..."
git add .gitignore
git commit -m "Remove large files from git tracking" || echo "No changes to commit"

echo ""
echo "Step 3: Cleaning git history (this may take a while)..."
echo "Removing large files from all commits..."

# Remove large files from history using filter-branch
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch \
    'assets/models/*.onnx' \
    'assets/models/tokenizer.json' \
    'assets/*.txt' \
    'assets/src_*.txt' \
    'assets/tgt_*.txt'" \
  --prune-empty --tag-name-filter cat -- --all

echo ""
echo "Step 4: Force garbage collection..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo ""
echo "Step 5: Checking new size..."
git count-objects -vH

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Next steps:"
echo "  1. Verify: git log --oneline"
echo "  2. Force push: git push origin main --force"
echo "  3. Warn collaborators to re-clone the repo"

