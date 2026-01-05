#!/bin/bash
# Script to fix git push issues by removing large files

set -e

echo "🔍 Checking repository size..."
git count-objects -vH

echo ""
echo "📋 Removing large files from git tracking (keeping local files)..."
echo ""

# Remove large model files
if git ls-files --error-unmatch assets/models/*.onnx &>/dev/null; then
  echo "  Removing .onnx model files..."
  git rm --cached assets/models/*.onnx 2>/dev/null || true
fi

if git ls-files --error-unmatch assets/models/tokenizer.json &>/dev/null; then
  echo "  Removing tokenizer.json..."
  git rm --cached assets/models/tokenizer.json 2>/dev/null || true
fi

# Remove large dataset files
if git ls-files --error-unmatch assets/*.txt &>/dev/null; then
  echo "  Removing .txt dataset files..."
  git rm --cached assets/*.txt 2>/dev/null || true
fi

# Remove build artifacts if tracked
if git ls-files build/ &>/dev/null; then
  echo "  Removing build/ directory..."
  git rm -r --cached build/ 2>/dev/null || true
fi

if git ls-files .dart_tool/ &>/dev/null; then
  echo "  Removing .dart_tool/ directory..."
  git rm -r --cached .dart_tool/ 2>/dev/null || true
fi

if git ls-files macos/Pods/ &>/dev/null; then
  echo "  Removing macos/Pods/ directory..."
  git rm -r --cached macos/Pods/ 2>/dev/null || true
fi

# Remove IDE files
if git ls-files *.iml &>/dev/null; then
  echo "  Removing .iml files..."
  git rm --cached *.iml 2>/dev/null || true
fi

if git ls-files **/local.properties &>/dev/null; then
  echo "  Removing local.properties files..."
  git rm --cached **/local.properties 2>/dev/null || true
fi

echo ""
echo "✅ Files removed from git tracking"
echo ""
echo "📊 Updated repository size:"
git count-objects -vH

echo ""
echo "📝 Next steps:"
echo "  1. Review changes: git status"
echo "  2. Stage .gitignore: git add .gitignore"
echo "  3. Commit: git commit -m 'Remove large files from tracking'"
echo "  4. If you need to clean history, see CLEANUP_GIT.md"
echo "  5. Push: git push origin main"

