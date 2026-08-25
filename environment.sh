#!/bin/bash

# a bash script to source in order to set up your command line to in order
# to work with the t11 IOCs and Services.

# check we are sourced
if [ "$0" = "$BASH_SOURCE" ]; then
    echo "ERROR: Please source this script"
    exit 1
fi

echo "Loading environment for t11 deployment ..."

#### SECTION 1. Environment variables ##########################################

export EC_CLI_BACKEND="ARGOCD"
# the argocd project and root app
export EC_TARGET=t11-beamline/t11
# the git repo for this project
export EC_SERVICES_REPO=https://github.com/epics-containers/t11-services
# declare your centralised log server Web UI
export EC_LOG_URL='https://graylog2.diamond.ac.uk/search?rangetype=relative&fields=message%2Csource&width=1489&highlightMessage=&relative=172800&q=pod_name%3A{service_name}*'

#### SECTION 2. Install ec #####################################################

# check if epics-containers-cli (ec command) is installed
if ! ec --version &> /dev/null; then
    echo "ERROR: Please set up a virtual environment and: 'pip install edge-containers-cli'"
    return 1
fi

# enable shell completion for ec commands
source <(ec --show-completion ${SHELL})

#### SECTION 3. Configure Argocd Server ###################################

# TODO add commands here to enable argocd cli
argocd login argocd.diamond.ac.uk --grpc-web --sso

# enable shell completion for k8s tools
if [ -n "$ZSH_VERSION" ]; then SHELL=zsh; fi
source <(argocd completion $(basename ${SHELL}))

