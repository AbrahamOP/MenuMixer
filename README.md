# MenuMixer

Mélangeur audio par application pour macOS — comme le mixeur de volume de Windows, directement dans la barre des menus.

Contrôle le volume de chaque application individuellement, change de sortie audio à la volée, visualise les niveaux en temps réel avec un VU-mètre, et n'affiche que les apps qui jouent actuellement (comme sur Windows).

![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Fonctionnalités

- **Affichage "Windows-like"** : seules les apps qui émettent du son actuellement sont listées (via `kAudioProcessPropertyIsRunningOutput`). Un toggle permet de voir aussi les apps ayant un stream ouvert mais silencieux.
- **Indicateur visuel** (point vert) sur chaque app qui joue actuellement.
- Volume par application avec curseur individuel et VU-mètre temps réel.
- Volume master global (synchronisé avec le volume système macOS).
- Sélection de la sortie audio par app (haut-parleurs, casque, AirPods, etc.).
- App légère en barre des menus (aucune fenêtre flottante, `LSUIElement`).
- Persistance des volumes et états de mute entre les sessions.
- Utilise les Core Audio Process Taps (API native macOS 14.2+).

---

## Installation

### Depuis la dernière release (recommandé)

1. Télécharge le `.dmg` depuis la [page Releases](../../releases/latest).
2. Ouvre le DMG (double-clic sur le fichier `.dmg`). Une fenêtre s'ouvre avec trois éléments :
   - `MenuMixer.app`
   - `Applications` (raccourci vers le dossier Applications de macOS)
   - `Installer.command` (script d'installation automatique)
3. **Double-clique sur `Installer.command`**. Un Terminal s'ouvre et fait tout à ta place :
   - Copie l'app dans `/Applications`
   - Retire le marquage de quarantaine posé par le navigateur (sinon macOS affiche « MenuMixer est endommagé » car l'app est signée ad-hoc et non notarisée)
   - Lance l'app

   > ⚠️ Au premier double-clic, macOS peut afficher un avertissement du type « Installer.command ne peut pas être ouvert car il provient d'un développeur non identifié ». Dans ce cas : **clic droit** sur `Installer.command` → **Ouvrir** → **Ouvrir** dans la boîte de dialogue. macOS retiendra ton choix.

4. L'icône haut-parleur apparaît dans la barre des menus. Clique dessus pour ouvrir le mélangeur.
5. Au premier usage, macOS demande l'autorisation de **capture audio** — accepte-la (indispensable pour lire et contrôler le volume par app).

### Méthode manuelle (alternative)

Si tu ne veux pas exécuter le script :

1. Glisse `MenuMixer.app` dans `/Applications` depuis le DMG.
2. Ouvre le Terminal et lance :

   ```bash
   xattr -cr "/Applications/MenuMixer.app"
   ```

3. Lance l'app depuis le Launchpad ou Spotlight.

### Pourquoi ces manipulations ?

L'app est signée en **ad-hoc** (signature locale gratuite) et non notarisée par Apple (ça coûte 99 €/an de compte développeur). macOS pose un flag de quarantaine sur tout fichier téléchargé depuis un navigateur, ce qui combiné à une signature ad-hoc provoque le message « endommagé ». Retirer ce flag via `xattr -cr` débloque l'app — elle est parfaitement saine, le code source est public et auditable dans ce repo.

### Compilation depuis le source

Prérequis :
- macOS 15.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```bash
git clone https://github.com/AbrahamOP/MenuMixer.git
cd MenuMixer
xcodegen generate           # régénère MenuMixer.xcodeproj depuis project.yml
open MenuMixer.xcodeproj
```

Puis build (⌘B) / run (⌘R) depuis Xcode.

Pour générer un DMG local :

```bash
./create-dmg.sh
```

---

## Utilisation

1. Clique sur l'icône haut-parleur dans la barre des menus.
2. Le popover affiche **uniquement les apps qui jouent actuellement**. Chacune montre :
   - Son icône et son nom, avec un **point vert** si elle émet en ce moment
   - Un curseur de volume individuel
   - Un VU-mètre temps réel
   - Un bouton mute
   - Un sélecteur de sortie audio (si plusieurs devices disponibles)
3. En bas, un bouton **« Afficher les X apps silencieuses »** permet de voir aussi les apps ayant un stream ouvert mais ne jouant rien. À l'inverse, un bouton **« Masquer les apps silencieuses »** rebascule en mode compact.
4. Le curseur **Volume global** en bas contrôle le volume système (lié bidirectionnellement aux touches clavier de volume et au menu son macOS).

---

## Permissions requises

Au premier lancement, macOS demande l'autorisation de **capture audio** (Core Audio Process Taps). C'est indispensable pour lire et contrôler le volume de chaque app. Les données audio ne quittent jamais ta machine.

---

## Désinstallation

```bash
rm -rf "/Applications/MenuMixer.app"
defaults delete com.menumixer.app 2>/dev/null || true
```

La seconde ligne supprime les préférences (volumes sauvegardés par app).

---

## Contribuer

Les PR sont les bienvenues. Ouvre une issue d'abord pour discuter des changements importants.

## Licence

MIT — voir [LICENSE](LICENSE).
