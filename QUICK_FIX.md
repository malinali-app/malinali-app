# Quick Fix for Git Push Error (HTTP 400)

## The Problem
Large files (449MB .onnx model, large .txt datasets) are in your git history, making pushes fail with HTTP 400.

## Quick Solution

### Option 1: Check What's Wrong (Recommended First)
```bash
./check_git_size.sh
```
This will show you what's making the repo large.

### Option 2: Remove Files from Current Commit Only
If you just added large files in the last commit:

```bash
# Undo last commit (keep changes)
git reset --soft HEAD~1

# Remove large files from staging
git reset HEAD assets/models/*.onnx 2>/dev/null || true
git reset HEAD assets/models/tokenizer.json 2>/dev/null || true
git reset HEAD assets/*.txt 2>/dev/null || true

# Make sure .gitignore is correct
git add .gitignore

# Commit without large files
git commit -m "Your commit message (without large files)"

# Push
git push origin main
```

### Option 3: Clean Git History (If files are in old commits)
**⚠️ WARNING: This rewrites history!**

```bash
# Run the cleanup script
./cleanup_git_history.sh

# Then force push
git push origin main --force
```

### Option 4: Start Fresh (Nuclear Option)
If nothing else works:

```bash
# Create a new branch without history
git checkout --orphan new-main

# Add all files (respecting .gitignore)
git add .

# Commit
git commit -m "Initial commit (cleaned)"

# Force push
git branch -D main
git branch -m main
git push -f origin main
```

## Why This Happens
Git tracks the **entire history** of your repository. Even if you remove files from tracking, if they were committed before, they're still in the git history and get pushed.

## Prevention
1. ✅ `.gitignore` is already updated
2. Always check `git status` before committing
3. Use `git add -n <file>` to see what would be added
4. For large files, use Git LFS or external storage

## Verify After Fix
```bash
git count-objects -vH
# Should show size-pack < 50MB ideally
```

