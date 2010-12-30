
time.localtime(os.path.getmtime('/tmp/file1'))      # Will produce a tuple, like below
## time.struct_time(tm_year=2010, tm_mon=12, tm_mday=28, tm_hour=13, tm_min=23, tm_sec=36, tm_wday=1, tm_yday=362, tm_isdst=0)
x = time.localtime(os.path.getmtime('/tmp/file1'))
## Some examples of what could be done with the Tuple(x)
time.strftime("%a, %d %b %Y %H:%M:%S +0000",x)      # Tue, 28 Dec 2010 13:23:36 +0000
time.strftime("%a, %d %b %Y %H:%M:%S %Z",x)         # Tue, 28 Dec 2010 13:23:36 PST
time.strftime("%a, %d %b %Y %I:%M:%S %p %Z",x)      # Tue, 28 Dec 2010 01:23:36 PM PST
time.strftime("%a, %d %b %Y %H:%M:%S +0000",x)      # Tuesday, 28 Dec 2010 13:23:36 +0000

## Working backwards, we can convert formatted time/date into a struct_time tuple
y = time.strptime('Tue, 28 Dec 2010 13:23:36', \
                  "%a, %d %b %Y %H:%M:%S")          # Will produce a tuple, like below
## time.struct_time(tm_year=2010, tm_mon=12, tm_mday=28, tm_hour=13, tm_min=23, tm_sec=36, tm_wday=1, tm_yday=362, tm_isdst=-1)