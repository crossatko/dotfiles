#!/usr/bin/env bash
# @launcher.title Say hello
# @launcher.subtitle Example: asks for a name, shows a toast
# @launcher.mode toast
# @launcher.argument Name
echo "Hello, ${1:-world}!"
