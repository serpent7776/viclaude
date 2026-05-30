" autoload/viclaude.vim - Claude Code conversation history browser

let s:grep_pattern = ''

function! s:warn(msg) abort
  echohl WarningMsg | echo a:msg | echohl None
endfunction

function! s:err(msg) abort
  echohl ErrorMsg | echo a:msg | echohl None
endfunction

function! s:by_timestamp_desc(a, b) abort
  return a:a.timestamp <# a:b.timestamp ? 1 : a:a.timestamp ># a:b.timestamp ? -1 : 0
endfunction

" Claude Code uses leading dash + slashes/dots replaced with dashes
function! s:project_dir(cwd) abort
  return expand('~/.claude/projects/' . substitute(a:cwd, '[/.]', '-', 'g'))
endfunction

" Resolve the git repo root for cwd; fall back to cwd if not a repo.
function! s:repo_root(cwd) abort
  let l:out = systemlist('git -C ' . shellescape(a:cwd) . ' rev-parse --show-toplevel')
  if v:shell_error == 0 && !empty(l:out)
    return l:out[0]
  endif
  return a:cwd
endfunction

function! s:list_sessions(project_dir) abort
  return filter(glob(a:project_dir . '/*.jsonl', 0, 1), 'filereadable(v:val)')
endfunction

function! s:get_session_files() abort
  let l:project_dir = s:project_dir(s:repo_root(getcwd()))
  if !isdirectory(l:project_dir)
    call s:warn('No Claude sessions found for this project.')
    return []
  endif
  let l:files = s:list_sessions(l:project_dir)
  if empty(l:files)
    call s:warn('No Claude sessions found for this project.')
  endif
  return l:files
endfunction

function! s:open_qflist(qflist) abort
  call setqflist(a:qflist)
  copen
endfunction

function! s:current_qf_data() abort
  let l:items = getqflist()
  let l:idx = line('.') - 1
  if l:idx < 0 || l:idx >= len(l:items)
    return {}
  endif
  let l:data = get(l:items[l:idx], 'user_data', '')
  return type(l:data) == v:t_dict ? l:data : {}
endfunction

function! s:open_in_code_window(reuse_cmd, split_cmd) abort
  wincmd p
  if line('$') == 1 && getline(1) ==# '' && !&modified && bufname('%') ==# ''
    execute a:reuse_cmd
  else
    execute a:split_cmd
  endif
endfunction

function! viclaude#history() abort
  let s:grep_pattern = ''
  let l:files = s:get_session_files()
  if empty(l:files)
    return
  endif

  let l:entries = []
  for l:file in l:files
    let l:info = s:extract_session_info(l:file)
    if !empty(l:info)
      call add(l:entries, l:info)
    endif
  endfor

  if empty(l:entries)
    call s:warn('No Claude sessions found for this project.')
    return
  endif

  " Sort by timestamp descending (most recent first)
  call sort(l:entries, function('s:by_timestamp_desc'))

  let l:qflist = []
  for l:entry in l:entries
    call add(l:qflist, {
          \ 'text': '[' . l:entry.display_time . '] ' . l:entry.summary,
          \ 'user_data': {'file': l:entry.file, 'match_idx': 0},
          \ })
  endfor

  call s:open_qflist(l:qflist)
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

let s:noise_tags = ['local-command-caveat', 'command-name', 'command-message',
      \ 'command-args', 'local-command-stdout', 'system-reminder']

function! s:clean_user_text(text) abort
  let l:text = a:text
  " Remove known noise XML elements (tag + content)
  for l:tag in s:noise_tags
    let l:text = substitute(l:text, '<' . l:tag . '>\_.\{-}<\/' . l:tag . '>', '', 'g')
  endfor
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
  let l:data = s:current_qf_data()
  if !has_key(l:data, 'file')
    call s:err('Invalid session entry.')
    return
  endif

  let l:file = l:data.file
  let l:match_idx = get(l:data, 'match_idx', 0)
  if !filereadable(l:file)
    call s:err('Session file not readable: ' . l:file)
    return
  endif

  let l:uuid = fnamemodify(l:file, ':t:r')

  call s:open_in_code_window('enew', 'new')

  " Set scratch buffer options
  setlocal buftype=nofile bufhidden=wipe noswapfile
  silent! execute 'file Claude:' . l:uuid

  " Render conversation
  let l:rendered = s:render_session(l:file)
  call setline(1, l:rendered)

  setlocal filetype=viclaude_discussion
  setlocal foldmethod=expr
  execute 'setlocal foldexpr=<SID>thinking_foldexpr(v:lnum)'
  execute 'setlocal foldtext=<SID>thinking_foldtext()'
  setlocal foldlevel=0
  setlocal nomodifiable

  " Section navigation: jump between user prompts
  nnoremap <buffer> <silent> ]] :<C-u>call <SID>jump_prompt(1)<CR>
  nnoremap <buffer> <silent> [[ :<C-u>call <SID>jump_prompt(0)<CR>

  " Go to top, then jump to the requested grep match if applicable
  normal! gg
  if !empty(s:grep_pattern)
    let @/ = '\c' . s:grep_pattern
    set hlsearch
    let l:jumps = l:match_idx > 0 ? l:match_idx : 1
    for l:i in range(l:jumps)
      silent! normal! n
    endfor
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

" Append a fenced block; spill to tempfile when threshold>0 and exceeded.
function! s:emit_block(output, lines, fence, threshold) abort
  if a:threshold > 0 && len(a:lines) > a:threshold
    let l:tmpfile = tempname()
    call writefile(a:lines, l:tmpfile)
    call add(a:output, '... (' . len(a:lines) . ' lines) ' . l:tmpfile)
  else
    call add(a:output, '```' . a:fence)
    call extend(a:output, a:lines)
    call add(a:output, '```')
  endif
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
        call s:emit_block(a:output, split(l:result_text, '\n'), '', 40)
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
        call add(a:output, '`[Tool: Bash]`')
        if !empty(l:cmd)
          call s:emit_block(a:output, split(l:cmd, '\n'), 'bash', 0)
        endif
      elseif l:name ==# 'Write'
        let l:path = get(l:input, 'file_path', '')
        let l:wcontent = get(l:input, 'content', '')
        call add(a:output, '`[Tool: Write]` `' . l:path . '`')
        if !empty(l:wcontent)
          call s:emit_block(a:output, split(l:wcontent, '\n'), '', 0)
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
          call s:emit_block(a:output, l:diff_lines, 'diff', 0)
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
    call s:warn('Usage: :ClaudeGrep <pattern>')
    return
  endif

  let l:files = s:get_session_files()
  if empty(l:files)
    return
  endif

  let l:results = []
  for l:file in l:files
    let l:match = s:grep_session(l:file, a:pattern)
    if !empty(l:match)
      call add(l:results, l:match)
    endif
  endfor

  if empty(l:results)
    call s:warn('No matches found for: ' . a:pattern)
    return
  endif

  " Sort by timestamp descending (most recent first)
  call sort(l:results, function('s:by_timestamp_desc'))

  let s:grep_pattern = a:pattern
  let l:qflist = []
  for l:r in l:results
    let l:idx = 0
    for l:excerpt in l:r.excerpts
      let l:idx += 1
      call add(l:qflist, {
            \ 'text': '[' . l:r.display_time . '] ' . l:excerpt,
            \ 'user_data': {'file': l:r.file, 'match_idx': l:idx},
            \ })
    endfor
  endfor

  call s:open_qflist(l:qflist)
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
  let l:excerpts = []

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

    for l:tline in split(l:text, '\n')
      if l:tline =~? a:pattern
        call add(l:excerpts, s:trim_excerpt(l:tline, a:pattern, 120))
      endif
    endfor
  endfor

  if empty(l:excerpts)
    return {}
  endif

  return {
        \ 'file': a:file,
        \ 'timestamp': l:timestamp,
        \ 'display_time': l:display_time,
        \ 'excerpts': l:excerpts,
        \ }
endfunction

function! s:trim_excerpt(line, pattern, max_len) abort
  let l:total = strchars(a:line)
  if l:total <= a:max_len
    return a:line
  endif
  let l:bpos = match(a:line, '\c' . a:pattern)
  if l:bpos < 0
    return strcharpart(a:line, 0, a:max_len) . '...'
  endif
  let l:pos = strchars(strpart(a:line, 0, l:bpos))
  let l:context_before = 30
  let l:start = l:pos - l:context_before
  if l:start < 0
    let l:start = 0
  endif
  let l:end = l:start + a:max_len
  if l:end > l:total
    let l:end = l:total
    let l:start = l:end - a:max_len
    if l:start < 0
      let l:start = 0
    endif
  endif
  let l:excerpt = strcharpart(a:line, l:start, l:end - l:start)
  if l:start > 0
    let l:excerpt = '...' . l:excerpt
  endif
  if l:end < l:total
    let l:excerpt = l:excerpt . '...'
  endif
  return l:excerpt
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

function! s:memory_dir(cwd) abort
  return s:project_dir(a:cwd) . '/memory'
endfunction

function! s:by_type_name(a, b) abort
  if a:a.type !=# a:b.type
    return a:a.type <# a:b.type ? -1 : 1
  endif
  if a:a.name !=# a:b.name
    return a:a.name <# a:b.name ? -1 : 1
  endif
  return 0
endfunction

function! s:extract_memory_info(file) abort
  let l:info = {
        \ 'file': a:file,
        \ 'name': fnamemodify(a:file, ':t:r'),
        \ 'description': '',
        \ 'type': '',
        \ }

  let l:lines = readfile(a:file, '', 50)
  if empty(l:lines) || l:lines[0] !=# '---'
    return l:info
  endif

  let l:i = 1
  while l:i < len(l:lines) && l:lines[l:i] !=# '---'
    let l:m = matchlist(l:lines[l:i], '^\(\w\+\):\s*\(.*\)$')
    if !empty(l:m)
      let l:key = l:m[1]
      let l:val = l:m[2]
      if l:key ==# 'name'
        let l:info.name = l:val
      elseif l:key ==# 'description'
        let l:info.description = l:val
      elseif l:key ==# 'type'
        let l:info.type = l:val
      endif
    endif
    let l:i += 1
  endwhile

  return l:info
endfunction

function! s:list_memories(memory_dir) abort
  return filter(glob(a:memory_dir . '/*.md', 0, 1), 'filereadable(v:val)')
endfunction

function! viclaude#memory() abort
  let l:memory_dir = s:memory_dir(s:repo_root(getcwd()))
  let l:files = isdirectory(l:memory_dir) ? s:list_memories(l:memory_dir) : []
  if empty(l:files)
    call s:warn('No Claude memories found for this project.')
    return
  endif

  let l:index_file = l:memory_dir . '/MEMORY.md'
  let l:entries = []
  for l:file in l:files
    if l:file ==# l:index_file
      continue
    endif
    call add(l:entries, s:extract_memory_info(l:file))
  endfor

  call sort(l:entries, function('s:by_type_name'))

  let l:qflist = []
  if filereadable(l:index_file)
    call add(l:qflist, {
          \ 'text': '[index] MEMORY.md',
          \ 'user_data': {'file': l:index_file},
          \ })
  endif

  for l:e in l:entries
    let l:label = '[' . (empty(l:e.type) ? '?' : l:e.type) . '] ' . l:e.name
    if !empty(l:e.description)
      let l:label = l:label . ' — ' . l:e.description
    endif
    call add(l:qflist, {
          \ 'text': l:label,
          \ 'user_data': {'file': l:e.file},
          \ })
  endfor

  call s:open_qflist(l:qflist)
  nnoremap <buffer> <silent> <CR> :call viclaude#select_memory()<CR>
endfunction

function! viclaude#select_memory() abort
  let l:data = s:current_qf_data()
  if !has_key(l:data, 'file')
    call s:err('Invalid memory entry.')
    return
  endif

  let l:file = l:data.file
  if !filereadable(l:file)
    call s:err('Memory file not readable: ' . l:file)
    return
  endif

  call s:open_in_code_window('edit ' . fnameescape(l:file), 'new ' . fnameescape(l:file))
endfunction
