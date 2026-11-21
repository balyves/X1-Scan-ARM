# Sortie

L’onglet Sortie (⌥⌘3) règle le fichier exporté.

## Format {#format}

- RVB 16 bits linéaire, RVB 8 bits sRVB, Gris 16 bits linéaire ou Gris 8 bits sRVB.
- Le 8 bits utilise une courbe et un profil sRVB provisoires. Il a moins de niveaux que le 16 bits linéaire.

## Compression {#compression}

- Aucune, LZW ou ZIP. Toutes sont sans perte.

## Nom de fichier {#name}

- Un modèle de nom, avec des éléments comme {roll} (pellicule), {frame} (vue), la date ou un numéro.
- Le nom du prochain fichier s’affiche dessous.
- Le bouton {icon:more} à droite ouvre Réglages › Exporter pour modifier les modèles.

## Dossier {#folder}

- « Choisir… » choisit le dossier où l’export et la numérisation enregistrent les fichiers.
- Aussi dans Fichier › Choisir le dossier d’export…
- « Afficher dans le Finder » montre le dernier fichier exporté.

## Exporter {#export}

- Fichier › Exporter… (⇧⌘E) écrit l’image affichée, tournée, redressée et recadrée.
- Une recette (`.x1recipe.json`) est écrite à côté.
- Une numérisation enregistrée n’est jamais remplacée : ses versions s’appellent _v1, _v2…
- Un fichier existant n’est jamais écrasé.
