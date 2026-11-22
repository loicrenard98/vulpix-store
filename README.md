# 🛍 Boutique Vulpix

Ce dépôt contient les projets partagés par la communauté de [Vulpix](https://github.com/).
Vulpix lit `catalog.json` pour afficher la boutique et télécharge les projets depuis `projects/`.

## Publier un projet

Le plus simple : dans Vulpix, **Boutique → ⇪ Publier un projet**.
Vulpix prépare les fichiers et ouvre une proposition (pull request) ici.

À la main : ajoute un dossier `projects/<identifiant>/` contenant :

| Fichier | Contenu |
|---|---|
| `manifest.json` | nom, description, auteur, version, empreinte… (créé par Vulpix) |
| `<identifiant>-<version>.zip` | le projet (créé par Vulpix) |
| `icon.png` | facultatif, 128 × 128, 512 Ko maximum |

## Règles vérifiées automatiquement

- l'identifiant n'utilise que des minuscules, des chiffres et des tirets, et il est identique au nom du dossier ;
- la description fait au moins 20 caractères ;
- l'archive fait 10 Mo maximum, contient un fichier `.vulpix`, et son empreinte SHA-256 correspond ;
- un projet ne peut être modifié que par son auteur, et chaque mise à jour augmente le numéro de version ;
- 🔒 **les projets payants ne sont pas encore acceptés** (`price` doit valoir `0`).

## Modération

Chaque proposition est vérifiée à la main avant d'être acceptée :

1. La vérification automatique (✅ `validate`) doit être passée.
2. Télécharge l'archive et relis le code. Vérifie qu'il ne supprime pas de fichiers, n'envoie pas de données, ne télécharge rien et ne cache rien.
3. **Merge** : le catalogue est régénéré automatiquement, et le projet apparaît dans Vulpix dans les minutes qui suivent.

Pour retirer un projet, supprime son dossier `projects/<identifiant>/`.
