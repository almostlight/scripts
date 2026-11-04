#!/bin/bash

# Script to gracefully shut down all Proxmox containers and VMs
# /usr/local/bin/pct-shutdown-all.sh

LOG_FILE="/var/log/pct-shutdown.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo > "$LOG_FILE"

# Function to log messages
log_message() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

# Function to shut down containers
shutdown_containers() {
    log_message "Shutting down containers"
    
    CONTAINERS=$(pct list | awk 'NR>1 {print $1}')
    TOTAL_CONTAINERS=$(echo "$CONTAINERS" | wc -w)
    
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    FAILED_IDS=""
    
    for CTID in $CONTAINERS; do
        CT_STATUS=$(pct status $CTID 2>/dev/null | awk '{print $2}')
        CT_NAME=$(pct config $CTID 2>/dev/null | grep ^name | cut -d' ' -f2)
        
        if [ "$CT_STATUS" = "running" ]; then
            log_message "Shutting down container $CTID ($CT_NAME)..."
            
            # Try graceful shutdown with timeout
            if pct shutdown $CTID --timeout 60; then
                log_message "Container $CTID shutdown successful"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                log_message "Container $CTID shutdown failed"
                if pct stop $CTID --skiplock 1; then
                    log_message "Container $CTID force stopped"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                else
                    log_message "Container $CTID failed to stop"
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                    FAILED_IDS="$FAILED_IDS $CTID"
                fi
            fi
        else
            log_message "Container $CTID ($CT_NAME) is not running (status: $CT_STATUS)"
        fi
    done
    
    log_message "Container shutdown completed: $SUCCESS_COUNT successful, $FAIL_COUNT failed"
    if [ -n "$FAILED_IDS" ]; then
        log_message "Failed container IDs:$FAILED_IDS"
    fi
    
    return $FAIL_COUNT
}

# Function to shut down VMs
shutdown_vms() {
    log_message "Shutting down VMs"
    
    VMS=$(qm list | awk 'NR>1 {print $1}')
    TOTAL_VMS=$(echo "$VMS" | wc -w)
    
    if [ "$TOTAL_VMS" -eq 0 ]; then
        log_message "No VMs found"
        return 0
    fi
    
    log_message "Found $TOTAL_VMS VM(s)"
    
    SUCCESS_COUNT=0
    FAIL_COUNT=0
    FAILED_IDS=""
    
    for VMID in $VMS; do
        VM_STATUS=$(qm status $VMID 2>/dev/null | awk '{print $2}')
        VM_NAME=$(qm config $VMID 2>/dev/null | grep ^name | cut -d' ' -f2)
        
        if [ "$VM_STATUS" = "running" ]; then
            log_message "Shutting down VM $VMID ($VM_NAME)..."
            
            # Try graceful shutdown with timeout
            if qm shutdown $VMID --timeout 60; then
                log_message "VM $VMID shutdown successful"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                log_message "VM $VMID shutdown failed"
                if qm stop $VMID --skiplock 1; then
                    log_message "VM $VMID force stopped"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                else
                    log_message "VM $VMID failed to stop"
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                    FAILED_IDS="$FAILED_IDS $VMID"
                fi
            fi
        else
            log_message "VM $VMID ($VM_NAME) is not running (status: $VM_STATUS)"
        fi
    done
    
    log_message "VM shutdown completed: $SUCCESS_COUNT successful, $FAIL_COUNT failed"
    if [ -n "$FAILED_IDS" ]; then
        log_message "Failed VM IDs:$FAILED_IDS"
    fi
    
    return $FAIL_COUNT
}

# Function to wait for all shutdowns to complete
wait_for_shutdown() {
    log_message "Waiting for shutdowns to complete"
    
    local TIMEOUT=300  # 5 minutes total timeout
    local INTERVAL=5
    local ELAPSED=0
    local ALL_STOPPED=false
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        # Check containers
        RUNNING_CONTAINERS=0
        for CTID in $(pct list | awk 'NR>1 && $2=="running" {print $1}'); do
            RUNNING_CONTAINERS=$((RUNNING_CONTAINERS + 1))
        done
        
        # Check VMs
        RUNNING_VMS=0
        for VMID in $(qm list | awk 'NR>1 && $2=="running" {print $1}'); do
            RUNNING_VMS=$((RUNNING_VMS + 1))
        done
        
        if [ $RUNNING_CONTAINERS -eq 0 ] && [ $RUNNING_VMS -eq 0 ]; then
            ALL_STOPPED=true
            break
        fi
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done
    
    if $ALL_STOPPED; then
        log_message "Containers and VMs stopped. Time taken: $ELAPSED seconds"
        return 0
    else
        log_message "Timeout reached. Some instances may still be running"
        log_message "Remaining: $RUNNING_CONTAINERS container(s), $RUNNING_VMS VM(s)"
        return 1
    fi
}

main() {
    log_message "Starting shutdown"
    log_message "Host: $(hostname)"
    log_message "Time: $TIMESTAMP"
    
    if ! command -v pct &> /dev/null || ! command -v qm &> /dev/null; then
        log_message "ERROR: Not a Proxmox node or commands not found"
        exit 1
    fi
    
    shutdown_containers
    CONTAINER_RESULT=$?
    
    shutdown_vms
    VM_RESULT=$?
    
    wait_for_shutdown
    WAIT_RESULT=$?
    
    log_message "Summary"
    log_message "Container shutdowns: $( [ $CONTAINER_RESULT -eq 0 ] && echo "All successful" || echo "$CONTAINER_RESULT failures" )"
    log_message "VM shutdowns: $( [ $VM_RESULT -eq 0 ] && echo "All successful" || echo "$VM_RESULT failures" )"
    log_message "Final status: $( [ $WAIT_RESULT -eq 0 ] && echo "All stopped" || echo "Some instances still running" )"
    
    TOTAL_FAILURES=$((CONTAINER_RESULT + VM_RESULT))
    if [ $TOTAL_FAILURES -eq 0 ] && [ $WAIT_RESULT -eq 0 ]; then
        log_message "All containers and VMs shutdown successfully"
        exit 0
    else
        log_message "Shutdown completed with issues"
        exit 1
    fi
}

main
