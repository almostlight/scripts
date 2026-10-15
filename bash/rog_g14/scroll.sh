#! /bin/bash 

echo "Enter message: " && read TEXT

cd ~/AniMeScroller/
./generate_gif.py -t "$TEXT" -o scroll.gif 
asusctl anime gif -p ./scroll.gif -a 0.64 -l 0  

function handler(){
    echo "handling SIGINT"
    asusctl anime -c
}
# Assign the handler function to the SIGINT signal
trap handler SIGINT 
watch ls -l

