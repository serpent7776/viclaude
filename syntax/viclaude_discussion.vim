if exists('b:current_syntax')
  finish
endif

let g:markdown_fenced_languages = ['sh', 'bash', 'python']
runtime! syntax/markdown.vim
unlet! b:current_syntax

" Fix: markdown's BoldItalic rules misparse **_foo** as start of bold-italic
" region that never closes, causing highlight bleed. Clear and suppress them.
silent! syntax clear markdownBoldItalic
silent! syntax clear markdownBoldUnderlineItalic

" Blockquote lines (user messages) with distinct background
syntax match viclaudeBlockquote /^>.*$/ contains=@Spell
highlight viclaudeBlockquote ctermfg=cyan ctermbg=236 guifg=#00ffff guibg=#303030

" Noise lines (local command artifacts, system reminders)
syntax match viclaudeNoise /^<.*$/ contains=@Spell
highlight viclaudeNoise ctermfg=243 guifg=#767676

" Thinking lines (extended thinking output)
syntax match viclaudeThinking /^\~.*$/ contains=@Spell
highlight viclaudeThinking ctermfg=243 guifg=#767676

let b:current_syntax = 'viclaude_discussion'
