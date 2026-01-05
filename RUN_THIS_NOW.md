# 🚀 Run These Commands to Fix Git Push

Copy and paste these commands **one at a time** into your terminal:

## Step 1: Remove Large Files from Git Tracking

```bash
cd /Users/mac/GitHub/malinali-app

# Remove large files (they'll stay on your disk, just removed from git)
git rm --cached assets/models/*.onnx
git rm --cached assets/models/tokenizer.json
git rm --cached assets/*.txt

# Remove build artifacts if tracked
git rm -r --cached build/ 2>/dev/null || true
git rm -r --cached .dart_tool/ 2>/dev/null || true
git rm -r --cached macos/Pods/ 2>/dev/null || true
```

## Step 2: Stage .gitignore and Commit

```bash
git add .gitignore
git commit -m "Remove large files from git tracking"
```

## Step 3: Clean Git History (IMPORTANT - This removes files from ALL commits)

```bash
# This rewrites history - removes large files from all past commits
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch \
    'assets/models/*.onnx' \
    'assets/models/tokenizer.json' \
    'assets/*.txt' \
    'assets/src_*.txt' \
    'assets/tgt_*.txt'" \
  --prune-empty --tag-name-filter cat -- --all
```

**This may take 5-10 minutes depending on your repo size.**

## Step 4: Clean Up Git

```bash
# Remove old references
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

## Step 5: Check Size

```bash
git count-objects -vH
```

You should see `size-pack` is much smaller now (ideally < 50MB).

## Step 6: Push

```bash
# Force push (required after rewriting history)
git push origin main --force
```

---

## ⚠️ Important Notes:

1. **Force push rewrites history** - If others are using this repo, they'll need to re-clone
2. **Backup first** - Make sure you have a backup or have pushed to another remote
3. **The large files stay on your computer** - They're just removed from git

## If You Get Errors:

- If `filter-branch` is too slow, you can use `git-filter-repo` (faster):
  ```bash
  pip install git-filter-repo
  git filter-repo --path assets/models/ --path assets/*.txt --invert-paths --force
  ```

- If you want to start completely fresh:
  ```bash
  git checkout --orphan new-main
  git add .
  git commit -m "Initial commit (cleaned)"
  git branch -D main
  git branch -m main
  git push -f origin main
  ```

