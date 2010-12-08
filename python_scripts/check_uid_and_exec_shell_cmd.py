#!/usr/bin/python3.1
import getpass,os,pwd,sys
file_list = sys.argv[1:]
## Method to test if file is writable
## os.access(os.path.join(os.curdir,'name_of_file'), os.W_OK)
# file_list = s.split()
#for each_item in file_list:
#    each_item = os.path.join(os.curdir,each_item)
#    if not os.access(each_item,os.W_OK):
#        print('Unable to write/remove file')
#    else:
#        print('Deleting File:',each_item)
#    ## x = os.remove(each_item)
#    ## Testing for read access
#        if not os.access(each_item,os.F_OK):
#            print('Successfully deleted file:',each_item)
#    # print(os.path.dirname(each_item))

## with open("/tmp/stdout.txt","wb") as out:

## We first determine if the user is root or non-root
def verify_user():
    myname = pwd.getpwnam(getpass.getuser())
    ## or this is another way
    ## myname = os.environ.get('USER')
    myuid = myname.pw_uid
    if myuid is not 0:
        print(myname.pw_name,' You are not currently root. Run this command as root.', end='\n')
        ret_code = 1
        return (ret_code)
    else:
        ## print(myname,' is root, as expected.')
        return 0

(ret_code) = verify_user()
## If exist status '1' cannot continue further

x = (ret_code)

if x is not 0:
    print('Do something here...')
else:
    print('Do something-else here...')
    

### Open the file for writing first
#with open("/tmp/stderr.txt","wb") as PIPE:
#    p = subprocess.Popen(('/bin/ls','/tmp'),shell=True,stdout=PIPE,stderr=PIPE)
#    ret_code = p.wait()
#    if ret_code is int(0):
#        print('Good')
#    else:
#        print('Bad')