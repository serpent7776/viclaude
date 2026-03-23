if exists('b:current_syntax')
  finish
endif

runtime! syntax/markdown.vim
unlet! b:current_syntax

" Blockquote lines (user messages) with distinct background
syntax match viclaudeBlockquote /^>.*$/ contains=@Spell
highlight viclaudeBlockquote ctermbg=236 guibg=#303030

let b:current_syntax = 'viclaude_discussion'
