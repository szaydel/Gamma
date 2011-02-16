#!/usr/bin/python3.1
##
##
##
## %prog in USAGE is obtained via 'os.path.basename(sys.argv[0])'
USAGE = '%prog [options] argument1 argument2'
VERSION = 'Fill-in something meaningful'
ERRORS = {}
ERRORS[0] = 'Critical arguments --filename and --mode are required.'
ERRORS[1] = 'Errors here two...'

import optparse
from sys import argv

## Check number of arguments
print(len(argv))

def main():
    """parse_options() -> opts, args
  
    Parse the command-line options given returning both
    the parsed options and arguments.
    """

    ## myargs = ['-m', 'expert', '-f', '/tmp/filen'] ## Only required for testing
    
    parser = optparse.OptionParser(usage=USAGE)
    parser.add_option("-v", "--verbose",
                    action="store_true", dest="verbose", default=True,
                    help="make lots of noise [default]")
    parser.add_option("-q", "--quiet",
                    action="store_false", dest="verbose",
                    help="be vewwy quiet (I’m hunting wabbits)")
    parser.add_option("-f", "--filename",
                    metavar="FILE", help="write output to FILE")
    parser.add_option("-m", "--mode",
                    default="intermediate",
                    help="interaction mode: novice, intermediate, "
                        "or expert [default: %default]")
    (opts,args) = parser.parse_args()
  
    if not (opts.filename or opts.mode):
        print("ERROR: %s" % ERRORS[0])
        parser.print_help()
        raise SystemExit(1)
    elif len(argv) <= 1:
        parser.print_usage()

    return opts, args

## We call the main function and create a tuple based on the results from
## executing the actual function
if __name__ == '__main__':
    (opts,args) = main()
    

filein = opts.filename
mode = opts.mode

print(filein,mode)