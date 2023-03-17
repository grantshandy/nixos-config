#!/bin/bash

DATE_FORMATTED=$(date "+%a %d/%m %I:%M %p")
MEMORY_USAGE="mem: $(free -m | grep Mem | awk '{print ($3/$2)*100}' | grep -o '^[0-9]*\.[0-9][0-9]')%"
CPU_USAGE="cpu: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')"

echo $CPU_USAGE \| $MEMORY_USAGE \| $DATE_FORMATTED
