Fixed issue :
With following layout :
- Window A = auto
- Window B = forced `{ 1.0 : 1.0 }`


Window A was resulting in `{ 1.0 : 1.0 }` while it should be `{ 0.5 : 1.0 }`.


But now, I noticed the following issue :

With following layout :
- Window A = auto
- Window B = auto
- Window C = forced `{ 1.0 : 1.0 }`

If window B is forced to `{ 1.0 : 1.0 }`, window A results in `{ 1.0 : 1.0 }` while it remain be `{ 0.5 : 1.0 }`.

It seems the fix was specific to the issue and not focused on the algorithm as a wider picture.
