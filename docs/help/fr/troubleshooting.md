# Dépannage

Chaque message d’erreur de X1 Scan a un bouton « Aide ». Il ouvre ici l’entrée du même nom. Ces entrées complètent le message : quand le cas se produit, et ce qu’il signifie.

Un garde-fou peut arrêter le scanner. C’est voulu : il protège l’appareil dès qu’une réponse diffère de ce qui est connu. Le message dit quoi faire.

Le volet « Détails » d’un message contient le texte technique. « Copier les détails » le copie pour un rapport de bug. Pour le X1 réel, le journal, dans le dossier X1-captures de votre dossier personnel, garde aussi tout le détail.

## Accès au X1 {#access}

### Aucun X1 trouvé {#no-scanner}

- Le Mac ne voit le X1 que s’il est allumé, relié et reconnu par le pilote FireWire.
- Sur macOS 26 Tahoe, ce pilote est ASFireWire. Sans lui, le X1 reste invisible, même allumé.
- Les adaptateurs USB vers FireWire ne fonctionnent pas. Voir [Matériel et connexion](hardware.md).
- Le bouton « Vérifier l’installation… » du message montre ce qui manque : voir [Vérifier l’installation](hardware.md#installation).
- Sans scanner, vous pouvez essayer l’application en [mode découverte](discovery.md).

### Le X1 est occupé {#scanner-busy}

- Un seul programme à la fois peut ouvrir le scanner.
- FlexColor garde le scanner tant qu’il est ouvert. Quittez-le complètement.

### Ce scanner n’est pas un X1 {#not-an-x1}

- X1 Scan lit d’abord l’identité du scanner. S’il ne s’agit pas d’un Flextight X1, il s’arrête là.
- Les autres modèles Flextight ne sont pas pris en charge.

### Le X1 n’a pas pu être lu {#scanner-read-failed}

- La lecture n’envoie que des demandes d’information. Elle ne fait rien bouger.
- Éteignez puis rallumez le X1, puis réessayez.
- Si le problème revient, le volet « Détails » donne le code à joindre à un rapport.

### Le X1 ne répond plus {#disconnected}

- Un câble qui bouge, un adaptateur mal enfoncé ou une coupure de courant peuvent interrompre l’échange.
- Après une coupure pendant un aperçu ou une numérisation, le X1 doit être éteint puis rallumé.

### Le X1 n’a pas répondu à temps {#scanner-timeout}

- Chaque commande a un délai. Une commande sans réponse arrête l’opération.
- Les causes habituelles sont la chaîne d’adaptateurs ou le câble.

## Démarrage d’un aperçu ou d’une numérisation {#start}

### Séquences de référence absentes {#capture-missing}

- X1 Scan ne pilote le X1 réel qu’avec des séquences validées, livrées dans l’application.
- Si elles manquent, l’application est incomplète. Rien n’est envoyé au scanner.

### Le journal n’a pas pu être créé {#log-failed}

- Chaque séance sur le X1 réel est notée dans un journal, dans le dossier X1-captures.
- C’est une sécurité : sans journal, X1 Scan n’envoie rien.

## Garde-fous {#safety}

Un garde-fou compare chaque commande et chaque réponse à une séquence validée. Au premier écart, il arrête tout. Le scanner n’est pas forcément en panne : l’arrêt est voulu, pour le protéger.

Après un arrêt par un garde-fou, éteignez puis rallumez le X1 avant de recommencer, sauf si le message dit autre chose.

### Commande refusée {#guard-refused}

- La commande bloquée n’a jamais été envoyée.
- Ce cas signale un problème dans X1 Scan. Un rapport de bug avec les détails aide à le corriger.

### État inattendu {#unexpected-state}

- Pendant une séquence, le scanner annonce régulièrement son état. Un état imprévu arrête la séquence.
- L’état seul ne dit pas la cause. Le volet « Détails » donne l’état reçu.

### Attente trop longue {#state-timeout}

- Le scanner devait atteindre un état dans un délai donné. Il ne l’a pas atteint.
- Si le porte-film a pu bouger, vérifiez qu’il est bien engagé.

### Position inattendue {#position-out-of-tolerance}

- X1 Scan vérifie la position du chariot à plusieurs moments.
- Un écart trop grand arrête la séquence avant le mouvement suivant.

### Position hors plage {#position-out-of-range}

- Avant la mise au point, la position lue doit rester dans une plage validée.
- Éteignez puis rallumez le X1, puis faites un aperçu complet avant de numériser.

### Position du chariot {#carriage-position}

- Avant de placer le chariot pour l’aperçu, X1 Scan vérifie sa position.
- Si elle n’est pas celle attendue, l’aperçu s’arrête avant de positionner le chariot.

### État de départ inconnu {#start-state-unknown}

- X1 Scan reconnaît deux états de départ : juste après l’allumage, et après un usage précédent.
- Ici, ni l’un ni l’autre ne correspondait. Seules des lectures, la commande de démarrage et le début de session ont été envoyées : aucune fenêtre, aucun mode, aucune image.

### Aperçu nécessaire {#scan-needs-preview}

- La numérisation suit toujours un aperçu complet, sans redémarrage entre les deux.
- Après un redémarrage du X1, faites d’abord un aperçu.

### Compteur de lignes {#line-counter}

- Le compteur de lignes du scanner doit toujours avancer.
- Un retour en arrière arrête la séquence.

### Réponse inattendue {#unexpected-response}

- Le scanner a renvoyé un statut, une longueur ou un contenu différent de la séquence validée.
- Le volet « Détails » indique l’étape et la valeur reçue.

## Arrêt {#stop}

### Arrêt demandé {#stopped-by-user}

- Arrêter (⌘. ou Échap), un changement de source ou quitter l’application arrêtent la séquence en cours.
- Une fois le balayage commencé (premier SCAN), X1 Scan envoie la commande d’arrêt et attend que le scanner soit prêt.
- Sur le X1 réel, le message dit s’il faut éteindre et rallumer le X1.

### La séquence d’arrêt n’a pas abouti {#stop-incomplete}

- Le scanner n’a pas confirmé qu’il était prêt après la commande d’arrêt.
- Ne lancez rien d’autre avant de l’avoir éteint puis rallumé.

## Image et fichiers {#files}

### L’image n’a pas pu être décodée {#decoding-failed}

- Le scanner a fini sa séquence. Seule la transformation des lignes en image a échoué.
- Le X1 n’a pas besoin d’être redémarré.

### Aucun dossier d’export {#no-export-folder}

- Voir [Dossier](output.md#folder).

### Dossier d’export introuvable {#export-folder-missing}

- Un disque externe débranché ou un dossier renommé donnent ce message.

### Le fichier n’a pas pu être écrit {#write-failed}

- Un fichier existant n’est jamais écrasé : ce n’est pas la cause.
- Après une numérisation, l’image reste affichée. Vous pouvez l’exporter ailleurs avec Fichier › Exporter….

### Porte-film absent ou non pris en charge {#holder-missing}

- Ce message est prévu pour une version ultérieure. X1 Scan ne détecte pas encore le porte-film.

### Erreur inattendue {#unknown}

- Un cas que X1 Scan ne connaît pas encore.
- Le volet « Détails » contient tout ce qui est utile pour un rapport de bug.
