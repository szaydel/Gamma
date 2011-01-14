#!/bin/python3.1
## Run three functions through a loop
## using the same arguments to the function every time
##

def f(n):
    return 3*n - 6
def g(n):
    return 5*n + 2
def h(n):
    return -2*n + 17

my_arg = 5

for a in [f, g, h]:
    ## We build a list using the 'append' method
    ## as we run through the functions their return is
    ## appended to the list 'b'
    b.append(a(my_arg))
    print(b)