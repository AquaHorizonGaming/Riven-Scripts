#!/bin/bash

# Function to check if the Docker container is running
check_container_status() {
    docker ps | grep -q "riven-db"
    if [ $? -ne 0 ]; then
        echo "Error: The 'riven-db' container is not running. Please start the container and try again."
        exit 1
    fi
}

# Function to perform a backup
backup_database() {
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local backup_file="/tmp/riven_backup_${timestamp}.sql"

    echo "Do you want to create a backup of the database before proceeding?"
    read -p "Type 'y' to back up or 'n' to skip: " backup_choice

    if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
        echo "Creating a backup of the database..."

        # Use docker exec to dump the database
        docker exec riven-db pg_dump -U postgres -d riven -f "$backup_file"

        if [ $? -eq 0 ]; then
            echo "Backup created successfully: $backup_file"
        else
            echo "Error: Backup failed."
            exit 1
        fi
    else
        echo "No backup created. Proceeding with the reset."
    fi
}

# Function to fetch and display state items with confirmation
fetch_state_items() {
    local state=$1
    echo "Do you want to see the items in the '$state' state?"
    read -p "Type 'y' to view them or 'n' to skip: " view_choice
    if [[ "$view_choice" =~ ^[Yy]$ ]]; then
        echo "Fetching items in the '$state' state..."
        docker exec riven-db psql -U postgres -d riven -c "SELECT id, title, last_state, scraped_times FROM \"MediaItem\" WHERE last_state = '$state';"
    else
        echo "Skipping viewing '$state' items."
    fi
}

# Function to reset state items (Unknown, Paused, Failed)
reset_state_items() {
    local state=$1
    echo "You are about to reset the '$state' items to 'Indexed'."
    echo "This will reset the following attributes:"
    echo "  - 'scraped_times' to 0"
    echo "  - 'scraped_at' to NULL"
    echo "  - 'active_stream' to NULL"
    read -p "Press Enter to confirm or CTRL+C to cancel..."

    # Perform the reset in the database
    echo "Resetting '$state' items..."
    docker exec riven-db psql -U postgres -d riven -c "
    BEGIN;
    UPDATE \"MediaItem\"
    SET last_state = 'Indexed',
        scraped_at = NULL,
        scraped_times = 0,
        active_stream = NULL
    WHERE last_state = '$state';
    COMMIT;
    "
    if [ $? -eq 0 ]; then
        echo "'$state' items successfully reset to 'Indexed'."
    else
        echo "Error: Database update failed for '$state'. Rolling back changes."
        docker exec riven-db psql -U postgres -d riven -c "ROLLBACK;"
        exit 1
    fi
}

# Function to ask the user which states they want to reset
ask_reset_states() {
    echo "Select which states you want to reset (you can choose multiple states):"
    echo "1) Unknown"
    echo "2) Paused"
    echo "3) Failed"
    read -p "Enter your choices (e.g., '1 3' for Unknown and Failed, '2 3' for Paused and Failed, etc.): " -a choices

    # Loop through the choices and perform actions for each selected state
    for choice in "${choices[@]}"; do
        case $choice in
            1)
                fetch_state_items "Unknown"
                reset_state_items "Unknown"
                ;;
            2)
                fetch_state_items "Paused"
                reset_state_items "Paused"
                ;;
            3)
                fetch_state_items "Failed"
                reset_state_items "Failed"
                ;;
            *)
                echo "Invalid choice: $choice. Skipping."
                ;;
        esac
    done
}

# Function to display current state counts after reset
show_current_counts() {
    echo "Fetching current counts of MediaItem states..."

    indexed_count=$(docker exec riven-db psql -U postgres -d riven -t -c "SELECT count(*) FROM \"MediaItem\" WHERE last_state = 'Indexed';")
    paused_count=$(docker exec riven-db psql -U postgres -d riven -t -c "SELECT count(*) FROM \"MediaItem\" WHERE last_state = 'Paused';")
    unknown_count=$(docker exec riven-db psql -U postgres -d riven -t -c "SELECT count(*) FROM \"MediaItem\" WHERE last_state = 'Unknown';")
    failed_count=$(docker exec riven-db psql -U postgres -d riven -t -c "SELECT count(*) FROM \"MediaItem\" WHERE last_state = 'Failed';")
    completed_count=$(docker exec riven-db psql -U postgres -d riven -t -c "SELECT count(*) FROM \"MediaItem\" WHERE last_state = 'Completed';")

    echo "Current MediaItem States:"
    echo "  - Indexed:   $indexed_count"
    echo "  - Paused:    $paused_count"
    echo "  - Unknown:   $unknown_count"
    echo "  - Failed:    $failed_count"
    echo "  - Completed: $completed_count"
}

# Main script execution
echo "Starting the reset process for MediaItem states..."

# Step 1: Check if the Docker container is running
check_container_status

# Step 2: Ask the user if they want to create a backup
backup_database

# Step 3: Ask the user which states they want to reset (can select multiple)
ask_reset_states

# Step 4: Show the current counts after the reset
show_current_counts

echo "Script completed successfully."
