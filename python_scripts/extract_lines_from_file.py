#!/usr/bin/python3.1
## Use regex matching to search for string
## in file and select lines where there is a match
## Lines are gathered into one list, and each line
## is split using ':' as a separator

## Input file should look something similar to this ->

## one:two:three:four:five:six
## four:five:six:seven:eight:nine

##
import re

## We define our search term here, consider using var
search_term = r'%s' % 'six'
## We create a list object, to which we will add
## matching lines from input file
li = []
with open("/tmp/searchf",'rt') as f:
    found = False
    for line in f.readlines():
        ## If our search_term is existing anywhere in the line
        if re.search(search_term, line):
            found = True
        if found:
            ## We remove any leading/trailing whitespace
            line = line.strip()
            ## Then append line to list, after splitting it
            li += (line.split(':'))
f.close()
print(li)