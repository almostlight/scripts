# Bash-like history expansion
source ~/.config/fish/config.d/*
# fish config
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
abbr -a cp 'cp -i'
abbr -a mv 'mv -i'
alias c='clear'
alias sizeof="du -cksh"
alias update-grub="sudo grub2-mkconfig -o /boot/grub2/grub.cfg"


