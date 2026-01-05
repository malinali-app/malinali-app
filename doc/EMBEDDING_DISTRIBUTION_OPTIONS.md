# Embedding Distribution Options

## Current Situation

- Generating embeddings takes time (30k+ pairs = several minutes)
- New users would need to wait for generation on first launch
- Database file is ~50-100MB (30k embeddings × 384 dimensions × 4 bytes)

## Option 1: Pre-built SQLite DB in Assets ✅ **Recommended**

### How It Works
1. Generate database once (during development/build)
2. Include `.db` file in app assets
3. App copies DB from assets to app directory on first launch
4. No generation needed for users

### Pros
- ✅ Fast first launch (just copy file)
- ✅ Simple implementation
- ✅ Works offline
- ✅ No network needed

### Cons
- ⚠️ Increases app size (~50-100MB)
- ⚠️ Can't update without app update
- ⚠️ All languages bundled together

### Implementation
```dart
// In app initialization
final dbFile = File('${appDir.path}/fula_translations.db');
if (!await dbFile.exists()) {
  // Copy from assets
  final assetData = await rootBundle.load('assets/fula_translations.db');
  await dbFile.writeAsBytes(assetData.buffer.asUint8List());
}
```

### File Size Optimization
- **Compress DB**: SQLite supports compression (ZIP the DB file)
- **Split by language**: Separate DBs for each language pair
- **Lazy load**: Load languages on-demand

---

## Option 2: Export to Compressed Format

### How It Works
1. Generate embeddings
2. Export to compressed format (e.g., `.tar.gz`, `.zip`)
3. Include compressed file in assets
4. Decompress on first launch

### Pros
- ✅ Smaller app size (compression: ~50% reduction)
- ✅ Can include multiple datasets
- ✅ Easy to update (replace compressed file)

### Cons
- ⚠️ Decompression takes time (but faster than generation)
- ⚠️ Still increases app size
- ⚠️ More complex implementation

### Format Options
- **SQLite + GZIP**: Compress the DB file
- **Custom binary format**: Optimized for embeddings
- **MessagePack/Protobuf**: Efficient serialization

---

## Option 3: Incremental Updates (Advanced)

### How It Works
1. Ship base dataset in app
2. Download updates from server
3. Merge new translations into existing DB

### Pros
- ✅ Small initial app size
- ✅ Can update translations without app update
- ✅ Users get latest data

### Cons
- ⚠️ Requires network/server
- ⚠️ Complex implementation
- ⚠️ Need update mechanism

---

## Option 4: Hybrid Approach (Best of Both Worlds) ⭐

### How It Works
1. **Base dataset in assets**: Common translations (1k-5k pairs)
2. **Full dataset on-demand**: Download or generate if needed
3. **Cache locally**: Once downloaded, use local DB

### Pros
- ✅ Fast initial launch (base dataset)
- ✅ Can expand later (full dataset)
- ✅ Flexible (download or generate)

### Cons
- ⚠️ More complex
- ⚠️ Need to decide what's "base" vs "full"

---

## Recommendation: Option 1 (Pre-built DB) + Compression

### Why?
1. **Simple**: Just copy file from assets
2. **Fast**: No generation needed
3. **Offline**: Works without network
4. **Compressible**: Can reduce size by ~50%

### Implementation Steps

1. **Generate DB during build**:
   ```bash
   # In CI/CD or local build
   flutter run  # Generates DB
   cp build/fula_translations.db assets/
   ```

2. **Add to assets**:
   ```yaml
   assets:
     - assets/fula_translations.db.gz  # Compressed
   ```

3. **Load in app**:
   ```dart
   if (!dbExists) {
     final compressed = await rootBundle.load('assets/fula_translations.db.gz');
     // Decompress and write
   }
   ```

### File Size Estimates

| Approach | Size | First Launch Time |
|----------|------|-------------------|
| Generate on-device | 0 MB | 5-10 minutes |
| Pre-built DB | 50-100 MB | 2-5 seconds |
| Compressed DB | 25-50 MB | 5-10 seconds |
| Base + Full | 5-10 MB + download | 2-5 sec + download |

---

## For Your Use Case

Given you want to:
- Support multiple languages (English, French, Spanish...)
- Keep it simple
- Work offline

**Recommendation**: **Option 1 with compression**

1. Generate DBs for each language pair
2. Compress each DB
3. Include in assets
4. Load on first launch

**Future**: If you add many languages, consider Option 4 (base + full).

---

## Next Steps

1. ✅ Move loading code to `bin/` folder (done)
2. Create build script to generate DBs
3. Add compression step
4. Include in assets
5. Update app to load from assets

Want me to implement this?

