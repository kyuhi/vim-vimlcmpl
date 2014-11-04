let s:save_cpo = &cpo
set cpo&vim


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
        if s:iscommand( line )
            let results = s:make_global_cmds() + s:make_builtin_cmds()
        elseif s:endswith( line, '&' ) || s:endswith( line, '&l:' ) " options
            let results = s:make_options()    
        elseif s:endswith( line, ':' ) " expressions
            let results = s:make_vars_or_funcs( line )
        else
            let results = s:make_global_funcs()
            \           + s:make_global_vars()
            \           + s:make_global_cmds()
            \           + s:make_builtin_cmds()
            \           + s:make_builtin_funcs()
        endif
        return filter( results, 'match(v:val.word, a:base) == 0' )
    endif
endfunc


func! vimlcompl#help()
    let word = s:get_word_in_syntax()
    let synname = s:get_syntax_name()
    if synname == 'vimFuncName'
        let word .= '('
    elseif synname == 'vimOption'
        let word = "'" . word . "'"
    elseif synname == 'vimCommand'
        let word = ':' . word
    endif
    try
        exec printf( 'help %s', word )
    catch
        call s:echohl( 'Error', 'no such a help tag "%s"', word )
    endtry
endfunc


" make candidates ------------------------------------------------------------
func! s:make_vars_or_funcs( line )
    if s:endswith( a:line, 's:' )
        return s:make_script_funcs() + s:make_script_vars()
    elseif s:endswith( a:line, 'g:' )
        return s:make_global_vars()
    elseif s:endswith( a:line, 'l:' )
        return s:make_local_vars()
    elseif s:endswith( a:line, 'a:' )
        return s:make_local_args()
    else
        return []
    endif
endfunc


func! s:make_local_vars()
    return s:make_candidates( s:in_function_lines(),
    \                         'let\s\+\([a-zA-Z0-9_]\+\)',
    \                         'l:var',
    \                         'v' )
endfunc


func! s:make_global_vars()
    return s:make_candidates( s:redir_lines( 'let g:' ),
    \                         '^\(\w\+\)',
    \                         'g:var',
    \                         'v' )
endfunc


func! s:make_global_funcs()
    return s:make_candidates( s:redir_lines( 'function' ),
    \                         '^function\s\+\([a-zA-Z0-9#_]\+\)',
    \                         'g:fun',
    \                         'f' )
endfunc


func! s:make_global_cmds()
    return s:make_candidates( s:redir_lines( 'command' ),
    \                         '^!\=\s\+\([a-zA-Z0-9_]\+\)',
    \                         'cmd',
    \                         'c' )
endfunc


func! s:make_script_funcs()
    return s:make_candidates( s:whole_lines(),
    \                         '^fu\a*!\s\+s:\([a-zA-Z0-9_]\+\)',
    \                         's:fun',
    \                         'f' )
endfunc


func! s:make_script_vars()
    return s:make_candidates( s:whole_lines(),
    \                         'let\s\+s:\([a-zA-Z0-9_]\+\)',
    \                         's:var',
    \                         'v' )
endfunc


func! s:make_builtin_funcs()
    return s:make_candidates_from_file(
    \           expand('<sfile>:p:h') . '/builtinfuncs.dict',
    \           'func', 'f' )
    
endfunc


func! s:make_builtin_cmds()
    return s:make_candidates_from_file(
    \           expand('<sfile>:p:h') . '/builtincmds.dict',
    \           'cmd', 'c' )
endfunc


func! s:make_local_args()
    let candidates = []
    let lines = s:in_function_lines()
    let last_line = lines[ -1 ]
    if !s:ismatch( last_line, '^fu' )
        return candidates
    endif
    let func_pat = '^fu\a*!\s\+s\=:\=[a-zA-Z0-9#_]\+\s*(\(.\+\))'
    let m = s:matchgroup( last_line, func_pat , 1 )
    if empty( m )
        return candidates
    endif
    for arg in split( m, ',' )
        let arg = s:strip( arg )
        let arg = (arg == '...') ? '000' : arg
        call add( candidates, s:candidate( s:strip(arg), 'a:var', 'v' ) )
    endfor
    return l:candidates
endfunc


func! s:make_options()
    let candidates = []
    for line in s:redir_lines( 'set all' )
        for opt in split(line, '\s\+')
            let lhs = s:matchgroup( opt, '\(\a\+\)=\(.\+\)', 1 )
            if lhs != ''
                call add( candidates, s:candidate( lhs, 'opt', 'o' ) )
                if lhs == 'errorformat'
                    break
                endif
            elseif s:ismatch( opt, '\a\+' )
                call add( candidates, s:candidate( opt, 'opt', 'o' ) )
            endif
        endfor
    endfor
    return candidates
endfunc


func! s:candidate( word, menu, kind )
    return { 'word' : a:word,
    \        'menu' : '[' . a:menu . ']',
    \        'kind' : a:kind
    \ }
endfunc


func! s:make_candidates( lines, pattern, menu, kind )
    let candidates = []
    for line in a:lines
        let m = s:matchgroup( line, a:pattern, 1 )
        if !empty( m )
            call add( candidates, s:candidate( m, a:menu, a:kind ) )
        endif
    endfor
    return candidates
endfunc


func! s:make_candidates_from_file( filename, menu, kind )
    if filereadable( a:filename )
        return map( readfile( a:filename ),
        \           's:candidate( v:val, a:menu, a:kind )' )
    else
        return []
    endif
endfunc



" get lines ------------------------------------------------------------------
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
        if s:ismatch( line, '^endf' )
            break
        elseif s:ismatch( line, '^fu' )
            call add( list, line )
            break
        else
            call add( list, line )
        endif
    endfor
    return list
endfunc


func! s:whole_lines()
    return getbufline( bufnr('%'), 1, line('$') )
endfunc


" helper functions for strings -----------------------------------------------
func! s:ismatch( str, pat )
    return match( a:str, a:pat ) == 0
endfunc


func! s:startswith( str, start )
    if -1 != match( a:str, '^' . a:start )
        return 1
    else
        return 0
    endif
endfunc


func! s:endswith( str, end )
    if -1 != match( a:str, a:end . '$' )
        return 1
    else
        return 0
    endif
endfunc


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


func! s:iscommand( s )
    return match( a:s, '^\s\+$' ) != -1 || match( a:s, '^\s\+\w\+$' ) != -1
endfunc


" etc ------------------------------------------------------------------------
func! s:get_syntax_name()
    let offset = mode() == 'i' ? -1 : 0
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
        if id != synID( line, end+1, 0 ) | break | endif
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
        exec printf('echohl %s', a:hl )
        echomsg call( 'printf', print_format )
    finally
        echohl None
    endtry
endfunc


let &cpo = s:save_cpo
unlet s:save_cpo
