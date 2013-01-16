#!/bin/bash

push=true

help()
{
    cat <<HELP

usage: ./build
usage: ./build --no-push

Flags:
    -n (--no-push)  Don't push to rubygems.org

HELP
    exit 0
}

# From http://mywiki.wooledge.org/BashFAQ/035.
while :
do
  case $1 in
    -h | --help | -\?)
        help
        exit 0      # This is not an error, User asked help. Don't do "exit 1"
        ;;
    -n | --no-push)
        push=false
        break
        ;;
    -*)
        echo "WARN: Unknown option (ignored): $1" >&2
        shift
        ;;
    *)  # no more options. Stop while loop
        break
        ;;
  esac
done

rm capistrano-demonz-*.gem
gem build capistrano-demonz.gemspec
VERSION=`ls capistrano-demonz-*.gem | sed 's/[^0-9.]*\([0-9.]*\).*/\1/'`
VERSION=${VERSION%?}
gem install "capistrano-demonz-$VERSION.gem"
if [[ $push == true ]]; then
  gem push "capistrano-demonz-$VERSION.gem"
fi
