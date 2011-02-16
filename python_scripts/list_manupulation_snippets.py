#!/usr/bin/env python3.1
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

## Convert a list into a string, useful for output purposes
my_list = ['a','b','c']
new_string = "".join(map(str, my_list))

## Build new list with items that contain 's'
a = ['sa','sb','db','da','sw','mo','mu']
[x for x in a if 's' in x ]

## Splitting-up items in a list
a = ['a:b','c:d','e:f']
n = list(itertools.chain(*(s.split(':') for s in a)))

## Take list of items and create combinations of items 4 per line
## write each generated line into a file, after converting it from list to str
x = ('sam', 'joe', 'bob', 'nate', 'bill', 'red', 'green', 'orange', 'yellow')
f = open('/tmp/lists', 'w')
for a in itertools.combinations(x,4):
    h = " ".join(a)
    f.write(h+'\n')
f.close()
