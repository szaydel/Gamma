#!/usr/bin/python3.1
##
##
##
def compare(a, b):
    """
    >>> compare(5, 4)
    1
    >>> compare(7, 7)
    0
    >>> compare(2, 3)
    -1
    >>> compare(42, 1)
    1
    """
# Your function body should begin here.
    if isinstance(a,str) or isinstance(b,str):
        print('Only numeric characters are acceptable.')
    else:
        if a > b:
            return 1
        elif a == b:
            return 0
        else:
            return -1
        
        
if __name__ == '__main__':
    import doctest
    doctest.testmod()
    
def hypotenuse(a, b):
    """
    >>> hypotenuse(3, 4)
    5.0
    >>> hypotenuse(12, 5)
    13.0
    >>> hypotenuse(7, 24)
    25.0
    >>> hypotenuse(9, 12)
    15.0
    """
    if isinstance(a,str) or isinstance(b,str):
        print('Only numeric characters are acceptable.')
    else:
        c = pow(pow(a,2)+pow(b,2),0.5)
        return c

def is_multiple(m, n):
    """
    >>> is_multiple(12, 3)
    True
    >>> is_multiple(12, 4)
    True
    >>> is_multiple(12, 5)
    False
    >>> is_multiple(12, 6)
    True
    >>> is_multiple(12, 7)
    False
    """
    if isinstance(m,str) or isinstance(n,str):
        print('Only numeric characters are acceptable.')
    else:
        if m % n == 0:
            return True
        else:
            return False
    
if __name__ == '__main__':
    import doctest
    doctest.testmod()