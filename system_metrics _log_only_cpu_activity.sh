#!/bin/bash

# Variables
LOG_FILE="/home/RUS_CIP/st179664/Function_Offloading/system_metrics/system_metrics_3.log"
INTERVAL=5  # Interval in seconds
DURATION=60  # Duration in seconds
END_TIME=$((SECONDS + DURATION))

# Ensure log file is writable
touch $LOG_FILE
chmod 644 $LOG_FILE

# Print the header
echo "Timestamp,CPU_User,CPU_System,CPU_Idle,CPU_IOWait,Mem_Free_GB,Mem_Used_GB,Num_Processes,CPU_Frequency,Avg_Process_Size_KB,Power_Consumption,CPU_Utilization,GPU_Utilization" > $LOG_FILE

# Initialize previous process count
PREV_PROCESS_COUNT=$(ps --no-headers -e | wc -l)
PREV_TIMESTAMP=$(date +%s)

# Function to get average process size
get_avg_process_size() {
  ps --no-headers -eo rss | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; else print 0 }'
}

# Function to read power consumption from sysfs
get_power_consumption() {
  if [ -d /sys/class/powercap/intel-rapl ]; then
    ENERGY_UJ_BEFORE=$(cat /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj)
    sleep 1
    ENERGY_UJ_AFTER=$(cat /sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj)
    ENERGY_UJ=$(echo "$ENERGY_UJ_AFTER - $ENERGY_UJ_BEFORE" | bc)
    POWER_W=$(echo "scale=2; $ENERGY_UJ / 1000000" | bc)
    echo $POWER_W
  else
    echo "N/A"
  fi
}

# Function to get CPU utilization for each core
get_cpu_utilization() {
  mpstat -P ALL 1 1 | awk '/Average/ && $2 ~ /[0-9]/ {printf "CPU%s: %.2f%% ", $2, 100 - $12}'
}

# Function to get GPU utilization
get_gpu_utilization() {
  nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | paste -sd "," -
}

# Function to check if there is CPU activity
is_cpu_active() {
  mpstat -P ALL 1 1 | awk '/Average/ && $2 ~ /[0-9]/ {if ($3 > 0 || $4 > 0 || $6 > 0) {exit 0}}; END {exit 1}'
}

# Function to log system metrics
log_system_metrics() {
  if is_cpu_active; then
    echo "CPU is active. Logging metrics..."  # Debug output
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    CURRENT_TIMESTAMP=$(date +%s)
    
    # Memory and CPU metrics using vmstat
    VMSTAT=$(vmstat 1 2 | tail -1)
    CPU_USER=$(echo $VMSTAT | awk '{print $13}')
    CPU_SYSTEM=$(echo $VMSTAT | awk '{print $14}')
    CPU_IDLE=$(echo $VMSTAT | awk '{print $15}')
    CPU_IOWAIT=$(echo $VMSTAT | awk '{print $16}')
    MEM_FREE=$(echo $VMSTAT | awk '{print $4 * 1024}')  # Convert to bytes
    MEM_USED=$(free -b | awk '/Mem:/ {print $3}')  # Use free command to get used memory in bytes
    
    # Convert memory metrics to gigabytes
    MEM_FREE_GB=$(echo "scale=2; $MEM_FREE / 1024 / 1024 / 1024" | bc)
    MEM_USED_GB=$(echo "scale=2; $MEM_USED / 1024 / 1024 / 1024" | bc)
    
    # CPU Frequency
    CPU_FREQ=$(lscpu | grep "MHz" | awk '{print $3}' | head -1)
    
    # Number of processes
    NUM_PROCESSES=$(ps -e --no-headers | wc -l)
    
    # Average process size
    AVG_PROCESS_SIZE=$(get_avg_process_size)
    
    # Convert average process size to kilobytes
    AVG_PROCESS_SIZE_KB=$(echo "scale=2; $AVG_PROCESS_SIZE / 1024" | bc)
    
    # Power consumption
    POWER_CONSUMPTION=$(get_power_consumption)
    
    # CPU Utilization
    CPU_UTILIZATION=$(get_cpu_utilization | tr '\n' ' ' | sed 's/ $//')
    
    # GPU Utilization
    GPU_UTILIZATION=$(get_gpu_utilization)
    
    # Combine all metrics into a single line
    LOG_ENTRY="$TIMESTAMP,$CPU_USER,$CPU_SYSTEM,$CPU_IDLE,$CPU_IOWAIT,$MEM_FREE_GB,$MEM_USED_GB,$NUM_PROCESSES,$CPU_FREQ,$AVG_PROCESS_SIZE_KB,$POWER_CONSUMPTION,\"$CPU_UTILIZATION\",$GPU_UTILIZATION"
    
    # Write to log file
    echo $LOG_ENTRY >> $LOG_FILE
  else
    echo "No CPU activity detected. Skipping log entry..."  # Debug output
  fi
}

# Main loop
while [ $SECONDS -lt $END_TIME ]; do
  log_system_metrics
  sleep $INTERVAL
done

echo "Logging completed. Metrics logged in $LOG_FILE."

