#!/bin/bash
# Check what's making the git repo too large

echo "📊 Git Repository Analysis"
echo "========================"
echo ""

echo "1. Repository size:"
git count-objects -vH
echo ""

echo "2. Largest files in git history (this may take a moment):"
git rev-list --objects --all | \
  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
  sed -n 's/^blob //p' | \
  sort --numeric-sort --key=2 --reverse | \
  head -10 | \
  numfmt --field=2 --to=iec-i --suffix=B
echo ""

echo "3. Files currently tracked (largest 10):"
git ls-files | xargs -I {} sh -c 'du -h "{}" 2>/dev/null' | sort -h | tail -10
echo ""

echo "4. Checking if large files are in recent commits:"
git log --all --pretty=format: --name-only --diff-filter=A | \
  sort -u | \
  xargs -I {} sh -c 'if [ -f "{}" ]; then du -h "{}" 2>/dev/null; fi' | \
  sort -h | tail -10
echo ""

echo "5. Files in assets/ directory:"
git ls-files assets/ 2>/dev/null | head -20
echo ""

echo "6. Recent commits:"
git log --oneline -5
echo ""

echo "✅ Analysis complete!"
echo ""
echo "If you see large files (>50MB), they need to be removed from git history."
echo "See the cleanup instructions below."

