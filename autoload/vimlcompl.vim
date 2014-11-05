let s:save_cpo = &cpo
set cpo&vim

let s:script_dirname = expand( '<sfile>:p:h' )


" interface {{{1
func! vimlcompl#complete( findstart, base )
    if a:findstart
        let line = getline('.')
        let start = col('.') - 1
        while start > 0 && line[ start - 1 ] =~ '\i'
            let start -= 1 
        endwhile
        return start
    else
        let synname = s:get_syntax_name()
        if synname == 'vimString' || synname == 'vimLineComment'
            return []
        endif
        let results = []
        let line = getline('.')[ : col('.') - 2 ]
        if line =~ '^\s*\%(\a[[:alnum:]_]*\)$' " commands?
            let results = s:make_global_cmds() + s:make_builtin_cmds()
        elseif line =~# '\%(&\|&l:\)$' " options?
            let results = s:make_options()    
        elseif line =~# ':$' " namespaces?
            let results = s:make_vars_or_funcs( line )
        else
            let results = s:make_global_funcs()
            \           + s:make_global_cmds()
            \           + s:make_builtin_cmds()
            \           + s:make_builtin_funcs()
            \           + s:make_local_vars()
        endif
        let pat = '^' . a:base
        return map( filter( results, 'v:val.name =~ pat' ),
        \           'v:val.to_candidate()' )
    endif
endfunc


func! vimlcompl#help()
    let word = s:get_word_in_syntax()
    let synname = s:get_syntax_name()
    if     synname == 'vimFuncName' | let word .= '('
    elseif synname == 'vimOption'   | let word = "'" . word . "'"
    elseif synname == 'vimCommand'  | let word = ':' . word
    endif
    try
        exec printf( 'help %s', word )
    catch
        call s:echohl( 'Error', 'no such a help tag "%s"', word )
    endtry
endfunc


" candidate {{{1
func! s:make_vars_or_funcs( line )
    if     a:line =~# 's:$'
        return s:make_script_funcs() + s:make_script_vars()
    elseif a:line =~# 'l:$'
        return s:make_local_vars()
    elseif a:line =~# 'a:$'
        return s:make_local_args()
    endif
    for pat in [ 'g:', 'w:', 'b:', 't:' ]
        if a:line =~# pat . '$' | return s:make_variables( pat ) | endif
    endfor
    return []
endfunc


func! s:make_local_vars()
    return s:make_objects_with_func( s:in_function_lines(), 's:let_object', 'l:' )
endfunc


func! s:make_script_vars()
    return s:make_objects_with_func( s:whole_lines(), 's:let_object', 's:' )
endfunc


func! s:make_global_funcs()
    return s:make_objects_with_func( s:redir_lines( 'function' ), 's:funcdef_object' )
endfunc


func! s:make_script_funcs()
    return s:make_objects_with_func( s:whole_lines(), 's:funcdef_object', 's:' )
endfunc


func! s:make_local_args()
    let def_line = s:in_function_lines()[ - 1 ]
    let func_def = s:funcdef_object( def_line )
    if empty( func_def ) | return [] | endif
    return map( func_def.get_args(), 's:object(v:val, "a:", "v")' )
endfunc


func! s:make_global_cmds()
    let pat = '^!\=\s\+\(\u[[:alnum:]_]*\)'
    let words = s:matches_from_lines( s:redir_lines( 'command' ), pat )
    return s:make_objects_with_words( words, 'command', 'c' )
endfunc


func! s:make_variables( ns )
    let pat = '^\(\a[[:alnum:]_#]*\)'
    let words = s:matches_from_lines( s:redir_lines( 'let ' . a:ns ), pat )
    return s:make_objects_with_words( words, a:ns, 'v' )
endfunc


func! s:make_builtin_funcs()
    let filename = s:script_dirname . '/builtinfuncs.dict'
    if filereadable( filename )
        return s:make_objects_with_func( readfile( filename ), 's:funcdef_object' )
    endif
    return []
endfunc


func! s:make_builtin_cmds()
    let filename = s:script_dirname . '/builtincmds.dict'
    if filereadable( filename )
        return s:make_objects_with_words( readfile( filename ), 'command', 'c' )
    endif
    return []
endfunc


func! s:make_options()
    let candidates = []
    for line in s:redir_lines( 'set all' )
        for opt in split( line, '\s\+' )
            let lhs = s:matchgroup( opt, '^\(\a\+\)=\%(.\+\)\=', 1 )
            if lhs == '' | continue
            elseif lhs == 'errorformat' | break
            else | call add( candidates, s:object( lhs, 'option', 'o' ) )
            endif
        endfor
    endfor
    return candidates
endfunc


" candidate.object {{{1

" each candidate objects require to define:
"   name : name of candidate (to be used to compare with query).
"   to_candidate() : convert object into vim completion candidate.


let s:funcdef_pat = '^fu\%[nction]\%(!\)\=\s\+\(s:\)\=\(\a[[:alnum:]#_]*\)\s*(\(.*\)\{-})'
func! s:funcdef_object( line )
    let mlist = matchlist( a:line, s:funcdef_pat )
    if empty( mlist ) | return {} | endif
    let self = { 'ns' : mlist[1],
    \            'name' : mlist[2],
    \            'argsstr' : mlist[3] }

    func! self.to_candidate()
        let syntax = self.ns . '(' . s:strip(self.argsstr) . ')'
        return s:candidate( self.name, syntax, 'f' )
    endfunc

    func! self.get_args()
        let args = []
        for arg in map( split( self.argsstr, ',' ), 's:strip( v:val )' )
            if arg == '...' | let arg = '000' | endif
            call add( args, arg )
        endfor
        return args
    endfunc

    return self
endfunc


let s:let_pat = '^\s*let\s\+\(l:\|s:\|g:\)\=\(\a[[:alnum:]_]*\)\s*=\(.\+\)'
func! s:let_object( line )
    let mlist = matchlist( a:line, s:let_pat )
    if empty( mlist ) | return {} | endif
    let self = { 'ns' : empty(mlist[1]) ? 'l:' : mlist[1],
    \            'name' : mlist[2],
    \            'expr' : mlist[3] }

    func! self.to_candidate()
        return s:candidate( self.name, self.ns, 'v' )
    endfunc

    return self
endfunc


func! s:object( word, menu, kind )
    let self = { 'name' : a:word, 'menu' : a:menu, 'kind' : a:kind }

    func! self.to_candidate()
        return s:candidate( self.name, self.menu, self.kind )
    endfunc

    return self
endfunc


func! s:make_objects_with_func( lines, map_func, ... )
    let objects = map( a:lines, printf( '%s( v:val )', a:map_func ) )
    let predicate = ( len(a:000) == 0 )
    \             ? '!empty(v:val)'
    \             : printf( '!empty(v:val) && v:val.ns == "%s"', a:1 )
    return filter( objects, predicate )
endfunc


func! s:make_objects_with_words( words, menu, kind )
    return map( a:words, 's:object( v:val, a:menu, a:kind )' )
endfunc


func! s:candidate(word, menu, kind)
    return { 'word' : a:word,
    \        'menu' : a:menu,
    \        'kind' : a:kind,
    \        'icase' : &l:ignorecase,
    \ }
endfunc


" getlines {{{1
func! s:redir_lines(cmd)
    " retuns string to be redirected by "cmd"(string).
    let s = ''
    redir => s
    silent! exec a:cmd
    redir END
    return split( s, '\n' )
endfunc


func! s:in_function_lines()
    let list = []
    for i in range( line('.'), 1, -1 )
        let line = getline( i )
        if line =~# '^endf' | break
        else
            call add( list, line )
            if line =~# '^fu' | break | endif
        endif
    endfor
    return list
endfunc


func! s:whole_lines()
    return getline( 1, line('$') )
endfunc


" string {{{1
func! s:strip( s )
    return substitute( substitute( a:s, '\s\+$', '', '' ), '^\s\+', '', '' )
endfunc


func! s:matchgroup( str, pattern, num )
    let l = matchlist( a:str, a:pattern )
    if len(l) > a:num
        return l[ a:num ]
    endif
    return ''
endfunc


func! s:matches_from_lines( lines, pattern, ... )
    let group_no = ( empty( a:000 ) ? 1 : a:1 )
    return filter( map( a:lines, 's:matchgroup( v:val, a:pattern, group_no )' ),
    \              '!empty( v:val )' )
endfunc


" helper.vim {{{1
func! s:get_syntax_name()
    let offset = ( mode() == 'i' ) ? -1 : 0
    let id = synID( line('.'), col('.') + offset, 0 )
    return synIDattr( id, "name" )
endfunc


func! s:get_word_in_syntax()
    let [line, col] = [line('.'), col('.')]
    let current_line = getline('.')
    let id = synID( line, col, 0 )
    " find start position
    let start = col
    while start >= 1
        if id != synID( line, start-1, 0 ) | break | endif
        let start -= 1
    endwhile
    " find end position
    let end = col
    let length = len( current_line )
    while end <= length
        if id != synID( line, end + 1, 0 ) | break | endif
        let end += 1
    endwhile
    let word = current_line[ start - 1 : end - 1 ]
    return word
endfunc


func! s:echohl( hl, fmt, ... )
    let print_format = []
    if len(a:000) == 0
        let print_format = [ a:fmt . '%s', '' ]
    else
        let print_format = [ a:fmt ] + a:000
    endif
    try
        exec printf( 'echohl %s', a:hl )
        echomsg call( 'printf', print_format )
    finally
        echohl None
    endtry
endfunc


let &cpo = s:save_cpo
unlet s:save_cpo
