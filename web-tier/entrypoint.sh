#!/bin/sh
set -e
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf
exec nginx -g 'daemon off;'