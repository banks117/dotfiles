# Personal preferences

## Comments

If the code is clear, don't comment it — often the right number of lines is zero.
When a comment does help, keep it brief: a line or two saying *why* (the
constraint, the tradeoff, the thing that bites), not *what*. Restating the code
earns nothing. The test: would a reader who never saw this diff need this? If it
only justifies the change just made, it belongs in the PR body, not the source.
Covers all code comments, migrations and tests included. Trim over-long ones when
already editing that code, not on sight. Design docs may carry longer context.

## Git

- When I ask you to commit, push the branch too — don't stop and ask. A commit
  instruction covers the push. I work on PR branches, so an unpushed commit
  hasn't reached the thing I'm actually looking at. Report the pushed ref range.
- This is about the push, not about whether to commit: still only commit when
  asked, and still branch first if somehow on the default branch.

## Shell Tools

When using bash, use `rg` instead of `grep` and `fd` instead of `find`.
