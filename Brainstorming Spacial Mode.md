
## Notes
Un workspace ne contient que des fenêtres qui ont un lien et qui ont la nécessité d'être vue l'une à coté de l'autre.
Si elles ont un lien mais n'ont pas besoin d'être vues à côté, on utilise un spécial workspace.
Si elles n'ont pas de lien, on les mets sur des workspaces différents.
On peut gérer ça avec :
- des launcher custom : une entré pour ouvrir plusieurs fenêtres d'un coup
- launcher avec le start menu ouvre sur le special workspace par défaut, ou alors shit+entrer pour mettre dans le workspace courant, ctrl+entrer pour un nouveau workspace


## Logique du solver
Le solver est déclenché uniquement lors des événements suivant :
- changement du nombre de fenêtre (ouverture ou fermeture de fenêtre)
- changement du mode de dimension d'une fenêtre (force dimension ou repasser une fenêtre en mode auto)
- déplacement de fenêtre

Le comportement va être différent en fonction de l'événement.

On cherche à suivre cette philosophie :
- remplir l'espace visible
- garder l'ordre des fenêtres
- [V2] ne jamais avoir de fenêtre partiellement visible
- garder le scroll le plus petit possible (en respectant les points précédents)
Ensuite, on a des préférences utilisateur (à rajouter) :
- tiling_mode :
	- split -> split la fenêtre la plus grande si possible, sinon ajuster toutes les fenêtres pour avoir au maximum des fenêtres de tailles équivalentes
	- ajuste -> avoir des fenêtres de tailles équivalentes au maximum
- tiling_order :
	- lines -> de gauche à droite
	- columns -> de haut en bas
	- spiral -> sens horaire
- invert_order :
	- false
	- [V2] true
- insert_mode :
	- view -> insère une nouvelle fenêtre là où il y a le plus de place visible
	- [V2] focus -> insère une nouvelle fenêtre juste après la fenêtre en focus
	- [V2] stack last -> les nouvelles fenêtres s'ajoutent tout à la fin
	- [V2] stack first -> les nouvelles fenêtres s'ajoutent tout au début


- tiling mode : how to chose dimensions when several possibilities ?
	- lines -> on divise la largeur tant que l'on peut avant de diviser la hauteur
	- columns -> on divise la hauteur tant que l'on peut avant de diviser la largeur
	- split -> on divise la plus grande fenêtre en laissant les autres 
- order mode : where to insert window ?
	- view -> insert where there is space in viewport, or next available space
	- focus -> insert after focused window
	- global -> find first available space
	- stack -> insert in last position
	- stack first ? -> insert in first position
- priority mode : how to behave ?
	- ajuste (or scroll) -> ajuste all window dimensions (but keep order) to minimize scroll
	- conserve (or view) -> ajuste minimum amount of windows regardless of scroll size 

Est-ce qu'on veut conserver l'ordre ou l'espace ?
Soit on est sur une logique d'ordre, soit d'espace.
Si c'est une logique d'ordre, on réajuste tout à chaque fois qu'il y a un événement.
Si c'est une logique d'espace, on modifie le minimum de fenêtres.

Pour la v2 :
- mode :
	- spacial -> garde la disposition actuelle au maximum. Réduit la fenêtre la plus grande -> les fenêtres ne se déplacent pas pour garder le visuel
	- order -> prendre ce mode pour la v1 -> garde l'ordre et déplace les fenêtre pour le maintenir -> les fenêtres se déplacent pour garder l'ordre

### Changement du nombre de fenêtre
Le comportement est différent si on a ouvert une fenêtre ou si on a fermé une fenêtre.
#### Ouverture de fenêtre
La logique est de placer la fenêtre : 
- si possible, dans "le plus grand espace **visible**" 
- sinon et si possible, dans "le **premier** plus grand espace" 
- sinon, tout à la fin en "agrandissant le scroll", mais le moins possible

Concrètement, le solver doit donc :
1. Récupérer la liste des fenêtres qui sont en mode "auto" et visibles dans le viewport
2. Prendre la plus grande qui peut être réduite (selon les "allowed dimensions")
3. Chercher deux "allowed dimension" qui permettent de faire rentrer les deux fenêtres 
### Changement du mode de dimension d'une fenêtre

### Déplacement de fenêtre
Je met de coté pour l'instant.


