#!/usr/bin/python3.1
##
##
## Lists and various manipulation of lists in python

## Take list and split it into two lists, one with all words starting with 'x'
## the other with all words starting with anything other than 'x'
words = ['xoom', 'xara', 'xero', 'shoom', 'xschool', 'zero']
list_1 = [word for word in words if word[0] == 'x']
list_2 = [word for word in words if word[0] != 'x']

## Similar sorting to above, but using only one list, instead of two
## does a normal sort of words, and then sorts based on whether or not
## word starts with 'x'
final_list = sorted(words)
final_list = sorted(final_list, key=lambda word: word[0] != 'x')

## Iterate over a list of items using a step of '1'
dir_name = ['dir1','dir2','dir3']
b = iter(range(len(dir_name)))
for a in b:
    print(dir_name[a])

## Iterate over a list of items using a step of '2'
## resuling in every other item returned
dir_name = ['dir1','dir2','dir3']
for a in iter(range(0,len(dir_name),2)):
    print(dir_name[a])