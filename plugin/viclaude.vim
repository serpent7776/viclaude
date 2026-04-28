" viclaude.vim - Browse Claude Code conversation history
" Maintainer: viclaude
" License: MIT

if exists('g:loaded_viclaude')
  finish
endif
let g:loaded_viclaude = 1

command! ClaudeHistory call viclaude#history()
command! -nargs=+ ClaudeGrep call viclaude#grep(<q-args>)
