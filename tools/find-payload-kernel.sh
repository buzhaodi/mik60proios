#!/bin/bash
P=/home/yang/unixnu-work/UniXNU/out/socrates/payload
echo "=== payload dir:"
ls "$P"
echo "=== find kernel.macho under it:"
find "$P" -name "kernel.macho" 2>/dev/null | head -5
echo "=== any Payloads dirs:"
find "$P" -type d -name "Payloads" 2>/dev/null | head -3
