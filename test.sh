#!/usr/bin/env bash
rm -rf test
#./mktest.sh
mkdir -p test/apps
PREFIX=test/usr/local CONF_PREFIX=test SHORTCUT_PREFIX=test/apps/ NOPKG=1 NOBUS=1 NOSVC=1 ./argon1.sh
