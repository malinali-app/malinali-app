# Git Repository Cleanup Guide

## Problem
The repository is too large to push due to large files (449MB .onnx model, large .txt datasets) that were committed to git history.

## Solution Steps

### Step 1: Remove large files from git tracking (keep local files)

```bash
# Remove large model files from git
git rm --cached assets/models/*.onnx
git rm --cached assets/models/tokenizer.json

# Remove large dataset files from git
git rm --cached assets/*.txt
git rm --cached assets/src_*.txt
git rm --cached assets/tgt_*.txt

# Remove build artifacts if tracked
git rm -r --cached build/ 2>/dev/null || true
git rm -r --cached .dart_tool/ 2>/dev/null || true
git rm -r --cached macos/Pods/ 2>/dev/null || true
```

### Step 2: Commit the removal

```bash
git add .gitignore
git commit -m "Remove large files from git tracking"
```

### Step 3: Clean up git history (if files were in previous commits)

**Option A: If you haven't pushed yet (safest)**
```bash
# Reset to before large files were added (adjust commit hash)
git log --oneline  # Find the commit before large files were added
git reset --soft <commit-hash>  # Keep changes, uncommit
# Then re-commit without large files
```

**Option B: If you've already pushed (requires force push)**
```bash
# Use git filter-branch or BFG Repo-Cleaner to remove files from history
# WARNING: This rewrites history - coordinate with team first!

# Using git filter-branch:
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch assets/models/*.onnx assets/models/tokenizer.json assets/*.txt" \
  --prune-empty --tag-name-filter cat -- --all

# Or use BFG Repo-Cleaner (faster, recommended):
# Download from https://rtyley.github.io/bfg-repo-cleaner/
# java -jar bfg.jar --delete-files "*.onnx" --delete-files "*.txt" your-repo.git
```

### Step 4: Force garbage collection

```bash
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### Step 5: Check repository size

```bash
git count-objects -vH
```

### Step 6: Push (if you rewrote history, use force push)

```bash
# If you rewrote history:
git push origin main --force

# If you just removed files from latest commit:
git push origin main
```

## Alternative: Use Git LFS for Large Files

If you need to track large files, consider Git LFS:

```bash
# Install git-lfs
brew install git-lfs  # macOS
# or: apt-get install git-lfs  # Linux

# Initialize in your repo
git lfs install

# Track large files
git lfs track "*.onnx"
git lfs track "assets/models/*.onnx"
git lfs track "assets/*.txt"

# Add .gitattributes
git add .gitattributes

# Now add your files normally
git add assets/models/paraphrase-multilingual-MiniLM-L12-v2.onnx
git commit -m "Add model files via Git LFS"
```

## Recommended Approach for This Project

1. **Don't track model files in git** - They're 449MB and change infrequently
2. **Don't track dataset .txt files** - They're large and can be downloaded separately
3. **Use external storage** for models:
   - GitHub Releases
   - Cloud storage (S3, Google Cloud Storage)
   - Download on first app launch
4. **Keep only code and small config files** in git

## Verify Cleanup

After cleanup, verify:
```bash
# Check what's tracked
git ls-files | xargs du -ch | tail -1

# Should be much smaller (ideally < 50MB)
git count-objects -vH
```

