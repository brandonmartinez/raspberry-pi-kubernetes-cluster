#!/usr/bin/env bash

set -o allexport
source ./.env
source ./src/_shared/echo.sh
set +o allexport

# Set Session Name
SESSION="rpicluster"
SESSIONEXISTS=$(tmux list-sessions | grep $SESSION)

section "TMUX Configuration Script"

# Only create tmux session if it doesn't already exist
if [ "$SESSIONEXISTS" = "" ]
then
    section "Getting Remote k3s Manifest"
    scp pi@$CLUSTER_HOSTNETWORKINGIPADDRESS:/etc/rancher/k3s/k3s.yaml kubeconfig.yml > /dev/null
    sed -i '' "s/127.0.0.1/$CLUSTER_HOSTNETWORKINGIPADDRESS/g" kubeconfig.yml
    chmod 600 "$KUBECONFIG"
    
    section "Configuring TMUX session for $SESSION"
    
    log "Creating new tmux session $SESSION"
    # Start New Session with our name
    tmux new-session -d -s $SESSION
    
    log "Creating window for local access"
    tmux rename-window -t $SESSION Shell
    tmux send-keys -t $SESSION:Shell "cd '$(PWD)'" C-m "export KUBECONFIG=\"$(pwd)/kubeconfig.yml\"" C-m "clear" C-m "kubectl get namespaces" C-m
    
    # Create a Window for Cluster
    tmux new-window -t $SESSION -n $CLUSTER_HOSTNAME -c "$(PWD)"
    tmux send-keys -t $SESSION:$CLUSTER_HOSTNAME "ssh pi@$CLUSTER_HOSTNETWORKINGIPADDRESS" C-m

    # TODO: add additional nodes and create windows for them

    # Select First Window
    tmux select-window -t $SESSION:Shell
fi

# Attach Session, on the Main window
section "Attaching to tmux session $SESSION"
sleep 5
tmux attach-session -t $SESSION
