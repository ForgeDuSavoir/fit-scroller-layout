J'ai l'erreur `lua execution timed out in lua layout recalculate callback` lors de l'ouverture de la "`X`ième" fenêtre, où la valeur de `X` dépend de la configuration :

Si :
```
        allowed_dimensions = {
			{ 1.0, 1.0 },
			{ 0.5, 1.0 },
			{ 0.5, 0.5 },
        },
        scroll_direction = "right",
        insert_mode = "view",
```

X = 9

Si : 
```
        allowed_dimensions = {
			{ 0.66, 1.0 },
			{ 0.5, 1.0 },
			{ 0.33, 1.0 },
			{ 0.5, 0.5 },
			{ 0.33, 0.5 },
        },
        scroll_direction = "right",
        insert_mode = "view",
```

X = 6
