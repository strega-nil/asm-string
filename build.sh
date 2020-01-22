#! /bin/bash
set -e

nasm -f elf64 -g -F dwarf string.s
clang -c -g test.c
clang -o test -g -static test.o string.o

rm test.o string.o
