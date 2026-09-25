---
name: ripgrep
description: Search codebases quickly and safely with ripgrep before editing, debugging, or reviewing code.
---

# Search with ripgrep

Use rg as the default tool for finding files, definitions, call sites,
configuration, and error messages. Search first, then edit the smallest set of
files that explains the real flow.

## Core commands

    # List candidate files
    rg --files
    rg --files -g '*.nix' -g '!result/**'

    # Search text with line numbers
    rg -n 'pattern' path/
    rg -n -i 'deprecated|obsolete' .

    # Find definitions and every caller
    rg -n 'function_name|function_name\(' .

    # Search exact text rather than a regular expression
    rg -n -F 'literal text' .

    # Show only matching file names or count matches
    rg -l 'pattern' .
    rg -c 'pattern' .

## Narrow the search

- Use -g '*.rs', -g '*.nix', or --type rust for file types.
- Exclude generated or dependency trees with -g '!node_modules/**',
  -g '!result/**', or -g '!.git/**'.
- Use --hidden only when hidden files are relevant; keep .git excluded.
- Use -F for user-provided text and -i when case should not matter.
- Pipe a broad result to head when only a sample is needed.

## Investigation workflow

1. Start with rg --files to understand the repository layout.
2. Search the exact error, symbol, option, or path.
3. Search all callers before changing a shared function or module.
4. Search related tests and configuration separately.
5. Prefer a narrower second search over a large unreadable result.

Avoid replacing rg with grep -R or find | grep unless a command specifically
requires their behavior.
