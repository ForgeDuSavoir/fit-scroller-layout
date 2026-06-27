## Notes
*Ce qui suit n'impacte en aucun cas le fonctionnement du solver, c'est uniquement pour garder en tête une philosophie d'utilisation des workspace. Cela permet simplement de justifier en partie les choix du mode spacial.*
Un workspace ne contient que des fenêtres qui ont un lien et qui ont la nécessité d'être vue l'une à coté de l'autre.
Si elles ont un lien mais n'ont pas besoin d'être vues à côté, on utilise un spécial workspace.
Si elles n'ont pas de lien, on les mets sur des workspaces différents.
On peut gérer ça avec :
- des launcher custom : une entré pour ouvrir plusieurs fenêtres d'un coup
- launcher avec le start menu ouvre sur le special workspace par défaut, ou alors shit+entrer pour mettre dans le workspace courant, ctrl+entrer pour un nouveau workspace

## Logique du solver en mode `spacial`
Le solver est déclenché uniquement lors des événements suivant :
- changement du nombre de fenêtre (ouverture ou fermeture de fenêtre)
- changement du mode de dimension d'une fenêtre (force dimension ou repasser une fenêtre en mode auto)
- déplacement de fenêtre

Le comportement varie en fonction de l'événement déclencheur.
### Changement du nombre de fenêtre
Le comportement est différent si on a ouvert une fenêtre ou si on a fermé une fenêtre.
#### Ouverture de fenêtre
(avec `insert_mode=view`)
La logique est de placer la fenêtre : 
- si possible, dans "le plus grand espace **visible**" 
- sinon et si possible, dans "le **premier** plus grand espace" 
- sinon, tout à la fin en "agrandissant le scroll", mais le moins possible

Concrètement, le solver doit donc :
1. Récupérer la liste des fenêtres qui sont en mode "auto" et visibles dans le viewport
2. Prendre la plus grande qui peut être réduite (selon les "allowed dimensions")
3. Chercher deux "allowed dimension" qui permettent de faire rentrer les deux fenêtres 
	- Si oui, placer la nouvelle fenêtre en splittant l'espace
4. Si on ne trouve pas de fenêtre, ou qu'aucune n'est splittable, ajouter la nouvelle fenêtre en agrandissant le scroll

#### Fermeture d'une fenêtre
La logique est de ne pas bouger les autres fenêtres (si possible) :
- Regarder si une dimension permise permet à une fenêtre de prendre l'espace libéré par la fenêtre fermé, sans impacter les autres fenêtres
- SI ce n'est pas possible, voir si on peut réduire le scroll et ne pas changer la dimension des fenêtres
	- S'il n'y a pas de scroll, ou plus de scroll, après fermeture essayer de remplir l'espace vide s'il y en a

### Changement du mode de dimension d'une fenêtre
#### Passer en dimension forcée
On veut essayer de modifier le moins de fenêtres possible en appliquant la dimension sur la fenêtre concernée.
- Voir si on peut réduire une des fenêtres adjacentes (qui sont en mode auto) pour accueillir la nouvelle dimension de la fenêtre concerner pour ne pas impacter d'autres fenêtres
- Si on ne peut pas, agrandir ou rétrécir le scroll, puis remplir les espace si possible, en agrandissant les fenêtres auto sans les déplacer

#### Revenir en mode de dimension auto
La je ne suis pas certain.
Je crois qu'on est un peu obligé de tout recalculer.
À voir.

### Déplacement de fenêtre
L'objectif est de :
- si la fenêtre qu'on déplace est en mode auto, la faire rentrer dans un emplacement en splittant une fenêtre auto si possible (pour ne pas impacter d'autres fenêtres)
- si elle n'est pas en auto, ou que la fenêtre adjacente n'est pas en auto ou ne peut pas être splittée, simplement échanger les fenêtre si possible
- si ce n'est pas possible, modifier le scroll pour accueillir ce déplacement sans changer la dimension des fenêtres

## Compact command
Avoir une commande `compact` qui déclenchera un recalcule complet pour compacter les fenêtres et réduire le scroll si on commence à avoir trop de "trous" ou de scroll à force d'ouvrir des fenêtres, de les agrandir, puis de les fermer. 

