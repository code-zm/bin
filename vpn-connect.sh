#!/bin/bash

################################################################################
# VPN Connection Script
################################################################################
#
# DESCRIPTION:
#   Interactive script to manage WireGuard VPN connections. Supports connecting
#   to random servers, selecting by state, and disconnecting active connections.
#
# PREREQUISITES:
#   - WireGuard installed (wg-quick command must be available)
#   - VPN config files named in format: wg-US-{STATE}-{NUMBER}.conf
#   - Config files located in ~/vpn/
#   - sudo privileges for wg-quick commands
#
# SETUP:
#   1. Save this script to ~/vpn/vpn-connect.sh
#   2. Make it executable:
#      chmod +x ~/vpn/vpn-connect.sh
#   3. Add to your ~/.bashrc:
#      source ~/vpn/vpn-connect.sh
#   4. Reload your shell:
#      source ~/.bashrc
#
# USAGE:
#   vpn              - Launch interactive menu
#   vpn on           - Connect to random VPN server
#   vpn off          - Disconnect all active VPN connections
#   vpn --help       - Display help message
#
# EXAMPLES:
#   # Quick connect to random server
#   $ vpn on
#   Connecting to random server: wg-US-CA-258
#
#   # Disconnect all VPNs
#   $ vpn off
#   Disconnecting all VPN connections
#
#   # Use interactive menu to select by state
#   $ vpn
#   VPN Connection Menu:
#   1) Random server (any state)
#   2) Select by state
#   3) Disconnect VPN
#   4) Cancel
#
# NOTES:
#   - The script uses 'command ls' to bypass any shell aliases
#   - Multiple VPN connections can be active simultaneously
#   - Config files must follow the naming pattern: wg-US-{STATE}-{NUMBER}.conf
#
################################################################################

vpn() {
    local vpn_dir="$HOME/vpn"

    # Check if any config files exist
    if ! command ls "$vpn_dir"/wg-US-*.conf &>/dev/null; then
        echo "No VPN config files found in $vpn_dir"
        return 1
    fi

    # Handle command-line arguments
    if [ -n "$1" ]; then
        case "$1" in
            on)
                # Connect to random server
                local config=$(command ls -1 "$vpn_dir"/wg-US-*.conf | shuf -n 1)
                local config_name=$(basename "$config" .conf)
                echo "Connecting to random server: $config_name"
                sudo wg-quick up "$config"
                return $?
                ;;
            off)
                # Disconnect all VPNs
                local active_interfaces=$(sudo wg show interfaces 2>/dev/null | tr ' ' '\n' | grep '^wg-US-')

                if [ -z "$active_interfaces" ]; then
                    echo "No active VPN connections found"
                    return 0
                fi

                local interfaces_array=($active_interfaces)
                echo "Disconnecting all VPN connections"
                for interface in "${interfaces_array[@]}"; do
                    local config="$vpn_dir/$interface.conf"
                    echo "Disconnecting from $interface"
                    sudo wg-quick down "$config"
                done
                return 0
                ;;
            --help|-h|help)
                echo "VPN Connection Script"
                echo ""
                echo "Usage: vpn [OPTION]"
                echo ""
                echo "Options:"
                echo "  on          Connect to a random VPN server"
                echo "  off         Disconnect all active VPN connections"
                echo "  --help, -h  Show this help message"
                echo "  (no option) Launch interactive menu"
                echo ""
                echo "Interactive menu allows you to:"
                echo "  - Connect to a random server from any state"
                echo "  - Select a specific state and server"
                echo "  - Disconnect active VPN connections"
                return 0
                ;;
            *)
                echo "Usage: vpn [on|off|--help]"
                echo "  on      - Connect to random server"
                echo "  off     - Disconnect all VPNs"
                echo "  --help  - Show help message"
                echo "  (no args) - Interactive menu"
                return 1
                ;;
        esac
    fi

    # Interactive menu (when no arguments provided)
    echo "VPN Connection Menu:"
    echo "1) Random server (any state)"
    echo "2) Select by state"
    echo "3) Disconnect VPN"
    echo "4) Cancel"
    read -p "Choose option [1-4]: " choice

    case $choice in
        1)
            # Random server from all configs
            local config=$(command ls -1 "$vpn_dir"/wg-US-*.conf | shuf -n 1)
            local config_name=$(basename "$config" .conf)
            echo "Connecting to random server: $config_name"
            sudo wg-quick up "$config"
            ;;
        2)
            # Get unique states
            local states=($(command ls -1 "$vpn_dir"/wg-US-*.conf | sed 's/.*wg-US-\([A-Z]*\)-.*/\1/' | sort -u))

            if [ ${#states[@]} -eq 0 ]; then
                echo "No states found"
                return 1
            fi

            echo ""
            echo "Available states:"
            for i in "${!states[@]}"; do
                echo "$((i+1))) ${states[$i]}"
            done

            read -p "Select state [1-${#states[@]}]: " state_choice

            if [[ ! "$state_choice" =~ ^[0-9]+$ ]] || [ "$state_choice" -lt 1 ] || [ "$state_choice" -gt ${#states[@]} ]; then
                echo "Invalid selection"
                return 1
            fi

            local selected_state="${states[$((state_choice-1))]}"
            local state_configs=($(command ls -1 "$vpn_dir"/wg-US-${selected_state}-*.conf))

            if [ ${#state_configs[@]} -eq 1 ]; then
                # Only one server in this state
                local config="${state_configs[0]}"
                local config_name=$(basename "$config" .conf)
                echo "Connecting to $config_name"
                sudo wg-quick up "$config"
            else
                # Multiple servers, show options
                echo ""
                echo "Servers in $selected_state:"
                echo "1) Random server from $selected_state"
                for i in "${!state_configs[@]}"; do
                    local config_name=$(basename "${state_configs[$i]}" .conf)
                    echo "$((i+2))) $config_name"
                done

                read -p "Select server [1-$((${#state_configs[@]}+1))]: " server_choice

                if [[ ! "$server_choice" =~ ^[0-9]+$ ]] || [ "$server_choice" -lt 1 ] || [ "$server_choice" -gt $((${#state_configs[@]}+1)) ]; then
                    echo "Invalid selection"
                    return 1
                fi

                if [ "$server_choice" -eq 1 ]; then
                    # Random from state
                    local config="${state_configs[$RANDOM % ${#state_configs[@]}]}"
                else
                    # Specific server
                    local config="${state_configs[$((server_choice-2))]}"
                fi

                local config_name=$(basename "$config" .conf)
                echo "Connecting to $config_name"
                sudo wg-quick up "$config"
            fi
            ;;
        3)
            # Disconnect VPN
            local active_interfaces=$(sudo wg show interfaces 2>/dev/null | tr ' ' '\n' | grep '^wg-US-')

            if [ -z "$active_interfaces" ]; then
                echo "No active VPN connections found"
                return 0
            fi

            # Convert to array
            local interfaces_array=($active_interfaces)

            if [ ${#interfaces_array[@]} -eq 1 ]; then
                # Only one active connection
                local interface="${interfaces_array[0]}"
                local config="$vpn_dir/$interface.conf"
                echo "Disconnecting from $interface"
                sudo wg-quick down "$config"
            else
                # Multiple active connections
                echo ""
                echo "Active VPN connections:"
                for i in "${!interfaces_array[@]}"; do
                    echo "$((i+1))) ${interfaces_array[$i]}"
                done
                echo "$((${#interfaces_array[@]}+1))) Disconnect all"

                read -p "Select connection to disconnect [1-$((${#interfaces_array[@]}+1))]: " disconnect_choice

                if [[ ! "$disconnect_choice" =~ ^[0-9]+$ ]] || [ "$disconnect_choice" -lt 1 ] || [ "$disconnect_choice" -gt $((${#interfaces_array[@]}+1)) ]; then
                    echo "Invalid selection"
                    return 1
                fi

                if [ "$disconnect_choice" -eq $((${#interfaces_array[@]}+1)) ]; then
                    # Disconnect all
                    echo "Disconnecting all VPN connections"
                    for interface in "${interfaces_array[@]}"; do
                        local config="$vpn_dir/$interface.conf"
                        echo "Disconnecting from $interface"
                        sudo wg-quick down "$config"
                    done
                else
                    # Disconnect specific connection
                    local interface="${interfaces_array[$((disconnect_choice-1))]}"
                    local config="$vpn_dir/$interface.conf"
                    echo "Disconnecting from $interface"
                    sudo wg-quick down "$config"
                fi
            fi
            ;;
        4)
            echo "Cancelled"
            return 0
            ;;
        *)
            echo "Invalid option"
            return 1
            ;;
    esac
}

# If script is sourced, just define the function
# If executed directly, run the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    vpn "$@"
fi
