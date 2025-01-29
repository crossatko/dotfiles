#!/bin/bash

response=$(curl -s https://wttr.in/Olomouc?format=1)
remove_spaces=${response// /}

echo "{\"text\": \"$remove_spaces\"}"
