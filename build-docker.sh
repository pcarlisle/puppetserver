#!/bin/sh

set -e

agent_version="$(grep puppet_build_version acceptance/config/beaker/options.rb | cut -d\" -f2)"

docker build -f docker/puppet-agent-alpine/Dockerfile "https://github.com/pcarlisle/puppet-agent.git#${agent_version}" -t puppet-agent:local

docker build . -t puppetserver:local
