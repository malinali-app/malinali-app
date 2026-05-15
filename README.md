# Malinali

## Français

Malinali est une application Flutter de traduction hors ligne basée sur la recherche dans un dictionnaire local. Les entrées sont stockées dans SQLite (`dictionary` pour les lemmes, `phrases` pour les expressions et corpus). La recherche combine ces tables et un index FTS5 construit sur l’appareil.

Le dictionnaire est synchronisé depuis Turso en développement comme en production. L’index de recherche est régénéré localement lorsque le dictionnaire local ne correspond plus à l’index enregistré. Sans identifiants Turso, le mode debug peut encore charger un petit dictionnaire depuis les assets.

Pour éviter une synchronisation Turso à chaque redémarrage à chaud en développement, définir MALINALI_SKIP_AUTO_TURSO_SYNC à true au lancement. La synchronisation manuelle reste disponible dans les paramètres.

L’application permet aussi d’importer un dictionnaire SQLite ou des paires de fichiers texte source et cible. Les résultats affichent la traduction proposée et le texte source correspondant.

La démo cible le français vers le pulaar. La qualité dépend surtout du jeu de données. L’outil convient aux langues peu dotées, aux usages hors ligne et aux contextes où l’utilisateur vérifie les suggestions proposées.

## English

Malinali is an offline Flutter translation app built around local dictionary lookup. Translation entries live in SQLite (`dictionary` for lemmas, `phrases` for expressions and corpus). Search combines both tables with an FTS5 index built on the device.

The dictionary is synced from Turso in development and production. The search index is rebuilt locally when the on-device dictionary no longer matches the stored index metadata. Without Turso credentials, debug builds can still load a small dictionary from bundled assets.

To avoid a Turso sync on every hot restart during development, set MALINALI_SKIP_AUTO_TURSO_SYNC to true at launch. Manual sync remains available in settings.

The app also supports importing a SQLite dictionary or paired source and target text files. Results show the suggested translation and the matching source text.

The demo focuses on French to Pulaar. Quality depends mainly on the dataset. The app suits low-resource languages, offline use, and workflows where the user reviews suggested matches.

## load db

Install the Turso CLI once: https://docs.turso.tech/cli
turso auth login
turso db import "C:\path\to\your\malinali.db"