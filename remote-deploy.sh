#!/bin/bash
#
# This script runs on the net-metrics host in a checkout of the repo.
#
# It is responsible for performing a 'deploy'. At this point that basically
# consists of restarting some daemons.
#
set -ex

(
    cd collector
    bundle --local
)

(
    cd frontend
    bundle --local --without development
)

systemctl daemon-reload
systemctl restart net-metrics-collector.service
systemctl restart net-metrics-frontend.service
