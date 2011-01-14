def check_md5sum(indx,fil):
    ## If unable to locate checksum index file,
    ## we raise an exception
    try:
        index_f = open(indx, 'r')
    except IOError as err:
        print('[Critical] I/O Error: {0}'.format(err))

    for line in index_f:            
        if fil in line:
            ## Each line will look something like this:
            ## ['/tmp/file1', '1f18348f32c9a4694f16426798937ae2']

            ## If we find the name of the file matching 'fil' variable
            ## we store second item in the list in a variable named
            ## 'old_hash', because this is the hash which we recorded
            ## at some point and stored it in the index file
            old_hash = line.split()[1]
            new_hash = hashlib.md5(open(fil,'rb').read(10240)).hexdigest()
            print('Checking MD5SUM of file: ',fil,'against index file',indx)
            
            ## If the two hashes match, we know the file remains untouched
            ## and we do not need to worry about it, anything else means
            ## the file changed
            if new_hash == old_hash:
                print('[GOOD] MD5SUM of File [',fil,'] did not change since last generation.')
            else:
                print('[WARN] MD5SUM of File [',fil,'] did change since last generation.')         
    index_f.close()