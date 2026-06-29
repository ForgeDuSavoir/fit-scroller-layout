Avec la configuration :
```
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        scroll_direction = "right",
        insert_mode = "view",
        placement_priority = "order",
```

et avec les 2 fenêtres suivantes :
1. A = auto
2. B = force { 1.0, 1.0 }

## Résultat attendu
```text
+-----+-----------+
|     |           |
|  A  |     B     |
|     |           |
+-----+-----------+
```
A = auto { 0.5 x 1.0 }
B = force { 1.0, 1.0 }

## Résultat observé
```text
+-----------+-----------+
|           |           |
|     A     |     B     |
|           |           |
+-----------+-----------+
```
A = auto { 1.0, 1.0 }
B = force { 1.0, 1.0 }