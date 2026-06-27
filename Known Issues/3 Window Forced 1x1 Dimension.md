Avec la configuration :
```
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        scroll_direction = "right",
        insert_mode = "view",
```

et avec les 3 fenêtres suivantes :
1. A = auto
2. B = auto 
3. C = force { 1.0, 1.0 }

## Résultat attendu
```text
+-----+-----------+
|  A  |           |
+-----+     C     |
|  B  |           |
+-----+-----------+
```
A = auto { 0.5 x 0.5 }
B = auto { 0.5 x 0.5 }
C = force { 1.0, 1.0 }

## Résultat observé
```text
+-----+-----+-----------+
|     |     |           |
|  A  |  B  |     C     |
|     |     |           |
+-----+-----+-----------+
```
A = auto { 0.5, 1.0 }
B = auto { 0.5, 1.0 }
C = force { 1.0, 1.0 }