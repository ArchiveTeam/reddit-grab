#!/bin/bash

echo "Installing lua-utf8..."
sudo luarocks install utf8 || exit 1

exit 0
