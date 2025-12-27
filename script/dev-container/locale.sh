#!/bin/sh
#
# Ensure interactive shells (including SSH logins) inherit the UTF-8 locale
# and RuboCop cache defaults the container was built with.

: "${LANG:=C.UTF-8}"
: "${LANGUAGE:=C.UTF-8}"
: "${LC_ALL:=C.UTF-8}"
: "${RUBOCOP_CACHE_ROOT:=/work/tmp}"

export LANG LANGUAGE LC_ALL RUBOCOP_CACHE_ROOT
