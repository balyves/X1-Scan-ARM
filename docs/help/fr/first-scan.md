# Premier scan pas à pas

Cette page suit le chemin complet, du branchement au fichier enregistré.
À chaque étape qui touche le scanner, l’état du X1 est indiqué.

> Sur le X1 réel, l’aperçu et la numérisation sont en cours de validation. Aujourd’hui, vous pouvez faire tout ce parcours en [mode découverte](discovery.md), sans scanner.

## 1. Brancher le X1 {#connect}

État du X1 : **éteint**.

- Le X1 a une prise FireWire 800.
- Sur un Mac sans FireWire, il faut deux adaptateurs Apple : Thunderbolt 3 (USB-C) vers Thunderbolt 2, puis Thunderbolt vers FireWire 800. Leurs références : [Matériel et connexion](hardware.md#chain).
- Les adaptateurs USB vers FireWire ne fonctionnent pas.
- Si le câble vient d’un autre Mac, éteignez puis rallumez le X1 après le branchement.

## 2. Installer ASFireWire {#asfirewire}

État du X1 : **indifférent**.

- macOS 26 Tahoe n’a plus de pilote FireWire.
- ASFireWire, un pilote tiers en version bêta, rétablit FireWire : voir [Matériel et connexion](hardware.md#asfirewire).
- Installez-le en suivant le guide de son site.
- X1 Scan demande macOS 26 Tahoe.

## 3. Allumer le X1 et vérifier {#check}

État du X1 : **allumé**. FlexColor doit être **fermé** : un seul programme peut ouvrir le scanner.

- Choisissez Scanner › Informations sur le scanner (⌘I).
- Cliquez sur « Lire l’identité ».
- Le modèle et le firmware s’affichent. Seules des lectures sont envoyées.
- En cas de message, voyez [Dépannage](troubleshooting.md).

## 4. Mettre le film dans le porte-film {#holder}

État du X1 : **allumé**. FlexColor : **fermé**.

- Placez le film dans le porte-film, puis le porte-film dans le X1.
- Dans le panneau, onglet Préparer, choisissez le [film et le porte-film](prepare.md#original).

## 5. Faire un aperçu {#preview}

État du X1 : **allumé**, porte-film en place. FlexColor : **fermé**.

- Cliquez sur « Aperçu » en bas du panneau, ou choisissez Scanner › Aperçu… (⌘R).
- L’image se construit ligne par ligne.
- « Arrêter » (⌘. ou Échap) interrompt l’aperçu à tout moment.
- Après l’aperçu, l’[exposition](information.md#exposure) est mesurée.

## 6. Cadrer {#framing}

État du X1 : **indifférent** (rien n’est envoyé au scanner).

- Tournez l’image si besoin : [Orientation](prepare.md#orientation).
- Tracez le cadre avec l’outil [Recadrage](tool-crop.md). Pour l’instant, le cadre ne vaut que pour l’aperçu, pas pour le scan : voir [Cadrage](prepare.md#framing).
- Redressez avec la [Règle de redressement](tool-rule.md).

## 7. Numériser {#scan}

État du X1 : **allumé**, rien n’a bougé depuis l’aperçu. FlexColor : **fermé**.

- Choisissez d’abord un [dossier d’export](output.md#folder) : la numérisation y est enregistrée.
- Cliquez sur « Numériser » en bas du panneau, ou choisissez Scanner › Numériser… (⇧⌘R).
- La barre du bas indique la mise au point, puis les lignes de l’image.

## 8. Enregistrer {#save}

État du X1 : **indifférent**.

- À la fin, la numérisation est enregistrée telle quelle dans le dossier d’export, avec sa recette.
- Choisissez Fichier › Exporter… (⇧⌘E) pour écrire une version tournée et redressée (le cadre n’est pas appliqué à un scan pour l’instant) : voir [Sortie](output.md).
