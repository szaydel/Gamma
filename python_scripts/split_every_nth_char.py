#!/usr/bin/python3.1
##
## Examples of splitting data every nth character
##

from itertools import islice

def split_every(n, iterable):
    i = iter(iterable)
    piece = list(islice(i, n))
    while piece:
        yield piece
        piece = list(islice(i, n))

## We define 'b' and then use the defined function
## to split the string every 2 characters

b = '5bc850f973614194ad853cd4e588c7db'
for a in [''.join(s) for s in split_every(2, b)]:
    print(a)