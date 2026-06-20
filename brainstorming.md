On a :
```
+-------------+
|+-----------+|
||           ||
||     A     ||
||           ||
|+-----------+|
+-------------+
```
-> OK

```
+-------------+
|+-----+-----+|
||     |     ||
||  A  |  B  ||
||     |     ||
|+-----+-----+|
+-------------+
```
-> OK

```
+-------------+
|+-----+-----+|
||     |  C  ||
||  A  +-----+|
||     |  B  ||
|+-----+-----+|
+-------------+
```
-> là il y a un problème, on dirait que la fenêtre C se place entre A et B au lieu de se placer après B. Je pense que c'est un problème de synchronisation du focus : c'est bien la fenêtre B qui est en focus, mais fit scroller agi comme si c'était la A qui était toujours en focus.
Si je ferme la fenêtre C et que je la ré-ouvre directement, j'ai :
```
+-------------+
|+-----+-----+|
||     |  B  ||
||  A  +-----+|
||     |  C  ||
|+-----+-----+|
+-------------+
```
Cette fois-ci la fenêtre C se place bien après la B -> on dirait que le fait de fermer la fenêtre a mis à jour le focus pour fit scroller.






on devrait avoir :
```
+-------------+
|+-----+-----+|
||  A  |     ||
|+-----+  B  +|
||  C  |     ||
|+-----+-----+|
+-------------+
```
Je ne sais pas si c'est un problème dans les spécifications ou si c'est un bug fit scroller.

Ensuite, on a  :
```
+-------------+
|+-----+-----+|
||  A  |  B  ||
|+-----+-----+|
||  C  |  D  ||
|+-----+-----+|
+-------------+
```
-> OK

Et finalement :
```
+-------------+
|+-----+-----+|
||  A  |  B  ||
|+-----+-----+|
||  C  |  D  ||
|+-----+-----+|
+-------------+
```


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






---


Pour commencer, le solver ne dois pas du tout prendre en compte ni le viewport, ni le focus, pour décider du positionnement et des dimensions des fenêtres.
Donc, quand il y a un changement de focus et/ou déplacement du viewport, le solver ne dois même pas être appelé.
Et inversement, le viewport ne dépends pas du solver, il dépends du focus ou du scroll manuel.
Le viewport et le solver sont indépendant l'un de l'autre, mais ils doivent travailler séquentiellement et c'est le solver qui a priorité :
1. Le solver est déclenché uniquement lors des événements suivant :
  - changement du nombre de fenêtre (ouverture ou fermeture de fenêtre)
  - changement du mode de dimension d'une fenêtre (force dimension ou repasser une fenêtre en mode auto)
  - déplacement de fenêtre
2. le viewport est déclenché uniquement lors des événements suivant :
  - le focus change
  - l'utilisateur utilise le scroll manuel (pas encore implémenté dans la v1)

Le fait d'ouvrir une nouvelle fenêtre, par exemple, va faire changer le nombre de fenêtres et donc faire appel au solver, mais ça va aussi changer le focus ce qui va aussi faire appel au viewport. Ce sont 2 événements indépendants mais c'est important que le solver soit appelé et ait terminé sa tache avant que le viewport commence.
En fait, le viewport dépends du solver pour connaitre sa position, mais pas pour se déclencher.

Voici comment le solver doit décieder de la position et des dimensions des fenêtres.
J'ai réfléchi un peu au fonctionnement et je me suis rendu compte que certains positionnements ne peuvent fonctionner qu'avec une logique de "positionnement spacial" (left, right up and down) et pas "d'ordre" (previous and next).

Je vais donc me concentrer sur un mode "order" pour la v1, car c'est plus simple, et je me pencherai sur la possibilité d'un mode "spacial" pour la v2 (choix de l'utilisateur dans la configuration).

On veut suivre la philosophie suivante :
- remplir l'espace visible
- garder l'ordre des fenêtres
- garder le scroll le plus petit possible (en respectant les points précédents)

Il faut donc changer le layout décrit dans la spécification.
J'aimerai ajouter un paramètre à la configuration :
- `tiling_mode` :
	- `split` -> réduire uniquement l'emplacement le plus grand, si possible, sinon ajuster toutes les fenêtres pour avoir au maximum des fenêtres de tailles équivalentes
	- `ajuste`-> avoir des fenêtres de tailles équivalentes au maximum

Si l'utilisateur à mis dans la configuration `tiling_mode=split`, le solver va : 
1. chercher la dimension de la fenêtre la plus grande
2. vérifier si on peut la splitter en deux dimensions autorisées  
	- si oui -> on le fait 
	- si non -> on applique la logique de `ajuste`


Si l'utilisateur à mis dans la configuration `tiling_mode=ajuste`, le solver va appliquer directement cette logique, sans faire la logique `split` auparavant : 
- essayer de faire pour que toutes les fenêtres aient la même dimension. 
- si ce n'est pas possible, prendre des dimensions où il y a le moins de différences de taille

Par exemple, si la configuration est :
```lua
allowed_dimensions = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}
scroll_direction = "right"
tiling_mode = "split"
```

Voici les comportement attendu :

On ouvre la fenêtre A :
```
+-------------+
|+-----------+|
||           ||
||     A     ||
||           ||
|+-----------+|
+-------------+
```

Ensuite la fenêtre B :
```
+-------------+
|+-----+-----+|
||     |     ||
||  A  |  B  ||
||     |     ||
|+-----+-----+|
+-------------+
```

Ensuite la fenêtre C :
```
+-------------+
|+-----+-----+|
||  A  |     ||
||-----+  C  ||
||  B  |     ||
|+-----+-----+|
+-------------+
```

Ensuite la fenêtre D :
```
+-------------+
|+-----+-----+|
||  A  |  C  ||
|+-----+-----+|
||  B  |  D  ||
|+-----+-----+|
+-------------+
```
Afin de maintenir l'ordre des fenêtres par la suite, ce positionnement est obligatoire.

Ensuite la fenêtre E :
```
      +-------------+
+-----|+-----+-----+|
|  A  ||  C  |     ||
+-----|+-----+  E  ||
|  B  ||  D  |     ||
+-----|+-----+-----+|
      +-------------+
```
La fenêtre E fait la largeur minimum autorisé par les allowed_dimensions, pour respecter la règle du "scroll le plus petit possible".
Par contre, elle fait le maximum de la hauteur autorisé par les allowed_dimensions, pour respecter la règle "remplir l'espace visible".

Ensuite la fenêtre F :
```
      +-------------+
+-----|+-----+-----+|
|  A  ||  C  |  E  ||
+-----|+-----+-----+|
|  B  ||  D  |  F  ||
+-----|+-----+-----+|
      +-------------+
```

Ensuite la fenêtre G :
```
            +-------------+
+-----+-----|+-----+-----+|
|  A  |  C  ||  E  |     ||
+-----+-----|+-----|  G  ||
|  B  |  D  ||  F  |     ||
+-----+-----|+-----+-----+|
            +-------------+
```

Ensuite la fenêtre H :
```
            +-------------+
+-----+-----|+-----+-----+|
|  A  |  C  ||  E  |  G  ||
+-----+-----|+-----|-----+|
|  B  |  D  ||  F  |  H  ||
+-----+-----|+-----+-----+|
            +-------------+
```

Et etc...
Pour garder une cohérence d'ordre, ce fonctionnement est obligatoire pour aller avec le scroll.

Décrit l'algorithme du solver pour pouvoir répliquer cette logique.


---

Il y a une autre option que j'aimerai ajouter dans la configuration :
Le paramètre `insert_mode` -> définit où doit-on insérer une nouvelle fenêtre par rapport à l'ordre.
Les options possible :
- "last" -> la nouvelle fenêtre s'ajoutent tout à la fin, comme dans l'exemple précédent
- "first" -> la nouvelles fenêtres s'ajoutent tout au début de la liste
- "view" -> insère la nouvelle fenêtre après la dernière fenêtre visible
- "focus" -> insère la nouvelle fenêtre juste après la fenêtre en focus

Il me semble que c'est n'est pas le solver qui s'occupe d'ajouter une fenêtre à la liste, mais il faut ajouter ce comportement à la documentation.