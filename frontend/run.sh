#!/bin/bash
cd "$(dirname "$0")"
export RACK_ENV=production
exec /usr/bin/bundle exec rackup -p 8081
