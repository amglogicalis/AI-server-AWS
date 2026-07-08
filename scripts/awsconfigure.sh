#!/bin/bash
# awsconfigure.sh - WSL/Linux compatible AWS Credentials Manager
# Automatically runs GUI if available (WSLg), otherwise falls back to interactive TUI.

# Path to the credentials file in the WSL home directory
AWS_DIR="$HOME/.aws"
CRED_PATH="$AWS_DIR/credentials"

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if GUI is supported in the current environment
GUI_AVAILABLE=0
if [ -n "$DISPLAY" ] && command -v python3 &>/dev/null; then
    if python3 -c "import tkinter" &>/dev/null; then
        GUI_AVAILABLE=1
    fi
fi

if [ $GUI_AVAILABLE -eq 1 ]; then
    echo "Entorno gráfico detectado. Iniciando GUI..."
    python3 "$SCRIPT_DIR/awsconfigure_gui.py" "$@"
    exit $?
fi

echo "Nota: Interfaz gráfica no disponible (\$DISPLAY vacío o falta el paquete python3-tk)."
echo "Iniciando menú interactivo en terminal..."
echo ""


# Ensure directories and files exist
mkdir -p "$AWS_DIR"
touch "$CRED_PATH"

# -------------------------------------------------------
# PARSE PROFILE DATA
# -------------------------------------------------------
get_profile_data() {
    local target_profile="$1"
    local inside=0
    while IFS= read -r line || [ -n "$line" ]; do
        # Clean carriage returns and trim whitespace
        line=$(echo "$line" | tr -d '\r' | xargs)
        if [[ "$line" =~ ^\[([^]]+)\]$ ]]; then
            local profile_name="${BASH_REMATCH[1]}"
            if [ "$profile_name" = "$target_profile" ]; then
                inside=1
            else
                inside=0
            fi
            continue
        fi
        if [ $inside -eq 1 ]; then
            if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
                local key=$(echo "${BASH_REMATCH[1]}" | xargs)
                local val=$(echo "${BASH_REMATCH[2]}" | xargs)
                echo "${key}=${val}"
            fi
        fi
    done < "$CRED_PATH"
}

# -------------------------------------------------------
# SAVE / UPDATE PROFILE
# -------------------------------------------------------
save_profile_data() {
    local profile="$1"
    local ak="$2"
    local sk="$3"
    local token="$4"

    local inside_target=0
    local found_profile=0
    local handled_ak=0
    local handled_sk=0
    local handled_token=0

    local tmp_file=$(mktemp)

    if [ -f "$CRED_PATH" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            local trimmed=$(echo "$line" | tr -d '\r' | xargs)
            
            if [[ "$trimmed" =~ ^\[([^]]+)\]$ ]]; then
                local cur="${BASH_REMATCH[1]}"
                if [ $inside_target -eq 1 ]; then
                    [ $handled_ak -eq 0 ] && echo "aws_access_key_id = $ak" >> "$tmp_file" && handled_ak=1
                    [ $handled_sk -eq 0 ] && echo "aws_secret_access_key = $sk" >> "$tmp_file" && handled_sk=1
                    if [ $handled_token -eq 0 ] && [ -n "$token" ]; then
                        echo "aws_session_token = $token" >> "$tmp_file"
                        handled_token=1
                    fi
                    inside_target=0
                fi
                if [ "$cur" = "$profile" ]; then
                    inside_target=1
                    found_profile=1
                    echo "$trimmed" >> "$tmp_file"
                    continue
                fi
            fi

            if [ $inside_target -eq 1 ]; then
                if [[ "$trimmed" =~ ^aws_access_key_id[[:space:]]*= ]]; then
                    echo "aws_access_key_id = $ak" >> "$tmp_file"
                    handled_ak=1
                elif [[ "$trimmed" =~ ^aws_secret_access_key[[:space:]]*= ]]; then
                    echo "aws_secret_access_key = $sk" >> "$tmp_file"
                    handled_sk=1
                elif [[ "$trimmed" =~ ^aws_session_token[[:space:]]*= ]]; then
                    if [ -n "$token" ]; then
                        echo "aws_session_token = $token" >> "$tmp_file"
                    fi
                    handled_token=1
                else
                    if [ -n "$trimmed" ]; then
                        echo "$trimmed" >> "$tmp_file"
                    fi
                fi
            else
                if [ -n "$trimmed" ] || [ -s "$tmp_file" ]; then
                    echo "$line" | tr -d '\r' >> "$tmp_file"
                fi
            fi
        done < "$CRED_PATH"
    fi

    if [ $inside_target -eq 1 ]; then
        [ $handled_ak -eq 0 ] && echo "aws_access_key_id = $ak" >> "$tmp_file"
        [ $handled_sk -eq 0 ] && echo "aws_secret_access_key = $sk" >> "$tmp_file"
        if [ $handled_token -eq 0 ] && [ -n "$token" ]; then
            echo "aws_session_token = $token" >> "$tmp_file"
        fi
    fi

    if [ $found_profile -eq 0 ]; then
        if [ -s "$tmp_file" ]; then
            echo "" >> "$tmp_file"
        fi
        echo "[$profile]" >> "$tmp_file"
        echo "aws_access_key_id = $ak" >> "$tmp_file"
        echo "aws_secret_access_key = $sk" >> "$tmp_file"
        if [ -n "$token" ]; then
            echo "aws_session_token = $token" >> "$tmp_file"
        fi
    fi

    mv "$tmp_file" "$CRED_PATH"
    chmod 600 "$CRED_PATH"
}

# -------------------------------------------------------
# REMOVE PROFILE
# -------------------------------------------------------
remove_profile_data() {
    local profile="$1"
    [ ! -f "$CRED_PATH" ] && return

    local inside_target=0
    local tmp_file=$(mktemp)

    while IFS= read -r line || [ -n "$line" ]; do
        local trimmed=$(echo "$line" | tr -d '\r' | xargs)
        if [[ "$trimmed" =~ ^\[([^]]+)\]$ ]]; then
            local cur="${BASH_REMATCH[1]}"
            if [ "$cur" = "$profile" ]; then
                inside_target=1
                continue
            else
                inside_target=0
            fi
        fi
        if [ $inside_target -eq 1 ]; then
            continue
        fi
        echo "$line" | tr -d '\r' >> "$tmp_file"
    done < "$CRED_PATH"

    mv "$tmp_file" "$CRED_PATH"
    chmod 600 "$CRED_PATH"
}

# -------------------------------------------------------
# TUI MENU ACTIONS
# -------------------------------------------------------
list_profiles() {
    echo "--- Existing AWS Profiles ---"
    local profiles=$(grep -E '^\[[^]]+\]' "$CRED_PATH" | tr -d '[]\r')
    if [ -z "$profiles" ]; then
        echo "No profiles found."
    else
        echo "$profiles"
    fi
    echo "-----------------------------"
}

select_profile() {
    local profiles=($(grep -E '^\[[^]]+\]' "$CRED_PATH" | tr -d '[]\r'))
    if [ ${#profiles[@]} -eq 0 ]; then
        echo "No profiles found." >&2
        return 1
    fi
    
    echo "Select a profile:" >&2
    for i in "${!profiles[@]}"; do
        echo "  $((i+1))) ${profiles[$i]}" >&2
    done
    
    local choice
    echo -n "Enter number (1-${#profiles[@]}): " >&2
    read choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
        echo "${profiles[$((choice-1))]}"
        return 0
    else
        echo "Invalid selection." >&2
        return 1
    fi
}

view_profile_details() {
    echo "--- View Profile Details ---"
    local profile
    profile=$(select_profile)
    [ $? -ne 0 ] && return
    
    echo ""
    echo "Details for profile [$profile]:"
    local data
    data=$(get_profile_data "$profile")
    
    local ak=""
    local sk=""
    local token=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^aws_access_key_id=(.*)$ ]]; then
            ak="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^aws_secret_access_key=(.*)$ ]]; then
            sk="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^aws_session_token=(.*)$ ]]; then
            token="${BASH_REMATCH[1]}"
        fi
    done <<< "$data"
    
    echo "Access Key ID     : $ak"
    if [ -n "$sk" ]; then
        echo "Secret Access Key : ************${sk: -4}"
    else
        echo "Secret Access Key : (not set)"
    fi
    if [ -n "$token" ]; then
        echo "Session Token     : [Set (Length: ${#token})]"
    else
        echo "Session Token     : (not set)"
    fi
    echo "----------------------------"
}

create_or_update_profile() {
    echo "--- Create or Update Profile ---"
    echo "1) Update an existing profile"
    echo "2) Create a new profile"
    echo -n "Select option (1-2): "
    local choice
    read choice
    
    local profile=""
    local existing_ak=""
    local existing_sk=""
    local existing_token=""
    
    if [ "$choice" = "1" ]; then
        profile=$(select_profile)
        [ $? -ne 0 ] && return
        
        local data
        data=$(get_profile_data "$profile")
        while IFS= read -r line; do
            if [[ "$line" =~ ^aws_access_key_id=(.*)$ ]]; then
                existing_ak="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^aws_secret_access_key=(.*)$ ]]; then
                existing_sk="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^aws_session_token=(.*)$ ]]; then
                existing_token="${BASH_REMATCH[1]}"
            fi
        done <<< "$data"
    elif [ "$choice" = "2" ]; then
        echo -n "Enter new profile name: "
        read profile
        profile=$(echo "$profile" | xargs)
        if [ -z "$profile" ]; then
            echo "Profile name cannot be empty."
            return
        fi
        if [[ "$profile" =~ [[:space:]] ]]; then
            echo "Profile name cannot contain spaces."
            return
        fi
    else
        echo "Invalid option."
        return
    fi
    
    local ak
    echo -n "AWS Access Key ID [${existing_ak}]: "
    read ak
    ak=$(echo "$ak" | xargs)
    [ -z "$ak" ] && ak="$existing_ak"
    
    local sk
    local display_sk=""
    [ -n "$existing_sk" ] && display_sk="********"
    echo -n "AWS Secret Access Key [$display_sk]: "
    read sk
    sk=$(echo "$sk" | xargs)
    [ -z "$sk" ] && sk="$existing_sk"
    
    local token
    local display_token=""
    [ -n "$existing_token" ] && display_token="[Existing Token]"
    echo -n "AWS Session Token (optional) [$display_token]: "
    read token
    token=$(echo "$token" | xargs)
    [ -z "$token" ] && token="$existing_token"
    
    if [ -z "$ak" ] || [ -z "$sk" ]; then
        echo "Error: AWS Access Key ID and Secret Access Key are required."
        return
    fi
    
    save_profile_data "$profile" "$ak" "$sk" "$token"
    echo "Profile '$profile' saved successfully."
}

delete_profile() {
    echo "--- Delete Profile ---"
    local profile
    profile=$(select_profile)
    [ $? -ne 0 ] && return
    
    echo -n "Are you sure you want to delete profile '$profile'? (y/N): "
    local confirm
    read confirm
    if [[ "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        remove_profile_data "$profile"
        echo "Profile '$profile' deleted successfully."
    else
        echo "Deletion cancelled."
    fi
}

validate_profile() {
    echo "--- Validate Profile ---"
    local profile
    profile=$(select_profile)
    [ $? -ne 0 ] && return
    
    if ! command -v aws &> /dev/null; then
        echo "Error: 'aws' CLI tool is not installed or not in the PATH." >&2
        echo "Please install AWS CLI in your Ubuntu environment." >&2
        return
    fi
    
    echo "Validating credentials for profile '$profile'..."
    local output
    output=$(aws sts get-caller-identity --profile "$profile" 2>&1)
    local status=$?
    
    if [ $status -eq 0 ]; then
        echo "========================================="
        echo "         VALIDATION SUCCESSFUL"
        echo "========================================="
        if command -v jq &> /dev/null; then
            echo "$output" | jq .
        else
            echo "$output"
        fi
        echo "========================================="
    else
        echo "========================================="
        echo "           VALIDATION FAILED"
        echo "========================================="
        echo "$output"
        echo "========================================="
    fi
}

# Main Loop
while true; do
    echo ""
    echo "========================================="
    echo "      AWS CREDENTIALS MANAGER (WSL)"
    echo "========================================="
    echo "1) List existing profiles"
    echo "2) View profile details"
    echo "3) Create / Update a profile"
    echo "4) Delete a profile"
    echo "5) Validate credentials with AWS CLI"
    echo "6) Exit"
    echo "========================================="
    echo -n "Select an option (1-6): "
    read opt
    echo ""
    
    case $opt in
        1) list_profiles ;;
        2) view_profile_details ;;
        3) create_or_update_profile ;;
        4) delete_profile ;;
        5) validate_profile ;;
        6) echo "Exiting. Goodbye!"; exit 0 ;;
        *) echo "Invalid option. Please try again." ;;
    esac
done
