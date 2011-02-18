#!/usr/bin/env python3.1
##
##
##

## Function which will take input as string, tuple or list
## and return item from input if it contains requested character
## and satisfies number of occurances
def instring(input,char,how_many):
    for line in input:
        if char in line and line.count(char) >= how_many:
            yield line

## For loop processes tuple through the generator  
list_n = ['m','mm','mmm']
for line in instring(list_n,'m',1):
    print(line)