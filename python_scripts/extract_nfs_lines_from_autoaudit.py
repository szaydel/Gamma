#!/usr/bin/python3.1
##
##
##
import re, shlex
from sys import argv as cmnd_args
from optparse import OptionParser

## Define required variables
missing_args = 'Received less than expected number of arguments. --file and --output are required!'

mystr = re.compile('^\#{2}fstab\#{2}([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})', re.VERBOSE)

### Make sure we have a valid number of command line arguments
def file_count(x):
    if x < 3:
        return('You may not have enough arguments.')
        SystemExit(1)

def extr_nfs_entry(file_l):
    new_l = []
    for each_file in file_l:
        with open(each_file, 'rt') as stream:
            for line in stream.readlines():
        ## This is where we select the hostname line, and extract IP address
        ## of the client
                if '##getent-hostname##' in line:
                    cli_IP = line.rsplit('#')[4].split(' ')[0]
                    ## print(cli_IP)
                if re.match(mystr,line):
                    ''' For each matching line, we need to do a few things
                        1) remove ##fstab## from line
                        2) Create a list containing Client IP, NFS IP, Export
                    '''
                    rewr_line = re.sub('^##fstab##','',line).split(' ')[0].split(':')
                    rewr_line.insert(0,cli_IP)
                    new_l.append(rewr_line)
                stream.close()
    return(new_l)

parsed_nfs_li = []

in_file_count = len(cmnd_args) - 4

file_count(in_file_count)

USAGE = 'command --file file1 [file2 file3 ...] --output file.out'
VERSION = 'Fill-in something meaningful'
ERRORS = {}
ERRORS[0] = 'Missing Input or Output files, please make sure to supply both!'
ERRORS[1] = 'Errors here two...'

## New added on 01/20/2011 - Adding parser option
def parse_options():
    """parse_options() -> opts, args
  
    Parse the command-line options given returning both
    the parsed options and arguments.
    """
  
    parser = OptionParser(usage=USAGE, version=VERSION)  ## Establish our parser
    ## Define all options for parser to work with
    ## Add options to parser and define number of files 
    parser.add_option('-f', '--file',
                      action='store',
                      dest='multi', default=False, help='Input File(s)',
                      nargs=in_file_count)
    
    parser.add_option('-o', '--output',
                      action='store',
                      dest='out', default=False, help='Output File(s)',
                      )
  
    (options, args) = parser.parse_args()
    #print(options.multi, options.out)
    if not (options.multi or options.out):
        print("ERROR: %s" % ERRORS[0])
        parser.print_help()
        raise SystemExit(1)

    return options, args
    
(options, args) = parse_options()

    
### Define our command line arguments
files_in = options.multi  # files_in is based on '-f --file' flag defined
file_out = options.out  # file_out is based on '-o, --output' flag defined
# print('My input files:',files_in, file_out)
# 

## Execute main function and store results in the 'results' variable
results = extr_nfs_entry(files_in)

## Create an empty list to hold values pulled from reading input files
## the value here is that we will prevent duplicates from being written
## to output file
output_list = []

## Write lines to output file
with open(file_out, 'at') as f_out:
    for line in results:
        if line not in output_list:
            output_list.append(line)
            f_out.write(" ".join(map(str, line))+'\n')
f_out.close()
raise SystemExit(0)