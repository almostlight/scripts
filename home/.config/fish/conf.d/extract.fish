function extract
    switch $argv[1]
        case '*.tar.gz' '*.tgz'
            tar xzf $argv[1]
        case '*.tar.bz2'
            tar xjf $argv[1]
        case '*.tar.xz'
            tar xJf $argv[1]
        case '*.zip'
            unzip $argv[1]
        case '*'
            echo "Unknown archive format"
            return 1
    end
end

