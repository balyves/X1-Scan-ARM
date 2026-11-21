# Matériel et connexion

Cette page décrit la chaîne qui relie le X1 à un Mac récent, et le pilote nécessaire sous macOS 26 Tahoe.

## La chaîne de connexion {#chain}

État du X1 : **éteint** pendant le branchement.

Le X1 a une prise FireWire 800 (9 broches). Un Mac récent n’a ni FireWire ni Thunderbolt 2. Dans l’ordre, depuis le Mac :

1. Adaptateur Apple Thunderbolt 3 (USB-C) vers Thunderbolt 2 : modèle A1790, référence MMEL2.
2. Adaptateur Apple Thunderbolt vers FireWire 800 : modèle A1463, référence MD464.
3. Câble FireWire 800, 9 broches des deux côtés, jusqu’au X1.

- Ces deux adaptateurs Apple ne sont plus vendus neufs. On les trouve d’occasion.
- Les adaptateurs USB vers FireWire ne fonctionnent pas.
- Si le câble vient d’un autre Mac, éteignez puis rallumez le X1 après le branchement.

## Le pilote ASFireWire {#asfirewire}

- macOS 26 Tahoe n’a plus de pilote FireWire.
- ASFireWire rétablit FireWire sous macOS 26 Tahoe, avec DriverKit.
- C’est un **projet tiers**, indépendant de X1 Scan, en **version bêta**.
- Dépôt : [github.com/mrmidi/ASFireWire](https://github.com/mrmidi/ASFireWire).
- Site, avec le guide d’installation : [www.asfw.net](https://www.asfw.net/).
- Installez-le en suivant le guide de son site.

## Vérifier la connexion {#check}

État du X1 : **allumé**. FlexColor : **fermé**.

- Choisissez Scanner › Informations sur le scanner (⌘I), puis « Lire l’identité ».
- Si le X1 n’est pas trouvé, voyez [Aucun X1 trouvé](troubleshooting.md#no-scanner).
