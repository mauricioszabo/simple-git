# Simple GIT

A simple package to be able to drive GIT.

## Motivation

I use GIT from terminal, like most of the people I work with. One of the things I __really__ miss from GIT is the ability to compare diffs, and to simply commit my file. As for the other things - stage and unstage files, amend commits, rebase, pull, these are things I can live with the command line.

So, I've created a bunch of scripts on my ATOM Init script to simply commit files. Then to add. Then to create a diff view... and now, integrated everything into a package.

![A screenshot of your package](https://gitlab.com/mauricioszabo/simple-git/-/raw/master/doc/fragment.gif)

## What does this package do?

* Protects push and commit to master (configurable)
* Quick-commit - add and commit a single file (with a diff view to show what you're commiting)
* Add files
* Commit files (with a diff view to show what you're commiting)
* Revert current file
* Create new branch from current
* Checkout to master, and pull
* Show diffs in project (see above)
* Show blame (see below)

## Ideas to the future

* Add a kind of "diff layer" in the current editor
* Selective stage parts of your code
* Safe rebase, or something to help with changing history
* Integrations - when we have a commit hash in blame, we should be able to view that commit, and other things
