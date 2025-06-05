#!/bin/bash

NGINX_CONF="nginx.frontend.conf"
BACKUP_CONF="nginx.frontend.conf.bak"
HTPASSWD_FILE="./.htpasswd"
DEFAULT_ENTRIES=("127.0.0.1" "136.244.91.127")
CONTAINER_NAME="Ecom_nginx"

usage() {
    echo -e "\n\033[1;36mUsage:\033[0m"
    echo -e "  \033[1m$0 [options] [arguments]\033[0m\n"

    echo -e "\033[1;36mOptions:\033[0m"
    echo -e "  \033[1mlist\033[0m,    \033[1m-l\033[0m                   Display the current list of allowed IPs."
    echo -e "  \033[1madd\033[0m,     \033[1m-a <IP_ADDRESS>\033[0m     Add a new IP address to the allowed list."
    echo -e "  \033[1mdelete\033[0m,  \033[1m-d <IP_ADDRESS>\033[0m     Remove an IP address from the allowed list."
    echo -e "  \033[1mclear\033[0m,   \033[1m-c\033[0m                   Clear all custom IPs and keep defaults only."
    echo -e "  \033[1mrestore\033[0m, \033[1m-r\033[0m                   Restore the backup configuration."
    echo -e "  \033[1muser\033[0m,    \033[1m-u\033[0m                   Add a user for HTTP auth (e.g. phpMyAdmin)."

    echo -e "\n\033[1;33mExamples:\033[0m"
    echo -e "  $0 -l"
    echo -e "  $0 add 192.168.1.10"
    echo -e "  $0 -d 192.168.1.10"
    echo -e "  $0 -c"
    echo -e "  $0 -r"
    echo -e "  $0 -u"

    exit 1
}

# Validate IP format
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo "Error: '$ip' is not a valid IP address."
        exit 1
    fi

    # Check each octet is <= 255
    IFS='.' read -r -a octets <<< "$ip"
    for octet in "${octets[@]}"; do
        ((octet >= 0 && octet <= 255)) || {
            echo "Error: Invalid octet $octet in IP $ip"
            exit 1
        }
    done
}

backup_config() {
    cp "$NGINX_CONF" "$BACKUP_CONF"
}

restart_nginx() {
    if docker restart $CONTAINER_NAME >/dev/null 2>&1; then
        echo "IP rule applied and Nginx container restarted successfully."
    else
        echo "Docker restart failed. Restoring previous config."
        mv "$BACKUP_CONF" "$NGINX_CONF"
        exit 1
    fi
}

ACTION=""
IP=""
CONFIG_CHANGED=0

case "$1" in
    list|-l) ACTION="list" ;;
    add|-a) ACTION="add"; IP=$2 ;;
    delete|-d) ACTION="delete"; IP=$2 ;;
    clear|-c) ACTION="clear" ;;
    restore|-r) ACTION="restore" ;;
    user|-u) ACTION="user" ;;
    *) usage ;;
esac

case "$ACTION" in
    add)
        [ -z "$IP" ] && echo "Missing IP address." && usage
        validate_ip "$IP"

        if grep -qE "[[:space:]]$IP[[:space:]]+1;" "$NGINX_CONF"; then
            echo "IP $IP already exists in map block."
            exit 0
        fi

        backup_config
        CONFIG_CHANGED=1

        awk -v ip="$IP" '
            BEGIN { inside_map = 0 }
            {
                if ($0 ~ /map \$remote_addr \$is_allowed_ip {/) {
                    inside_map = 1
                    print
                    next
                }
                if (inside_map && $0 ~ /^[ \t]*}[ \t]*$/) {
                    printf("        %s 1;  # added by script\n", ip)
                    inside_map = 0
                }
                print
            }
        ' "$BACKUP_CONF" > "$NGINX_CONF"

        echo "IP $IP added."
        ;;

    delete)
        [ -z "$IP" ] && echo "Missing IP address." && usage
        validate_ip "$IP"

        if ! grep -qE "^[[:space:]]*$IP[[:space:]]+1;.*# added by script" "$NGINX_CONF"; then
            echo "IP $IP not found. No changes made."
            exit 0
        fi

        backup_config
        CONFIG_CHANGED=1

        grep -vE "^[[:space:]]*$IP[[:space:]]+1;.*# added by script" "$BACKUP_CONF" > "$NGINX_CONF"
        echo "IP $IP removed."
        ;;

    clear)
        # Check if any custom (non-default) IPs exist
        TMP=$(mktemp)
        trap "rm -f $TMP" EXIT

        awk '
            BEGIN { inside_map = 0 }
            /map \$remote_addr \$is_allowed_ip {/ { inside_map = 1; next }
            inside_map && /^[ \t]*}/ { inside_map = 0; next }
            inside_map {
                if ($1 != "default") print $1
            }
        ' "$NGINX_CONF" > "$TMP"

        CUSTOM_FOUND=0
        while read -r ip; do
            skip=0
            for default in "${DEFAULT_ENTRIES[@]}"; do
                [[ "$ip" == "$default" ]] && skip=1 && break
            done
            ((skip)) || CUSTOM_FOUND=1
        done < "$TMP"

        if [[ $CUSTOM_FOUND -eq 0 ]]; then
            echo "No custom IPs to clear."
            exit 0
        fi

        backup_config
        CONFIG_CHANGED=1

        awk -v defaults="${DEFAULT_ENTRIES[*]}" '
            BEGIN {
                split(defaults, keep_ips)
                inside_map = 0
            }
            {
                if ($0 ~ /map \$remote_addr \$is_allowed_ip {/) {
                    inside_map = 1
                    print
                    next
                }
                if (inside_map && $0 ~ /^[ \t]*}[ \t]*$/) {
                    for (i in keep_ips) {
                        printf("        %s 1;\n", keep_ips[i])
                    }
                    inside_map = 0
                } else if (inside_map) {
                    if ($0 ~ /^[[:space:]]*default[[:space:]]+0;/) print
                    next
                }
                print
            }
        ' "$BACKUP_CONF" > "$NGINX_CONF"

        echo "Cleared all custom IPs. Defaults retained."
        ;;

    list)
        awk '
            BEGIN { inside_map = 0 }
            /map \$remote_addr \$is_allowed_ip {/ { inside_map = 1; next }
            inside_map && /^[ \t]*}/ { inside_map = 0; next }
            inside_map {
                gsub(/[;#].*$/, "", $0)
                print $1
            }
        ' "$NGINX_CONF"
        exit 0
        ;;

    user)
        echo -ne "\033[1;36mEnter username:\033[0m "
        read -r username
        [[ -z "$username" ]] && echo "Username cannot be empty." && exit 1

        echo -ne "\033[1;36mEnter password:\033[0m "
        read -s password
        echo
        [[ -z "$password" ]] && echo "Password cannot be empty." && exit 1

        if [[ -f "$HTPASSWD_FILE" ]]; then
            htpasswd -b "$HTPASSWD_FILE" "$username" "$password"
        else
            htpasswd -b -c "$HTPASSWD_FILE" "$username" "$password"
        fi

        if [[ $? -eq 0 ]]; then
            CONFIG_CHANGED=1
            echo -e "\033[1;32mUser '$username' added to $HTPASSWD_FILE.\033[0m"
        else
            echo -e "\033[1;31mFailed to add user.\033[0m"
            exit 1
        fi
        ;;

    restore)
        if [[ ! -f "$BACKUP_CONF" ]]; then
            echo "Backup file $BACKUP_CONF does not exist. Cannot restore."
            exit 1
        fi

        cp "$BACKUP_CONF" "$NGINX_CONF"
        CONFIG_CHANGED=1
        echo "Backup restored from $BACKUP_CONF to $NGINX_CONF."
        ;;
esac

if [[ "$CONFIG_CHANGED" -eq 1 ]]; then
    echo "Operation completed. Restarting Nginx container..."
    restart_nginx
fi
