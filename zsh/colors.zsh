# Shell colors: colored ls, a prompt with folder + git branch, and syntax
# highlighting. Uses named ANSI colors so the Ghostty theme picks the shades.

# ls: color folders, executables, symlinks.
export CLICOLOR=1

# Prompt: folder (blue), git branch (magenta), then ❯ — green, or red if the
# last command failed. A blank line before each prompt separates commands.
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats ' %F{magenta}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{magenta}%b%f %F{yellow}(%a)%f'
precmd() { vcs_info; print }
setopt prompt_subst
PROMPT='%F{blue}%B%~%b%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})❯%f '

# Syntax highlighting while typing; must be sourced last.
ZSH_HL="$(brew --prefix 2>/dev/null)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[ -f "$ZSH_HL" ] && source "$ZSH_HL"
unset ZSH_HL
