#!/usr/bin/python3.1
##
##
##
## Compare hash of the file currently to one
## recorded earlier in the index file
## Function expects to receive two input
## items, one is the index file and other
## is the name of file which should be checked

debug = 'n'
import datetime,hashlib,os,re,sys

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

def new_line(input):
    print()

def begin_end(input):
    print('>>>>',input,'<<<<')
    
## Will print a line of text similar to:
## Your custom input <filename> last modified on:
def print_last_mod(text,fil):
    print(text,fil,'last modified on:',end='\t')

## Establish a timestamp for a file
## input should be a string with filename, i.e.:
## '/path/to/filename'
def get_timestap(fil):
    t_formt = '%a, %B %Y, at %H:%M:%S'
    tstamp = print(datetime.datetime.fromtimestamp(os.path.getmtime(fil)).strftime(t_formt))
    return(tstamp)
    
def dr_version_exists(fil,sfx):
    ## Basic details about Production version of the file
    print(80 * '#')
    print_last_mod('PROD:',fil)
    get_timestap(fil)
    dr_file = fil.replace(fil,fil+'.'+dr_suffix)    ## Set name of DR file from Prod file
    ## Hopefully 'DR' version of the file exists and
    ## we collect some basic details about the file
    if os.path.exists(dr_file):
        print(80 * '#','\n'+'DR Version of Config File '+dr_file, 'exists.')
        
        print_last_mod('*',dr_file)
        get_timestap(dr_file)
    else:
        print(80 * '#','\n'+'DR Version of Config File '+dr_file, 'does not exist, and should be created.')

def check_md5sum(indx,fil):
    index_f = open(indx, 'r')
    for line in index_f:
        line_by_line = line.split()
        z = re.match(fil, line_by_line[0],re.VERBOSE)
        if not z == None:
            new_hash = hashlib.md5(open(fil,'rb').read(10240)).hexdigest()
            print('Checking MD5SUM of file: ',fil,'against index file',indx)
            if new_hash == line_by_line[1]:
                print('[GOOD] MD5SUM of File [',fil,'] did not change since last generation.')
            else:
                print('[WARN] MD5SUM of File [',fil,'] did change since last generation.')
    index_f.close()

## Production file array consists of the following files
default_f = ['/tmp/file1','/tmp/file2','/tmp/file3','/tmp/file4']
prod_f = []
for a in default_f:
    if os.path.exists(a):
        prod_f.append(a)

if debug == 'y':
    print('Production Array contains these files:', prod_f)

## Verify and update prod_f array, to make sure
## that production of file in the array is present

## Building array of DR files based on suffix
## established from 'DR_ENV' variable
dr_f = []

for a in prod_f:
    dr_f.append(a+'.'+dr_suffix)

if debug == 'y':
    print('DR Array contains these files:', dr_f)

for file in prod_f:
    dr_version_exists(file,dr_suffix)
    new_line('')
    check_md5sum('/tmp/chksum.index',file)
    begin_end('End')
    new_line('')
    #print_last_mod('P:',file)
    #get_timestap(file)