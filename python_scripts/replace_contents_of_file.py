#!/bin/python3.1
## We read contents of a file, make necessary
## adjustements using regex
## and write out changed contents to new file
f_in = open('/tmp/file.in','r')
f_out = open('/tmp/file.out','a')
p = re.compile('s*.[0-9]{1,3}')
## Create variable to 
read_f_in = f_in.readlines()
for line in read_f_in:
    if p.search(line):
        line = re.sub(p,'relacement',line)
        print('Wrote out to file f_out',line)
        f_out.writelines(line)
    else:
        f_out.writelines(line)