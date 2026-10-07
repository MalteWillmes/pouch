#!/bin/sh
# Stamp a new version into the app so open phones update themselves, then commit and push.
# Usage: ./publish.sh "commit message"
set -e
v=$(date -u +%Y%m%d%H%M%S)
sed -i "s/const APP_VERSION = \"[^\"]*\"/const APP_VERSION = \"$v\"/; s/categories.js?v=[^\"]*\"/categories.js?v=$v\"/" index.html
echo "$v" > version.txt
git add -A
git commit -q -m "$1"
git push -q
echo "published $v"
