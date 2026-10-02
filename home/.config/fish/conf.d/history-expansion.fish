function __history_expand
    set -l cmd (commandline)
    set -l prev (history | head -n 1)
    set -l args (string split ' ' -- $prev)

    set cmd (string replace --all '!!' "$prev" "$cmd")

    if test (count $args) -gt 1
        set cmd (string replace --all '!$' "$args[-1]" "$cmd")
        set cmd (string replace --all '!^' "$args[2]" "$cmd")
        set cmd (string replace --all '!*' (string join ' ' $args[2..-1]) "$cmd")
    end

    commandline "$cmd"
    commandline -f execute
end

bind \r __history_expand
