# Worktrees

I run one task per git worktree, each in its own herdr space with its own DDEV site. `wt-new`, `wt-open` and `wt-done` come from ~/dotfiles/zsh/worktrees.zsh.

When I start a task that needs its own branch (a feature, a fix, anything headed for a PR) and this checkout is busy with something else, suggest a worktree once before making changes. Busy means it's on another task's branch, or it has uncommitted changes that aren't part of the new task. Give the command ready to paste, with a short task name and a branch name that follows the repo's conventions:

```
wt-new <task> <branch>
```

Then tell me to start Claude in the new space; you can't move this session there. If I say yes, you may run `wt-new` yourself: it takes a few minutes and starts DDEV and copies the database.

Don't suggest one for questions, reviews, quick edits that belong to the current branch, or when I've already said to work here. Never create a worktree or switch branches without asking.
