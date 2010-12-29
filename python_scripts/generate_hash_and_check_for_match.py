#!/usr/bin/python3.1
##
##
##


import os,sys
## OS has to export environment, in order for it to be
## accessible by this script

x = os.environ.get('DR_ENV')
if x == None:
    print('OS environment variable "DR_ENV" is not set, please set first.')
    sys.exit(1)
## If the OS environment variable is set and exported
## We will define the suffix of the DR file, whether test
## prod or something else.
else:   
    if x == 'DR.test':
        dr_suffix = 'DR.test'
    elif x == 'DR.prod':
        dr_suffix = 'DR.prod'
    else:
        dr_suffix = 'DR.test'

## Production file array consists of the following files
default_f = ['/tmp/file1','/tmp/file2','/tmp/file3','/tmp/file4']
prod_f = []
for a in default_f:
    if os.path.exists(a):
        prod_f.append(a)

print('Production Array contains these files:', prod_f)

## Verify and update prod_f array, to make sure
## that production of file in the array is present

## Building array of DR files based on suffix
## established from 'DR_ENV' variable
dr_f = []

for a in prod_f:
    dr_f.append(a+'.'+dr_suffix)

print('DR Array contains these files:', dr_f)

## We open a file 'write' to store our hashes
## for each production file
x = open('/tmp/chksum.index', 'w')

import hashlib
prod_f_hash = [(f, hashlib.md5(open(f,'rb').read(10240)).hexdigest()) for f in prod_f]
dr_f_hash = [(f, hashlib.md5(open(f,'rb').read(10240)).hexdigest()) for f in dr_f]

count = 0
while count < len(prod_f):

    b = prod_f_hash[count][0] + ' ' + prod_f_hash[count][1] + '\n'
    x.writelines(b)

    print('Prod-Hash','\t',prod_f_hash[count][1])
    print('DR-Hash','\t',dr_f_hash[count][1])
    
    if prod_f_hash[count][1] == dr_f_hash[count][1]:
        print('Match')
    else:
        print('No-match')
    count+=1        
x.close()

