# Scènes Wallpaper Engine pour Serpantinum

L'application **Wallpaper Engine Scenes** (`we-gui`) gère les scènes et leurs propriétés. Le sélecteur du shell conserve les images et vidéos. Choisir un fond dans le shell libère uniquement l'écran sélectionné. Les affectations sont enregistrées par le daemon dans `~/.config/we-layerd/config.toml` et restaurées par `we-layerd.service`.

## Installer ou réinstaller

Le moteur local est dans `~/Projects/we-layerd-serpantinum`, basé sur le daemon `e32b915424f2918bb4a28f1ba1009611d9bba5f9` et le sous-module renderer `cc8b2c74db77e45598b15408def2d7ee149cdc4b`. Les corrections sont locales, sans commit. Les fichiers Steam restent intacts.

Depuis ce dépôt :

```sh
python3 scripts/install-wallpaper-engine.py --engine "$HOME/Projects/we-layerd-serpantinum"
```

L'installation exige les binaires construits, Qt 6.12, EGL, GBM, epoxy, les dépendances DXC et libxdo dans `.deps`. Les greffons GStreamer locaux présents dans `.deps/gstreamer` sont copiés avec le runtime. Aucun paquet système n'est modifié. La commande compare les fichiers, garde des sauvegardes datées sous `~/.local/share/serpantinum-addons-v2/backups/`, puis remplace les fichiers atomiquement. Elle adapte seulement `Wallpaper.qml`, `WallpaperEngine.qml`, `WallpaperBlur.qml` et le script du pont. L'installateur général réapplique également ces adaptations lorsque le module natif est installé.

Après une modification des bibliothèques natives déjà chargées, redémarrer le service et le shell. Un simple rechargement QML suffit pour les seules modifications QML.

```sh
systemctl --user restart we-layerd.service
serpantinumd stop
serpantinumd start
```

La configuration initiale laisse les fonds natifs sur les deux écrans. Le lanceur installé limite cette instance de we-gui aux scènes et présente aussi les 16 scènes fournies avec Wallpaper Engine. Les projets JSON dépaquetés et les PKG sont résolus sans extraction dans Steam.

## Vérifier et contrôler

```sh
we-layerd ctl status
we-layerd ctl pause
we-layerd ctl resume
we-layerd output-clear DP-1
journalctl --user -u we-layerd.service
```

`output-clear` écrit une exclusion persistante : l'écran n'hérite plus d'un éventuel fond global. Les pauses manuelle, plein écran/maximisation, verrouillage et alimentation de l'écran se composent. Une reprise automatique conserve la pause manuelle. La capture audio s'arrête lorsqu'aucun fond n'est configuré ou lors d'une pause manuelle/de verrouillage.

Le pont reçoit les événements d'application, de libération, d'échec et d'arrêt du service. Il réconcilie aussi au chargement du shell. Il n'interroge pas périodiquement le daemon. Des captures GPU ponctuelles (lecture CPU unique à l'application, avec la prévisualisation comme repli) restent disponibles pour Matugen et les usages figés ; ils ne transportent pas l'animation du verre.

## Canal GPU

Le renderer fournit son DMA-BUF présenté, stable jusqu'à l'acquisition suivante. L'exporteur le copie sur GPU vers un pool de trois buffers GBM. Un socket local `SOCK_SEQPACKET` par écran transmet les descripteurs et les numéros de séquence à Qt. Chaque consommateur conserve au plus un buffer en attente et restitue sa séquence après une copie GPU synchronisée. Un lecteur lent ne bloque pas le renderer ; les allocations encore détenues par un lecteur déconnecté sont retirées avant réutilisation.

Qt partage son flux entre les contrôles d'une même fenêtre. `WallpaperBlur` échantillonne ce flux avec ses shaders, ses masques, sa géométrie et son verre liquide existants. Une prévisualisation placée derrière la texture conserve un fond fonctionnel si l'import échoue ; les erreurs sont consignées. Les clients se connectent lorsque la surface en a besoin. Le dernier descripteur présenté est conservé pour servir un panneau ouvert pendant une pause, sans relancer la scène. Il n'y a pas de lecture de pixels ni de copie CPU d'image dans ce chemin. Les synchronisations `glFinish` privilégient pour l'instant la sûreté ; leur coût doit être suivi.

Le module requiert le scene graph OpenGL de Qt et un GPU capable d'importer les DMA-BUF du renderer. L'installation locale sélectionne le GPU qui pilote les sorties connectées ; elle refuse un choix ambigu entre plusieurs GPU.

## Tests

```sh
python3 -m unittest discover -s tests
cmake -S native/wallpaper-bridge -B native/wallpaper-bridge/build -DCMAKE_BUILD_TYPE=Release
cmake --build native/wallpaper-bridge/build --parallel 3
SERPANTINUM_DRM_DEVICE=/dev/dri/by-path/pci-0000:03:00.0-render \
  ctest --test-dir native/wallpaper-bridge/build --output-on-failure
```

Le test GPU est marqué ignoré sans `SERPANTINUM_DRM_DEVICE`. Il vérifie le pool, les restitutions erronées, le lecteur lent et l'ouverture d'un consommateur pendant une pause. `glass-frame-probe OUTPUT IMAGE.png` est utilisé pour les captures ponctuelles de qualification et de Matugen ; sa lecture CPU unique ne sert jamais au rendu animé du verre.

La validation du 19 octobre 2026 comprend les 16 références, des scènes synthétiques texte/horloge/SceneScript/propriétés, PKG, marionnette avec animation d'os, souris, sortie sonore et audio réactif. Les captures, journaux et mesures de cette session sont dans le dossier `outputs` de la tâche Codex. Cela démontre ces cas, pas la compatibilité universelle avec toutes les scènes Workshop. Les variantes avancées de marionnettes/morphing, un débranchement physique et la parité Windows ne sont pas qualifiés.
