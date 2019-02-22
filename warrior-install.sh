#!/bin/bash

PIP=pip

if type pip3 > /dev/null 2>&1
then
  PIP=pip3
fi

echo "Installing warcio"
if ! sudo $PIP install warcio --upgrade
then
  exit 1
fi

exit 0

