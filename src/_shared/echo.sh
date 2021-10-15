#!/usr/bin/env bash

YELLOW='\033[1;33m'
GRAY='\033[1;30m'
NC='\033[0m'

function section () {
    echo -e "\n${YELLOW}**************************************************${NC}"
    echo -e $1
    echo -e "${YELLOW}**************************************************${NC}\n"
}

function log () {
    echo -e "${NC}$1${GRAY}"
}
