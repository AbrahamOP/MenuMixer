# MenuMixer

Mélangeur audio par application pour macOS — comme le mixeur de volume de Windows, directement dans la barre des menus.

Contrôle le volume de chaque application individuellement, change de sortie audio à la volée, et visualise les niveaux en temps réel avec un VU-mètre.

![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Fonctionnalités

- Volume par application (curseur individuel pour chaque app qui joue du son)
- VU-mètre temps réel par application
- Volume master global
- Sélection de la sortie audio (haut-parleurs, casque, AirPods, etc.)
- App légère en barre des menus (aucune fenêtre flottante)
- Utilise les Core Audio Process Taps (API native macOS 14.2+)

---

## Installation

### Depuis la dernière release (recommandé)

1. Télécharge le `.dmg` depuis la [page Releases](../../releases/latest).
2. Ouvre le DMG (double-clic sur le fichier `.dmg`). Une fenêtre s'ouvre avec trois éléments :
   - `Mélangeur de Son.app`
   - `Applications` (raccourci vers le dossier Applications de macOS)
   - `Installer.command` (script d'installation automatique)
3. **Double-clique sur `Installer.command`**. Un Terminal s'ouvre et fait tout à ta place :
   - Copie l'app dans `/Applications`
   - Retire le marquage de quarantaine posé par le navigateur (sinon macOS affiche "Mélangeur de Son est endommagé" car l'app est signée ad-hoc et non notarisée)
   - Lance l'app

   > ⚠️ Au premier double-clic, macOS peut afficher un avertissement du type "Installer.command ne peut pas être ouvert car il provient d'un développeur non identifié". Dans ce cas : **clic droit** sur `Installer.command` → **Ouvrir** → **Ouvrir** dans la boîte de dialogue. macOS retiendra ton choix.

4. L'icône haut-parleur apparaît dans la barre des menus. Clique dessus pour ouvrir le mélangeur.
5. Au premier usage, macOS demande l'autorisation de capture audio — **accepte-la** (indispensable pour lire/contrôler le volume par app).

### Méthode manuelle (si tu préfères)

Si tu ne veux pas exécuter le script :

1. Glisse `Mélangeur de Son.app` dans `/Applications` depuis le DMG.
2. Ouvre le Terminal et lance :

   ```bash
   xattr -cr "/Applications/Mélangeur de Son.app"
   ```

3. Lance l'app depuis le Launchpad ou Spotlight.

### Pourquoi ces manipulations ?

L'app est signée en **ad-hoc** (signature locale gratuite) et non notarisée par Apple (ça coûte 99 €/an de compte développeur). macOS pose donc un flag de "quarantaine" sur tout fichier téléchargé depuis un navigateur, ce qui combiné à une signature ad-hoc provoque le message "endommagé". Retirer ce flag via `xattr -cr` débloque l'app — elle est parfaitement saine, le code source est public et auditable dans ce repo.

### Compilation depuis le source

Prérequis :
- macOS 15.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (pour régénérer le `.xcodeproj`)

```bash
git clone https://github.com/<ton-user>/MenuMixer.git
cd MenuMixer
xcodegen generate           # régénère le .xcodeproj depuis project.yml
open MelangeurDeSon.xcodeproj
```

Puis build (⌘B) / run (⌘R) depuis Xcode.

Pour générer un DMG local :

```bash
./create-dmg.sh
```

---

## Utilisation

1. Clique sur l'icône haut-parleur dans la barre des menus.
2. Le popover affiche :
   - **Sortie audio** : choisis la sortie active (menu déroulant)
   - **Volume master** : curseur principal
   - **Par application** : une ligne par app qui joue du son, avec VU-mètre et curseur individuel
3. Les apps apparaissent/disparaissent automatiquement selon qu'elles jouent du son ou non.

---

## Permissions requises

Au premier lancement, macOS demande l'autorisation de **capture audio** (Core Audio Process Taps). C'est indispensable pour lire et contrôler le volume de chaque app. Les données audio ne quittent jamais ta machine.

---

## Désinstallation

```bash
rm -rf "/Applications/Mélangeur de Son.app"
```

---

## Contribuer

Les PR sont les bienvenues. Ouvre une issue d'abord pour discuter des changements importants.

## Licence

MIT — voir [LICENSE](LICENSE).
