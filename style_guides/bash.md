# Bash Coding Style

## Shell

-   Use Bash with `#!/usr/bin/env bash`.
-   Use `set -euo pipefail`.
-   Write scripts for Bash, not POSIX `sh`.

## Indentation

-   Use tabs for indentation.
-   Never use spaces for indentation.
-   Use one tab per indentation level.

## Naming

-   Use `SCREAMING_SNAKE_CASE` for script-wide variables and
    configuration values.
-   Use descriptive names.
-   Avoid unnecessary abbreviations.

## Variables

-   Quote variable expansions.
-   Prefer `"${VARIABLE}"`.
-   Define important configuration values near the beginning of the
    script.

## Conditionals

-   Use `[[ ... ]]` for Bash conditionals.
-   Check prerequisites and required privileges early.
-   Prefer explicit checks over relying on later command failures.

## Commands

-   Prefer long options when they improve readability.
-   Use `--` where appropriate for variable-derived paths.
-   Use `$(...)` for command substitution.
-   Prefer `apt-get` over `apt` in scripts.
-   Use `install` when ownership or permissions are part of a file
    operation.

## Multi-line Commands

-   Use `\` for command continuation.
-   Put long options and arguments on separate lines when this improves
    readability.
-   Keep continuation indentation consistent.

## Error Handling

-   Send error messages to `stderr`.
-   Exit explicitly when a required condition is not met.
-   Do not suppress command failures without a clear reason.

## Functions

-   Use functions for reusable operations, cleanup, or meaningful
    logical sections.
-   Use lowercase `snake_case` for function names.
-   Avoid unnecessary abstraction.

## Temporary Resources

-   Use `mktemp` for temporary files and directories.
-   Clean temporary resources with `trap`.

## Idempotence

-   Scripts should be safe to run repeatedly whenever practical.
-   Check whether users, files, directories, packages, services, and
    configuration already exist before modifying them.
-   Avoid creating duplicate configuration.

## Output

-   Use concise progress messages for major operations.
-   Use `==>` as the standard prefix for major progress messages.
-   Keep normal output useful and limited.

## Formatting

-   Separate logical sections with blank lines.
-   Prefer clarity and consistency over compactness.
-   Comments should explain why something is done, not restate the code.

## ShellCheck

-   Scripts should pass ShellCheck.
-   Avoid suppressing warnings unless there is a specific reason.

## General Principles

-   Prefer explicit, readable code over clever code.
-   Keep execution flow easy to follow from top to bottom.
-   Minimize unnecessary dependencies.
-   Fail early when prerequisites are missing.
-   Favor predictable and maintainable behavior.

