#!/bin/bash

# single file test
echo "Running single file test"
./indexer.pl test_data/Moby\ Dick\ Or\ The\ Whale\ by\ Herman\ Melville 2>/dev/null

# multifile test
echo
echo "Running full directory test"
./indexer.pl test_data/* 2>/dev/null

#timeout test - kill subprocesses
echo
echo "Running timeout test (timeout of 1 sec)"
./indexer.pl -t 1 test_data/* 2>/dev/null

# stream test
echo
echo "Running text blob test (stdin stream)"
cat test_data/Moby\ Dick\ Or\ The\ Whale\ by\ Herman\ Melville | ./indexer.pl -b 2>/dev/null
