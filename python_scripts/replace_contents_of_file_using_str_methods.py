#!/bin/python3.1
## We read contents of a file, make necessary
## adjustements using regex
## and write out changed contents to new file
f_in = open('/tmp/file.in','r')
f_out = open('/tmp/file.out','a')

## Our regex compiled, we will use it to match with
## lines in the input file
selection = '^(s|t){1}[a-z]{0,3}'
replacement = 'eagnmn-dr-001 eagnmn-dr-002 eagnmn-dr-003'

p = re.compile('(eagn|samt)[a-z,0-9].*$')

## Create variable to 
read_f_in = f_in.readlines()
for line in read_f_in:
    if p.search(line):
        line = re.sub(p,replacement,line)
        print('Wrote out to file f_out',line)
        f_out.writelines(line)
    else:
        f_out.writelines(line)