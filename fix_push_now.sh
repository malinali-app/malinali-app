#!/bin/bash
# Complete fix for git push issues - run this script

set -e

cd /Users/mac/GitHub/malinali-app

echo "🔍 Step 1: Checking current status..."
git status --short || echo "Git status check failed"

echo ""
echo "📊 Step 2: Checking repository size..."
git count-objects -vH || echo "Count objects failed"

echo ""
echo "🗑️  Step 3: Removing large files from git tracking..."
git rm --cached assets/models/*.onnx 2>/dev/null && echo "  ✓ Removed .onnx files" || echo "  ⚠ .onnx files not tracked"
git rm --cached assets/models/tokenizer.json 2>/dev/null && echo "  ✓ Removed tokenizer.json" || echo "  ⚠ tokenizer.json not tracked"
git rm --cached assets/*.txt 2>/dev/null && echo "  ✓ Removed .txt files" || echo "  ⚠ .txt files not tracked"
git rm -r --cached build/ 2>/dev/null && echo "  ✓ Removed build/" || echo "  ⚠ build/ not tracked"
git rm -r --cached .dart_tool/ 2>/dev/null && echo "  ✓ Removed .dart_tool/" || echo "  ⚠ .dart_tool/ not tracked"
git rm -r --cached macos/Pods/ 2>/dev/null && echo "  ✓ Removed macos/Pods/" || echo "  ⚠ macos/Pods/ not tracked"

echo ""
echo "📝 Step 4: Staging .gitignore..."
git add .gitignore

echo ""
echo "💾 Step 5: Committing changes..."
if git diff --cached --quiet; then
    echo "  ⚠ No changes to commit"
else
    git commit -m "Remove large files from git tracking" || echo "  ⚠ Commit failed or nothing to commit"
fi

echo ""
echo "🧹 Step 6: Cleaning git history (this may take a while)..."
echo "  Removing large files from all commits..."

# Use filter-repo if available, otherwise filter-branch
if command -v git-filter-repo &> /dev/null; then
    echo "  Using git-filter-repo..."
    git filter-repo --path assets/models/ --path assets/*.txt --invert-paths --force
else
    echo "  Using git filter-branch..."
    git filter-branch --force --index-filter \
      "git rm --cached --ignore-unmatch \
        'assets/models/*.onnx' \
        'assets/models/tokenizer.json' \
        'assets/*.txt' \
        'assets/src_*.txt' \
        'assets/tgt_*.txt'" \
      --prune-empty --tag-name-filter cat -- --all 2>&1 | tail -5
fi

echo ""
echo "🗑️  Step 7: Force garbage collection..."
git reflog expire --expire=now --all 2>/dev/null || true
git gc --prune=now --aggressive 2>&1 | tail -3

echo ""
echo "📊 Step 8: Final size check..."
git count-objects -vH

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Next: Try pushing again:"
echo "  git push origin main --force"
echo ""
echo "⚠️  Note: If you've already pushed before, you'll need --force"
echo "⚠️  Warn collaborators to re-clone if you force push"

