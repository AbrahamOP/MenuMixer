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
2. Ouvre le DMG, glisse **Mélangeur de Son** dans `/Applications`.
3. Au premier lancement, Gatekeeper peut bloquer l'app (elle est signée ad-hoc, pas via un compte développeur Apple payant). Pour débloquer :

   ```bash
   xattr -cr "/Applications/Mélangeur de Son.app"
   ```

4. Lance l'app. Une icône haut-parleur apparaît dans la barre des menus.
5. Autorise l'accès audio au premier clic (macOS demandera la permission de capture audio).

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
