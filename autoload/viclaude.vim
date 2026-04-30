" autoload/viclaude.vim - Claude Code conversation history browser

let s:session_files = []
let s:grep_pattern = ''

" Claude Code uses leading dash + slashes replaced with dashes
function! s:project_name(cwd) abort
  return substitute(substitute(a:cwd, '/', '-', 'g'), '\.', '-', 'g')
endfunction

function! s:project_dir(project_name) abort
  return expand('~/.claude/projects/' . a:project_name)
endfunction

function! viclaude#history() abort
  let s:grep_pattern = ''
  let l:cwd = getcwd()
  let l:project_name = s:project_name(l:cwd)
  let l:project_dir = s:project_dir(l:project_name)

  if !isdirectory(l:project_dir)
    echohl WarningMsg | echo 'No Claude sessions found for this project.' | echohl None
    return
  endif

  let l:files = glob(l:project_dir . '/*.jsonl', 0, 1)
  if empty(l:files)
    echohl WarningMsg | echo 'No Claude sessions found for this project.' | echohl None
    return
  endif

  let l:entries = []
  for l:file in l:files
    if !filereadable(l:file)
      continue
    endif
    let l:info = s:extract_session_info(l:file)
    if !empty(l:info)
      call add(l:entries, l:info)
    endif
  endfor

  if empty(l:entries)
    echohl WarningMsg | echo 'No Claude sessions found for this project.' | echohl None
    return
  endif

  " Sort by timestamp descending (most recent first)
  call sort(l:entries, {a, b -> a.timestamp ==# b.timestamp ? 0 : a.timestamp ># b.timestamp ? -1 : 1})

  let s:session_files = []
  let l:qflist = []
  for l:entry in l:entries
    call add(s:session_files, l:entry.file)
    call add(l:qflist, {
          \ 'text': '[' . l:entry.display_time . '] ' . l:entry.summary,
          \ })
  endfor

  call setqflist(l:qflist)
  copen
  " Buffer-local mapping to open selected session
  nnoremap <buffer> <silent> <CR> :call viclaude#select_entry()<CR>
endfunction

function! s:extract_user_text(content) abort
  if type(a:content) == v:t_string
    return a:content
  endif
  if type(a:content) == v:t_list
    for l:block in a:content
      if type(l:block) == v:t_dict && get(l:block, 'type', '') ==# 'text'
        return get(l:block, 'text', '')
      endif
    endfor
  endif
  return ''
endfunction

function! s:clean_user_text(text) abort
  let l:text = a:text
  " Remove known noise XML elements (tag + content)
  let l:text = substitute(l:text, '<local-command-caveat>\_.\{-}<\/local-command-caveat>', '', 'g')
  let l:text = substitute(l:text, '<command-name>\_.\{-}<\/command-name>', '', 'g')
  let l:text = substitute(l:text, '<command-message>\_.\{-}<\/command-message>', '', 'g')
  let l:text = substitute(l:text, '<command-args>\_.\{-}<\/command-args>', '', 'g')
  let l:text = substitute(l:text, '<local-command-stdout>\_.\{-}<\/local-command-stdout>', '', 'g')
  let l:text = substitute(l:text, '<system-reminder>\_.\{-}<\/system-reminder>', '', 'g')
  " Strip any remaining XML tags
  let l:text = substitute(l:text, '<[^>]\+>', '', 'g')
  " Trim leading whitespace and blank lines
  let l:text = substitute(l:text, '^\_s*', '', '')
  return l:text
endfunction

function! s:is_noise_message(text) abort
  return empty(a:text) || a:text =~# '^\s*$'
        \ || a:text =~# '^\[Request interrupted'
        \ || a:text =~# '^Caveat: The messages below'
        \ || a:text =~# '^Exit code \d'
        \ || a:text =~# '^/clear\>'
        \ || a:text =~# '^Implement the following plan:'
endfunction

function! s:extract_session_info(file) abort
  let l:lines = readfile(a:file, '', 50)
  let l:timestamp = ''

  for l:line in l:lines
    try
      let l:obj = json_decode(l:line)
    catch
      continue
    endtry

    if type(l:obj) != v:t_dict
      continue
    endif

    " Skip non-user messages
    if get(l:obj, 'type', '') !=# 'user'
      continue
    endif

    " Skip sidechain entries
    if get(l:obj, 'isSidechain', v:false)
      continue
    endif

    let l:msg = get(l:obj, 'message', {})
    if empty(l:msg)
      continue
    endif

    if get(l:msg, 'role', '') !=# 'user'
      continue
    endif

    " Capture timestamp from the first user message
    if empty(l:timestamp)
      let l:timestamp = get(l:obj, 'timestamp', '')
    endif

    let l:text = s:clean_user_text(s:extract_user_text(get(l:msg, 'content', '')))

    if s:is_noise_message(l:text)
      continue
    endif

    " Format timestamp: 2026-03-23T11:43:36.354Z → 2026-03-23 11:43
    let l:display_time = l:timestamp
    if len(l:timestamp) >= 16
      let l:display_time = l:timestamp[0:9] . ' ' . l:timestamp[11:15]
    endif

    " Truncate summary to a reasonable length, single line
    let l:summary = substitute(l:text, '\n.*', '', '')
    if len(l:summary) > 120
      let l:summary = l:summary[0:119] . '...'
    endif

    return {
          \ 'file': a:file,
          \ 'timestamp': l:timestamp,
          \ 'display_time': l:display_time,
          \ 'summary': l:summary,
          \ }
  endfor

  return {}
endfunction

function! viclaude#select_entry() abort
  let l:idx = line('.') - 1
  if l:idx < 0 || l:idx >= len(s:session_files)
    echohl ErrorMsg | echo 'Invalid session entry.' | echohl None
    return
  endif

  let l:file = s:session_files[l:idx]
  if !filereadable(l:file)
    echohl ErrorMsg | echo 'Session file not readable: ' . l:file | echohl None
    return
  endif

  " Extract UUID from filename for buffer name
  let l:uuid = fnamemodify(l:file, ':t:r')

  " Go to previous window (code window)
  wincmd p
  " Reuse the window if its buffer is empty and unmodified; otherwise split
  if line('$') == 1 && getline(1) ==# '' && !&modified && bufname('%') ==# ''
    enew
  else
    new
  endif

  " Set scratch buffer options
  setlocal buftype=nofile bufhidden=wipe noswapfile
  silent! execute 'file Claude:' . l:uuid

  " Render conversation
  let l:rendered = s:render_session(l:file)
  call setline(1, l:rendered)

  setlocal filetype=viclaude_discussion
  setlocal foldmethod=expr
  setlocal foldexpr=s:thinking_foldexpr(v:lnum)
  setlocal foldtext=s:thinking_foldtext()
  setlocal foldlevel=0
  setlocal nomodifiable

  " Section navigation: jump between user prompts
  nnoremap <buffer> <silent> ]] :<C-u>call <SID>jump_prompt(1)<CR>
  nnoremap <buffer> <silent> [[ :<C-u>call <SID>jump_prompt(0)<CR>

  " Go to top, then jump to grep match if applicable
  normal! gg
  if !empty(s:grep_pattern)
    let @/ = s:grep_pattern
    set hlsearch
    silent! normal! n
  endif
endfunction

function! s:jump_prompt(forward) abort
  let l:flags = a:forward ? 'W' : 'bW'
  while search('^> ', l:flags) > 0
    let l:lnum = line('.')
    if l:lnum == 1 || getline(l:lnum - 1) !~# '^> '
      return
    endif
  endwhile
endfunction

function! s:thinking_foldexpr(lnum) abort
  let l:line = getline(a:lnum)
  if l:line =~# '^\~ ' || l:line =~# '^< '
    return 1
  endif
  " Blank line right after a foldable block belongs to the fold
  if a:lnum > 1 && l:line ==# '' && (getline(a:lnum - 1) =~# '^\~ ' || getline(a:lnum - 1) =~# '^< ')
    return 1
  endif
  return 0
endfunction

function! s:thinking_foldtext() abort
  let l:count = v:foldend - v:foldstart
  if getline(v:foldstart) =~# '^< '
    return '< [Noise] (' . l:count . ' lines) '
  endif
  return '~ [Thinking] (' . l:count . ' lines) '
endfunction

function! s:render_session(file) abort
  let l:lines = readfile(a:file)
  let l:output = []
  let l:last_assistant_id = ''

  for l:raw in l:lines
    try
      let l:obj = json_decode(l:raw)
    catch
      continue
    endtry

    if type(l:obj) != v:t_dict
      continue
    endif

    " Skip non-message types
    let l:entry_type = get(l:obj, 'type', '')
    if l:entry_type ==# 'file-history-snapshot' || l:entry_type ==# 'progress'
      continue
    endif

    " Skip sidechain entries
    if get(l:obj, 'isSidechain', v:false)
      continue
    endif

    let l:msg = get(l:obj, 'message', {})
    if empty(l:msg) || type(l:msg) != v:t_dict
      continue
    endif

    let l:role = get(l:msg, 'role', '')
    let l:content = get(l:msg, 'content', '')
    let l:msg_id = get(l:msg, 'id', '')

    if l:role ==# 'user'
      " Check if this is a tool-result-only message (no human text)
      let l:has_text = v:false
      if type(l:content) == v:t_string
        let l:has_text = v:true
      elseif type(l:content) == v:t_list
        for l:block in l:content
          if type(l:block) == v:t_dict && get(l:block, 'type', '') ==# 'text'
            let l:has_text = v:true
            break
          endif
        endfor
      endif

      let l:is_noise = l:has_text &&
            \ s:is_noise_message(s:clean_user_text(s:extract_user_text(l:content)))
      if l:has_text && !l:is_noise
        if !empty(l:output)
          call add(l:output, '')
          call add(l:output, '---')
        endif
        call add(l:output, '')
      endif
      call s:render_user_content(l:content, l:output, l:has_text)
      if l:has_text && !l:is_noise
        call add(l:output, '')
        let l:last_assistant_id = ''
      endif

    elseif l:role ==# 'assistant'
      " Coalesce assistant turns with same message ID
      let l:new_turn = l:msg_id ==# '' || l:msg_id !=# l:last_assistant_id
      if l:new_turn
        let l:last_assistant_id = l:msg_id
      endif
      call s:render_assistant_content(l:content, l:output)
    endif
  endfor

  return l:output
endfunction

function! s:render_user_content(content, output, blockquote) abort
  if type(a:content) == v:t_string
    if a:blockquote
      let l:clean = s:clean_user_text(a:content)
      if a:content !=# l:clean
        let l:raw_lines = split(a:content, '\n')
        call map(l:raw_lines, {_, v -> '< ' . v})
        call extend(a:output, l:raw_lines)
      endif
      if !empty(l:clean)
        let l:lines = split(l:clean, '\n')
        call map(l:lines, {_, v -> '> ' . v})
        call extend(a:output, l:lines)
      endif
    else
      call extend(a:output, split(a:content, '\n'))
    endif
    return
  endif

  if type(a:content) != v:t_list
    return
  endif

  for l:block in a:content
    if type(l:block) != v:t_dict
      continue
    endif

    let l:btype = get(l:block, 'type', '')

    if l:btype ==# 'text'
      let l:raw = get(l:block, 'text', '')
      if a:blockquote
        let l:clean = s:clean_user_text(l:raw)
        if l:raw !=# l:clean
          let l:raw_lines = split(l:raw, '\n')
          call map(l:raw_lines, {_, v -> '< ' . v})
          call extend(a:output, l:raw_lines)
        endif
        if !empty(l:clean)
          let l:lines = split(l:clean, '\n')
          call map(l:lines, {_, v -> '> ' . v})
          call extend(a:output, l:lines)
        endif
      else
        call extend(a:output, split(l:raw, '\n'))
      endif

    elseif l:btype ==# 'tool_result'
      let l:result_content = get(l:block, 'content', '')
      let l:result_text = ''
      if type(l:result_content) == v:t_string
        let l:result_text = l:result_content
      elseif type(l:result_content) == v:t_list
        for l:rb in l:result_content
          if type(l:rb) == v:t_dict && get(l:rb, 'type', '') ==# 'text'
            let l:result_text = get(l:rb, 'text', '')
            break
          endif
        endfor
      endif
      if !empty(l:result_text)
        let l:result_lines = split(l:result_text, '\n')
        if len(l:result_lines) > 5
          let l:tmpfile = tempname()
          call writefile(l:result_lines, l:tmpfile)
          call add(a:output, '... (' . len(l:result_lines) . ' lines) ' . l:tmpfile)
        else
          call add(a:output, '```')
          call extend(a:output, l:result_lines)
          call add(a:output, '```')
        endif
        call add(a:output, '')
      endif
    endif
  endfor
endfunction

function! s:render_assistant_content(content, output) abort
  if type(a:content) != v:t_list
    return
  endif

  for l:block in a:content
    if type(l:block) != v:t_dict
      continue
    endif

    let l:btype = get(l:block, 'type', '')

    if l:btype ==# 'thinking'
      let l:thinking = get(l:block, 'thinking', '')
      if !empty(l:thinking)
        for l:line in split(l:thinking, '\n')
          call add(a:output, '~ ' . l:line)
        endfor
        call add(a:output, '')
      endif

    elseif l:btype ==# 'text'
      call extend(a:output, split(get(l:block, 'text', ''), '\n'))
      call add(a:output, '')

    elseif l:btype ==# 'tool_use'
      let l:name = get(l:block, 'name', '?')
      let l:input = get(l:block, 'input', {})
      if l:name ==# 'Bash'
        let l:cmd = get(l:input, 'command', '')
        if !empty(l:cmd)
          call add(a:output, '`[Tool: Bash]`')
          call add(a:output, '```bash')
          call extend(a:output, split(l:cmd, '\n'))
          call add(a:output, '```')
        else
          call add(a:output, '`[Tool: Bash]`')
        endif
      elseif l:name ==# 'Write'
        let l:path = get(l:input, 'file_path', '')
        let l:wcontent = get(l:input, 'content', '')
        call add(a:output, '`[Tool: Write]` `' . l:path . '`')
        if !empty(l:wcontent)
          let l:wlines = split(l:wcontent, '\n')
          if len(l:wlines) > 5
            let l:tmpfile = tempname()
            call writefile(l:wlines, l:tmpfile)
            call add(a:output, '... (' . len(l:wlines) . ' lines) ' . l:tmpfile)
          else
            call add(a:output, '```')
            call extend(a:output, l:wlines)
            call add(a:output, '```')
          endif
        endif
      elseif l:name ==# 'Edit'
        let l:path = get(l:input, 'file_path', '')
        let l:old = get(l:input, 'old_string', '')
        let l:new = get(l:input, 'new_string', '')
        call add(a:output, '`[Tool: Edit]` `' . l:path . '`')
        if !empty(l:old) || !empty(l:new)
          let l:diff_lines = []
          for l:dl in split(l:old, '\n')
            call add(l:diff_lines, '- ' . l:dl)
          endfor
          for l:dl in split(l:new, '\n')
            call add(l:diff_lines, '+ ' . l:dl)
          endfor
          if len(l:diff_lines) > 10
            let l:tmpfile = tempname()
            call writefile(l:diff_lines, l:tmpfile)
            call add(a:output, '... (' . len(l:diff_lines) . ' lines) ' . l:tmpfile)
          else
            call add(a:output, '```diff')
            call extend(a:output, l:diff_lines)
            call add(a:output, '```')
          endif
        endif
      else
        let l:context = s:tool_context(l:name, l:input)
        if !empty(l:context)
          call add(a:output, '`[Tool: ' . l:name . ']` ' . l:context)
        else
          call add(a:output, '`[Tool: ' . l:name . ']`')
        endif
      endif
      call add(a:output, '')
    endif
  endfor
endfunction

function! s:tool_context(name, input) abort
  if type(a:input) != v:t_dict
    return ''
  endif

  if a:name ==# 'Read'
    let l:path = get(a:input, 'file_path', '')
    if !empty(l:path)
      return '`' . l:path . '`'
    endif

  elseif a:name ==# 'Grep'
    let l:pattern = get(a:input, 'pattern', '')
    if !empty(l:pattern)
      return '`/' . l:pattern . '/`'
    endif

  elseif a:name ==# 'Glob'
    let l:pattern = get(a:input, 'pattern', '')
    if !empty(l:pattern)
      return '`' . l:pattern . '`'
    endif

  elseif a:name ==# 'Task'
    let l:desc = get(a:input, 'description', '')
    if !empty(l:desc)
      return l:desc
    endif
  endif

  return ''
endfunction

function! viclaude#grep(pattern) abort
  if empty(a:pattern)
    echohl WarningMsg | echo 'Usage: :ClaudeGrep <pattern>' | echohl None
    return
  endif

  let l:cwd = getcwd()
  let l:project_name = s:project_name(l:cwd)
  let l:project_dir = s:project_dir(l:project_name)

  if !isdirectory(l:project_dir)
    echohl WarningMsg | echo 'No Claude sessions found for this project.' | echohl None
    return
  endif

  let l:files = glob(l:project_dir . '/*.jsonl', 0, 1)
  if empty(l:files)
    echohl WarningMsg | echo 'No Claude sessions found for this project.' | echohl None
    return
  endif

  let l:results = []
  for l:file in l:files
    if !filereadable(l:file)
      continue
    endif
    let l:match = s:grep_session(l:file, a:pattern)
    if !empty(l:match)
      call add(l:results, l:match)
    endif
  endfor

  if empty(l:results)
    echohl WarningMsg | echo 'No matches found for: ' . a:pattern | echohl None
    return
  endif

  " Sort by timestamp descending (most recent first)
  call sort(l:results, {a, b -> a.timestamp ==# b.timestamp ? 0 : a.timestamp ># b.timestamp ? -1 : 1})

  let s:session_files = []
  let s:grep_pattern = a:pattern
  let l:qflist = []
  for l:r in l:results
    call add(s:session_files, l:r.file)
    let l:count_str = l:r.count == 1 ? '1 match' : l:r.count . ' matches'
    call add(l:qflist, {
          \ 'text': '[' . l:r.display_time . '] (' . l:count_str . ') ' . l:r.excerpt,
          \ })
  endfor

  call setqflist(l:qflist)
  copen
  nnoremap <buffer> <silent> <CR> :call viclaude#select_entry()<CR>
endfunction

function! s:grep_session(file, pattern) abort
  let l:raw_lines = readfile(a:file)

  " Quick check: skip files that don't contain the pattern at all
  let l:raw_match = v:false
  for l:rl in l:raw_lines
    if l:rl =~? a:pattern
      let l:raw_match = v:true
      break
    endif
  endfor
  if !l:raw_match
    return {}
  endif

  let l:timestamp = ''
  let l:display_time = ''
  let l:count = 0
  let l:first_excerpt = ''

  for l:raw in l:raw_lines
    try
      let l:obj = json_decode(l:raw)
    catch
      continue
    endtry

    if type(l:obj) != v:t_dict
      continue
    endif

    if get(l:obj, 'isSidechain', v:false)
      continue
    endif

    let l:msg = get(l:obj, 'message', {})
    if empty(l:msg) || type(l:msg) != v:t_dict
      continue
    endif

    let l:role = get(l:msg, 'role', '')
    if l:role !=# 'user' && l:role !=# 'assistant'
      continue
    endif

    " Capture timestamp from first message
    if empty(l:timestamp)
      let l:timestamp = get(l:obj, 'timestamp', '')
      let l:display_time = l:timestamp
      if len(l:timestamp) >= 16
        let l:display_time = l:timestamp[0:9] . ' ' . l:timestamp[11:15]
      endif
    endif

    let l:content = get(l:msg, 'content', '')
    let l:text = s:extract_searchable_text(l:content)

    if l:text =~? a:pattern
      let l:count += 1
      if empty(l:first_excerpt)
        for l:tline in split(l:text, '\n')
          if l:tline =~? a:pattern
            let l:first_excerpt = l:tline
            break
          endif
        endfor
      endif
    endif
  endfor

  if l:count == 0
    return {}
  endif

  if len(l:first_excerpt) > 120
    let l:first_excerpt = l:first_excerpt[0:119] . '...'
  endif

  return {
        \ 'file': a:file,
        \ 'timestamp': l:timestamp,
        \ 'display_time': l:display_time,
        \ 'count': l:count,
        \ 'excerpt': l:first_excerpt,
        \ }
endfunction

function! s:extract_searchable_text(content) abort
  if type(a:content) == v:t_string
    return a:content
  endif
  if type(a:content) == v:t_list
    let l:texts = []
    for l:block in a:content
      if type(l:block) == v:t_dict && get(l:block, 'type', '') ==# 'text'
        call add(l:texts, get(l:block, 'text', ''))
      endif
    endfor
    return join(l:texts, "\n")
  endif
  return ''
endfunction
