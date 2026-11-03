# Tasks and worktrees

I run each task in its own herdr tab, inside one space per repo (b2b, play, bkr, patterns, or "other"). Branch work gets its own git worktree with its own DDEV site. `task`, `wt-open` and `wt-done` come from ~/dotfiles/zsh/worktrees.zsh.

When I start a task that needs its own branch (a feature, a fix, anything headed for a PR) and this checkout is busy with something else, suggest a worktree once before making changes. Busy means it's on another task's branch, or it has uncommitted changes that aren't part of the new task. Give the command ready to paste, with a branch name that follows the repo's conventions (the part after the last slash names the tab and folder):

```
task <branch> <b2b|play|bkr|patterns> wt
```

It opens a new tab with its own Claude, so tell me to give the task to that Claude; you can't move this session there. If I say yes, you may run `task` yourself: it returns in seconds, and DDEV setup runs in the new tab's shell.

Don't suggest one for questions, reviews, quick edits that belong to the current branch, or when I've already said to work here. Never create a worktree or switch branches without asking.
