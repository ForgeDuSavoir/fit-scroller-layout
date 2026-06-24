Voici comment le solver "décide" des dimensions à appliquer à quelle fenêtre, par rapport à l'ordre dans lequel elles sont. 

Par simplicité, on va d'abord voir le comportement lorsqu'il n'y a pas de fenêtre avec des dimensions forcées et toutes les fenêtres sont en mode "auto".

Cette logique décrit comment identifier la "grille" de fenêtre que l'on va utiliser et quelle fenêtre on va placer dans quelle emplacement par rapport à l'ordre dans lequel elles sont.

On va supprimer le paramètre `tiling_mode`, finalement on en a pas besoin pour l'instant.

## Prérequis
Pour éviter des recalcules inutiles, certains calcules sont fait au moment où la configuration est chargée. Ce sont des constantes (valeurs fixes) utiles.
Le résultat de ces calcules sont stocké pour que le solver puisse y accéder sans avoir besoin de faire les calcules lui-même.

Voici donc les constantes calculées :
- `axis`
- `maximized_dimension`
- `max_maximized_windows`
- `smallest_dimension`
- `max_grid_size`
- `dimensions_areas`

### `axis`
`axis` représente l'axe du scroll :
- Si `scroll_direction = right` ou `scroll_direction = left`, `axis = horizontal`
- Si `scroll_direction = down` ou `scroll_direction = up`, `axis = vertical`

### `maximized_dimension`
`maximized_dimension` représente la dimension la plus grande autorisée.

Pour la calculer :
1. Parcourir la liste des `allwed_dimensions` et sélectionner la surface (`largeur x hauteur`) la plus grande
2. Si plusieurs dimensions ont la même surface, on prends celle ayant la plus grande valeur sur l'axe opposé du scroll :
	- donc si le scroll est horizontale (`axis = horizontal`) -> on prends la dimension avec la plus grande hauteur
	- et si le scroll est verticale (`axis = vertical`) -> on prends la dimension avec la plus grande largeur
3. On stock la dimension sélectionnée dans `maximized_dimension`

### `max_maximized_windows`
`max_maximized_windows` représente le nombre maximum de fenêtres que l'on peut faire rentrer sans scroller en appliquant la plus grande dimension (`maximized_dimension`) à toutes les fenêtres.

Pour le calculer :
1. Récupérer la dimension la plus grande (`maximized_dimension`)
2. Calculer la taille de la grille -> pour cela, on fait : 
	`1 / maximized_dimension.largeur` arrondi au minimum
	multiplié par 
	`1 / maximized_dimension.hauteur` arrondi au minimum
3. On stock le résultat dans `max_maximized_windows`

### `smallest_dimension`
`smallest_dimension` représente la dimension la plus petite autorisée.

Pour la calculer :
1. Parcourir la liste des `allowed_dimensions` et sélectionner la dimension avec la surface (`largeur x hauteur`) la plus petite
2. Si plusieurs dimensions ont la même surface, prendre celle avec la valeur la plus petite sur l'axe du scroll :
	- donc si le scroll est horizontale -> on prends la dimension avec la plus petite largeur
	- et si le scroll est verticale -> on prends la dimension avec la plus petite hauteur
3. On stock la dimension sélectionnée dans `smallest_dimension`

### `max_grid_size`
`max_grid_size` représente le nombre maximum de fenêtres que l'on peut faire rentrer sans avoir besoin de scroller.

Pour le calculer :
1. Récupérer la dimension la plus petite (`smallest_dimension`)
2. Calculer la taille de la grille -> pour cela, on fait : 
	`1 / smallest_dimension.largeur` arrondi au minimum
	multiplié par 
	`1 / smallest_dimension.hauteur` arrondi au minimum
3. On stock le résultat dans `max_grid_size`

À noter que le calcul est exactement le même que pour calculer `max_maximized_windows`, mais en utilisant une dimension différente.
On pourra donc le factoriser.

### `dimensions_areas`
`dimensions_areas` sert à stocker la surface de toutes les dimensions, dans l'ordre de la plus prioritaire à la moins prioritaire, ce qui revient à de la grande à la plus petite.

Pour l'obtenir :
1. Récupérer les `allowed_dimensions`
2. Calculer leurs surfaces (`largeur x hauteur`)
3. Les trier de la plus grande à la plus petite
	- Si plusieurs dimensions ont la même surface, les trier par ordre décroissant `X`, où :
		`X = valeur_absolue(largeur x hauteur)`
		- Si plusieurs dimensions ont la même valeur pour `X`, les trier par ordre croissant dans le sens du scroll :
			Si le scroll est horizontale, utiliser la `largeur`
			Si le scroll est verticale, utiliser la `hauteur` 


## Contexte
En plus des constantes définies dans [[#Prérequis]], on a une liste ordonnée de fenêtres, dont chaque fenêtre a un état. 
L'état comporte un mode : 
- "auto" 
- ou "forced *dimension*" (spécifie quel dimension est forcée) 

## Comportement
Le solver va procéder de la manière suivantes :
1. Vérifier si on peut faire rentrer toutes les fenêtres en dimension maximisée ou non (sans scroller) :
	1. Récupérer `max_maximized_windows`
	2. Vérifier si le nombre de fenêtres est inférieur ou égale à `max_maximized_windows`
		- Si oui -> voir la section [[#Fit maximized]]
		- Si non, passer au point suivant
2. Vérifier si on peut faire rentrer toutes les fenêtres sans scroller ou non :
	1. Récupérer le nombre de fenêtres et `max_grid_size`
	2. Vérifier si le nombre de fenêtres est inférieur ou égale à `max_grid_size`
		- Si non, va devoir scroller -> procéder à [[#Implement scroll]]
		- Si oui, on n'a pas besoin de scroller -> passer au point suivant
3. Procéder à  [[#Fit windows]]

### Fit maximized
Appliquer les dimensions :
- `maximized_dimension` à toutes les fenêtres qui sont en mode "auto" 
- la dimension définit pour les fenêtre "forcées"

et les placer de manière à ne pas faire scroller.
### Implement scroll
Puisque l'on sait qu'il va falloir scroller, on sait que les premières fenêtres vont devoir prendre la dimension la plus petite. On regardera ensuite si les dernières fenêtres pourront être plus grandes.

1. Récupérer `smallest_dimension`
2. Récupérer `max_grid_size`
3. Pour les `X` premières fenêtres, où :
	- `X = Y + Z`, où :
		- `Y = round_down(nombre_de_fenêtres / max_grid_size) x max_grid_size`
		- Si scroll horizontale :
			- `line_count = round_down(1 / smallest_dimension.hauteur)`
			- `Z = round_down((nombre_de_fenêtres - Y) / line_count) x line_count`
		- Si scroll verticale :
			- `column_count = round_down(1 / smallest_dimension.largeur)`
			- `Z = round_down((nombre_de_fenêtres - Y) / column_count) x column_count`
	appliquer la dimension `smallest_dimension`
4. Pour les fenêtres restantes, soit `Y = nombre_de_fenêtres - X`, on sait que :
	- Si scroll horizontale, elles seront dans la même colonne, avec une largeur égale à `smallest_dimension.largeur`
	- Si scroll verticale, elles seront sur la même ligne, avec une hauteur égale à `smallest_dimension.hauteur`. Pour la suite, on considère que le scroll est horizontale, inverser donc `largeur` et `hauteur` s'il est verticale.
	1.  Récupérer toutes les dimensions où `largeur = smallest_dimension.largeur`
	2. Les trier par ordre de `hauteur`, du plus grand au plus petit
	3. Les prendre dans l'ordre, et pour chacune :
		- Si `hauteur <= (1 / Y)` -> sélectionner celle-la
		- Sinon, passer à la suivante
	4. Appliquer la dimension sélectionnée au `Z` prochaine fenêtres avec `Z = Y - 1`
	5. Il n'y a maintenant plus que la dernière fenêtre qui n'a pas eu sa dimension.
		Reprendre la liste ordonnée précédente des dimensions, dans l'ordre, et pour chacune :
			Si `hauteur <= 1 / Z` -> sélectionner celle-la
			Sinon, passer à la suivante
	6. Appliquer la dimension sélectionnée à la dernière fenêtre.

### Fit windows
Voici la logique pour identifier les dimensions à appliquer :
1. Récupérer `dimensions_areas`
2. Puis, pour chacune, dans l'ordre :
	1. Calculer la grille de la dimension : `grid = round_down(1 / largeur) x round_down(1 / hauteur)`
	2. Calculer `buffer = nombre_de_fenêtres - grid`
		- Si `buffer <= 0` -> OK, toutes les fenêtres rentrent avec cette dimension, on l'applique donc à toutes les fenêtres
		- Si `buffer <= grid` -> OK, on va essayer avec cette dimension. 
			Vérifier si on peut splitter cette dimension en 2 dimensions autorisées (2 fois la même ou 2 différentes)
			- Si non -> pas OK, on passe à la dimension suivante
			- Si oui -> OK :
				1. on applique la dimension sur les `X` premières fenêtres, où `X = nombre_de_fenêtres - buffer`
				2. on split `Y` fois, où `Y = buffer`, pour intégrer les fenêtres restantes
		- Sinon -> pas OK, on passe à la dimension suivante
3. Si on a trouver aucun résultat, il y a un problème dans la configuration de l'utilisateur : renvoyer une erreur.


---

## Exemples
Pour définir plus facilement le comportement voulu, on va présenté des exemples, où on donne :
- la configuration utilisée
- la liste ordonnée des fenêtres avec leurs mode
- le résultat attendu

### Exemple 1
#### Configuration
On a la configuration suivante :
```
        allowed_dimensions = {
			{ 1.0, 1.0 },
			{ 0.5, 1.0 },
			{ 0.5, 0.5 },
        },
        scroll_direction = "right",
        insert_mode = "view",
```

#### Exemple 1.1
##### Fenêtres
On a les 5 fenêtres suivantes, dans l'ordre :
1. A =  force : { 0.5, 1.0 }
2. B = auto
3. C = auto
4. D = auto
5. E = auto

##### Résultat voulu
1. A = force : { 0.5, 1.0 }
2. B = auto : { 0.5, 0.5 }
3. C = auto : { 0.5, 0.5 }
4. D = auto : { 0.5, 0.5 }
5. E = auto : { 0.5, 0.5 }

```text
+-----+-----+-----+
|     |  B  |  D  |
|  A  +-----+-----+
|     |  C  |  E  |
+-----+-----+-----+
```

1. A est placé avec sa dimension forcée
2. B, C, D et E prennent la plus petite dimension pour limiter le scroll

#### Exemple 1.2
##### Fenêtres
On a les 4 fenêtres suivantes, dans l'ordre :
1. A = auto
2. B = force : { 0.5, 1.0 }
3. C = auto
4. D = auto
5. E = auto

##### Résultat voulu
1. A = auto : { 0.5, 1.0 }
2. B = force : { 0.5, 1.0 }
3. C = auto : { 0.5, 0.5 }
4. D = auto : { 0.5, 0.5 }
5. E = auto : { 0.5, 1.0 }

```text
+-----+-----+-----+-----+
|     |     |  C  |     |
|  A  |  B  +-----+  E  |
|     |     |  D  |     |
+-----+-----+-----+-----+
```

1. A prend le moins de largeur possible et rempli sa hauteur
2. B prend sa dimension forcée
3. C et D prennent la plus petite dimension
4. E prend le moins de largeur possible et rempli sa hauteur

#### Exemple 1.3
##### Fenêtres
On a les 4 fenêtres suivantes, dans l'ordre :
1. A = auto
2. B = auto
3. C = force : { 0.5, 1.0 }
4. D = auto
5. E = auto

##### Résultat voulu
1. A = auto : { 0.5, 0.5 }
2. B = auto : { 0.5, 0.5 }
3. C = force : { 0.5, 1.0 }
4. D = auto : { 0.5, 0.5 }
5. E = auto : { 0.5, 0.5 }

```text
+-----+-----+-----+
|  A  |     |  D  |
+-----+  C  +-----+
|  B  |     |  E  |
+-----+-----+-----+
```

#### Exemple 1.4
##### Fenêtres
On a les 4 fenêtres suivantes, dans l'ordre :
1. A = auto
2. B = auto
3. C = auto
4. D = force : { 0.5, 1.0 }
5. E = auto

##### Résultat voulu
1. A = auto : { 0.5, 0.5 }
2. B = auto : { 0.5, 0.5 }
3. C = auto : { 0.5, 1.0 }
4. D = force : { 0.5, 1.0 }
5. E = auto : { 0.5, 1.0 }

```text
+-----+-----+-----+-----+
|  A  |     |     |     |
+-----+  C  |  D  |  E  |
|  B  |     |     |     |
+-----+-----+-----+-----+
```

#### Exemple 1.5
##### Fenêtres
On a les 4 fenêtres suivantes, dans l'ordre :
1. A = auto
2. B = auto
3. C = auto
4. D = auto
5. E = force : { 0.5, 1.0 }

##### Résultat voulu
1. A = auto : { 0.5, 0.5 }
2. B = auto : { 0.5, 0.5 }
3. C = auto : { 0.5, 0.5 }
4. D = force : { 0.5, 0.5 }
5. E = force : { 0.5, 1.0 }

```text
+-----+-----+-----+
|  A  |  C  |     |
+-----+-----+  E  |
|  B  |  D  |     |
+-----+-----+-----+
```


