#!/usr/bin/python3.1
## Build nested list from lines read from
## input file, and create final list where
## nested lists are combined and nesting
## eliminated

## Define list variable for our final 
final_li = []

## Open file and assign object to variable f
with open('/tmp/searchf','rt') as f:
    ## For every line in file create a list inside of main
    ## nested_li list
    nested_li = [x.strip().split(':') for x in f.readlines()]
    
    ## Use 'for' loop to build final list without
    ## using nesting
    for iterator in nested_li:
        final_li += iterator
    print(final_li)
    f.close()