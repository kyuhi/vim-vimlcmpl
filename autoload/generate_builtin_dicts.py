from __future__ import print_function
import re
import os
import sys


def writelist( name, lst ):
    with open( name, 'w' ) as fp:
        fp.write( '\n'.join( lst ) + '\n' )


def lines_in_dir( dirname, ignore_prefixs=() ):
    lines = []
    for filename in os.listdir( dirname ):
        if any( filename.startswith( prefix ) for prefix in ignore_prefixs ):
            continue
        fullpath = os.path.join( dirname, filename )
        if not os.path.isfile( fullpath ):
            continue
        with open( fullpath ) as fp:
            lines.extend( fp.readlines() )
    return lines


def main(doc_root_dir):
    # search commands and write
    cmd_rx = re.compile( r':(\[\w+\])?(?P<word>[a-z]\w*(\[\w+\])?)' )
    cmd_set = set()
    cmd_lines = lines_in_dir( doc_root_dir, ignore_prefixs=('os', 'tags') )
    for line in cmd_lines:
        m = cmd_rx.match( line )
        if not m: continue
        try:
            name = m.group( 'word' )
            cmd_set.add( name.replace('[', '').replace(']', '') )
        except IndexError:
            pass
    writelist( 'builtincmds.dict', cmd_set )

    # search functions and write
    fun_rx = re.compile( r'([a-z][a-z0-9_]*)\(([a-zA-Z0-9_, \{\}\]\[]*?)\)' )
    fun_set = set()
    with open( os.path.join( doc_root_dir, 'eval.txt' ) ) as fp:
        for line in fp.readlines():
            m = fun_rx.match( line )
            if not m: continue
            args = re.sub( '[\{\}]', '', m.group(2).strip() )
            fun_set.add( 'function! {}({})'.format( m.group(1), args ) )
    writelist( 'builtinfuncs.dict', fun_set )


def usage_quit( scriptname, msg='' ):
    message = '{} vim_document_root_dir\n{}'.format( scriptname, msg )
    print( message, file=sys.stderr ) 
    quit(1)


if __name__ == '__main__':
    args = sys.argv
    if len( args ) == 1:
        usage_quit( args[0] )
    if not os.path.isdir( args[1] ):
        usage_quit( args[0], '{} is not directory'.format( args[1] ) )
    main( args[1] )
