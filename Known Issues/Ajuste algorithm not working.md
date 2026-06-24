J'ai trouvé 2 bugs dans fit scroller qui semblent être liés, où la règle "scroll must be as little as possible" n'est pas respectée. En fait, on dirait un problème dans la logique du solver.

Voici ce qu'il se passe :
## Bug 1 : 0.33 sizes
Avec la configuration :
```
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.66, 1.0 },
            { 0.5, 1.0 },
            { 0.33, 1.0 },
            { 0.5, 0.5 },
            { 0.33, 0.5 },
        scroll_direction = "right",
        },
```

### `split`tiling mode
Avec `tiling_mode = "split"`.
#### Comportement attendu

##### Si j'ouvre 3 fenêtres :
La logique est : "je prends l'espace le plus grand et je regarde si je peux le diviser en 2 allowed dimensions".
```
+-----+-----+
|  A  |     |
+-----+  C  |
|  B  |     |
+-----+-----+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x1.0

##### 4 fenêtres
Même logique que pour 3 fenêtres.
```text
+-----+-----+
|  A  |  C  |
+-----+-----+
|  B  |  D  |
+-----+-----+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x0.5
D = 0.5x0.5

##### 5 fenêtres
L'espace le plus grand est 0.5x0.5 et ne peut pas être divisé en 2 allowed dimensions -> fallback to "ajuste". 
```text
+---+---+---+
| A | C |   |
+---+---+ E |
| B | D |   |
+---+---+---+
```
A = 0.33x0.5
B = 0.33x0.5
C = 0.33x0.5
D = 0.33x0.5
E = 0.33x1.0

Toutes les fenêtres peuvent encore rentrer les le viewport en respectant les allowed dimensions.

#### Comportement observé
Jusqu'à 4 fenêtres, tout se passe comme prévu.
Lorsque l'on ouvre une 5ème fenêtre, les fenêtres existantes ne changent pas et la 5ème s'ouvre en 0.33x1.0 :

```text
    +-------------+ 
+---|--+-----+---+|
|  A|  |  C  |   ||
+---|--+-----+ E ||
|  B|  |  D  |   ||
+---|--+-----+---+|
    +-------------+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x0.5
D = 0.5x0.5
E = 0.33x1.0

### `ajuste`tiling mode
Avec `tiling_mode = "ajuste"`.
#### Comportement attendu
##### Si j'ouvre 3 fenêtres
La logique est : "j'essai de faire pour que toutes les fenêtres aient des dimension similaires au maximum, tout en remplissant l'écran".
```
+---+---+---+
|   |   |   |
| A | B | C |
|   |   |   |
+---+---+---+
```
A = 0.33x1.0
B = 0.33x1.0
C = 0.33x1.0

##### 4 fenêtres
Même logique que pour 3 fenêtres.
```text
+-----+-----+
|  A  |  C  |
+-----+-----+
|  B  |  D  |
+-----+-----+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x0.5
D = 0.5x0.5

On retrouve la même disposition que pour le mode `split`, mais la logique est différente : on veut que toutes les fenêtres soient de même taille, on a pas splitter un espace en 2.
##### 5 fenêtres
On est obligé d'utiliser la dimension 0.33x0.33 pour que toutes les fenêtres rentre dans le viewport, puis on en agrandi une pour qu'elle prenne l'espace disponible.
```text
+---+---+---+
| A | C |   |
+---+---+ E |
| B | D |   |
+---+---+---+
```
A = 0.33x0.5
B = 0.33x0.5
C = 0.33x0.5
D = 0.33x0.5
E = 0.33x1.0

Toutes les fenêtres peuvent encore rentrer les le viewport en respectant les allowed dimensions.

#### Comportement observé

##### Si j'ouvre 3 fenêtres
```text
+-----+-----+
|  A  |     |
+-----+  C  |
|  B  |     |
+-----+-----+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x1.0

On dirait que le comportement est identique qu'avec le "split mode".
##### 4 fenêtres
```text
+-----+-----+
|  A  |  C  |
|-----+-----|
|  B  |  D  |
+-----+-----+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x0.5
D = 0.5x0.5

-> OK
##### 5 fenêtres
```text
    +-------------+ 
+---|--+-----+---+|
|  A|  |  C  |   ||
+---|--+-----+ E ||
|  B|  |  D  |   ||
+---|--+-----+---+|
    +-------------+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x0.5
D = 0.5x0.5
E = 0.33x1.0

Encore le même comportement qu'avec le "split mode".
## Bug 2 : forced dimensions
### Cas de test
J'ai la configuration :
```
        allowed_dimensions = {
			{ 1.0, 1.0 },
			{ 0.5, 1.0 },
			{ 0.5, 0.5 },
        },
        scroll_direction = "right",
        tiling_mode = "split",
        insert_mode = "view",
```

J'ai 4 fenêtres ouvertes :
```text
+-----+-----+
|  A  |  C  |
+-----+-----+
|  B  |  D  |
+-----+-----+
```
A = 0.5x0.5
B = 0.5x0.5
C = 0.5x0.5
D = 0.5x0.5

et j'appel la commande "toggle dimension" sur la fenêtre C pour la forcer à la dimension :
- 1.0x1.0
- puis, 0.5x1.0

### Comportement attendu
##### Fenêtre C forcée à la dimension 1.0x1.0
```text
+-----+-----------+-----+
|  A  |           |     |
|-----+     C     |  D  |
|  B  |           |     |
+-----+-----------+-----+
```
A = 0.5x0.5 (auto)
B = 0.5x0.5 (auto)
C = 1.0x1.0 (forced)
D = 0.5x1.0 (auto)

Pour respecter les règles :
1. Garder l'ordre des fenêtres
2. Forcer les fenêtres "auto" dans les dimensions autorisées
3. Forcer C à 1.0x1.0
4. Réduire le scroll au maximum
5. Remplir l'espace vide

##### Fenêtre C forcée à la dimension 0.5x1.0
```text
+-----+-----+-----+
|  A  |     |     |
|-----+  C  |  D  |
|  B  |     |     |
+-----+-----+-----+
```
A = 0.5x0.5 (auto)
B = 0.5x0.5 (auto)
C = 0.5x1.0 (forced)
D = 0.5x1.0 (auto)

### Comportement observé
##### Fenêtre C forcée à la dimension 1.0x1.0
```text
+-----------+-----------+-----------+-----------+
|           |           |           |           |
|     A     |     B     |     C     |     D     |
|           |           |           |           |
+-----------+-----------+-----------+-----------+
```
A = 1.0x1.0 (auto)
B = 1.0x1.0 (auto)
C = 1.0x1.0 (forced)
D = 1.0x1.0 (auto)

##### Fenêtre C forcée à la dimension 0.5x1.0
```text
+-----+-----+-----+-----+
|     |     |     |     |
|  A  |  B  |  C  |  D  |
|     |     |     |     |
+-----+-----+-----+-----+
```
A = 0.5x1.0 (auto)
B = 0.5x1.0 (auto)
C = 0.5x1.0 (forced)
D = 0.5x1.0 (auto)

