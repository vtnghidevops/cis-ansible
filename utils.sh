#!/bin/bash

# SSH Key Manager Script - Pure Bash Version
# Tự động tạo SSH key, copy đến target servers và tạo Ansible vault files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SSH_DIR="$HOME/.ssh"
VAULT_DIR="host_vars"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check ssh-keygen
    if ! command -v ssh-keygen &> /dev/null; then
        missing_deps+=("ssh-keygen")
    fi
    
    # Check ssh-copy-id
    if ! command -v ssh-copy-id &> /dev/null; then
        missing_deps+=("ssh-copy-id")
    fi
    
    # Check ansible-vault
    if ! command -v ansible-vault &> /dev/null; then
        print_warning "ansible-vault is not installed. Vault files will be created as plain text."
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_info "Please install OpenSSH client tools"
        exit 1
    fi
}

# Function to create SSH directory
setup_ssh_directory() {
    if [ ! -d "$SSH_DIR" ]; then
        print_info "Creating SSH directory: $SSH_DIR"
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi
}

# Function to generate SSH key
generate_ssh_key() {
    local key_name="$1"
    local private_key="$SSH_DIR/id_rsa_$key_name"
    local public_key="$SSH_DIR/id_rsa_$key_name.pub"
    
    print_header "🔑 Generate SSH Key: $key_name"
    
    # Check if key already exists
    if [ -f "$private_key" ] || [ -f "$public_key" ]; then
        print_warning "SSH key '$key_name' already exists!"
        read -p "Do you want to overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Key generation cancelled."
            return 1
        fi
    fi
    
    # Generate SSH key
    print_info "Generating SSH key..."
    if ssh-keygen -t rsa -b 4096 -f "$private_key" -N "" -C "$key_name"; then
        print_success "SSH key generated successfully:"
        echo "   Private key: $private_key"
        echo "   Public key: $public_key"
        
        # Set correct permissions
        chmod 600 "$private_key"
        chmod 644 "$public_key"
        
        return 0
    else
        print_error "Error generating SSH key"
        return 1
    fi
}

# Function to copy SSH key to servers
copy_ssh_key_to_servers() {
    local key_name="$1"
    shift
    local servers=("$@")
    local public_key="$SSH_DIR/id_rsa_$key_name.pub"
    
    print_header "📋 Copy SSH Key to Servers"
    
    # Check if public key exists
    if [ ! -f "$public_key" ]; then
        print_error "Public key does not exist: $public_key"
        return 1
    fi
    
    # Display servers list
    print_info "Servers to copy key to:"
    for i in "${!servers[@]}"; do
        echo "   $((i+1)). ${servers[i]}"
    done
    
    echo
    print_info "Using key: $public_key"
    
    local success_count=0
    local failed_servers=()
    
    # Copy key to each server
    for server in "${servers[@]}"; do
        echo
        print_info "🔄 Copying key to $server..."
        
        # Get username for the server
        read -p "Enter username for $server: " username
        if [ -z "$username" ]; then
            print_error "Username cannot be empty for $server"
            failed_servers+=("$server")
            continue
        fi
        
        # Run ssh-copy-id command with automatic host key acceptance and force overwrite
        print_info "Running: ssh-copy-id -o StrictHostKeyChecking=no -i $public_key $username@$server"
        if ssh-copy-id -f -o StrictHostKeyChecking=no -i "$public_key" "$username@$server"; then
            print_success "Successfully copied key to $username@$server"
            ((success_count++))
        else
            print_error "Error copying key to $username@$server"
            failed_servers+=("$server")
        fi
        
        echo "--- Completed for $server ---"
    done
    
    # Display results
    echo
    print_header "📊 Results"
    echo "   ✅ Success: $success_count/${#servers[@]}"
    
    if [ ${#failed_servers[@]} -gt 0 ]; then
        echo "   ❌ Failed: ${#failed_servers[@]} servers"
        echo "   Failed servers: ${failed_servers[*]}"
    fi
    
    return $([ $success_count -eq ${#servers[@]} ] && echo 0 || echo 1)
}

# Function to copy multiple files to server (simple version)
copy_files_to_server() {
    local key_name="$1"
    
    print_header "📁 Copy Multiple Files to Server"
    
    # Check if private key exists
    local private_key="$SSH_DIR/id_rsa_$key_name"
    if [ ! -f "$private_key" ]; then
        print_error "Private key does not exist: $private_key"
        return 1
    fi
    
    # Get files list path
    echo
    read -p "Enter files list path: " files_list
    if [ ! -f "$files_list" ]; then
        print_error "Files list not found: $files_list"
        return 1
    fi
    
    # Load files from file
    local files=()
    print_info "Reading files from: $files_list"
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            # Trim whitespace and newlines
            line=$(echo "$line" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$line" ]; then
                files+=("$line")
                echo "   [DEBUG] Added: '$line'"
            fi
        fi
    done < "$files_list"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_error "No files found in $files_list"
        return 1
    fi
    
    echo
    print_info "Files loaded from $files_list:"
    for i in "${!files[@]}"; do
        echo "   $((i+1)). '${files[i]}'"
    done
    echo
    
    # Check if files exist in current directory
    local missing_files=()
    local existing_files=()
    
    print_info "Checking files:"
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            existing_files+=("$file")
            echo "   ✅ $file (found)"
        else
            missing_files+=("$file")
            echo "   ❌ $file (not found)"
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing files: ${missing_files[*]}"
        print_info "Make sure files are in the current directory"
        return 1
    fi
    
    # Get target info
    echo
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi
    
    read -p "Enter target IP: " target_ip
    if [ -z "$target_ip" ]; then
        print_error "Target IP cannot be empty"
        return 1
    fi
    
    # Get remote directory (optional)
    read -p "Enter remote directory (default: ~/): " remote_dir
    remote_dir="${remote_dir:-~/}"
    
    # Confirm before proceeding
    echo
    print_info "Summary:"
    echo "   Files list: $files_list"
    echo "   Files: ${existing_files[*]}"
    echo "   Target: $username@$target_ip:$remote_dir"
    echo "   Using key: $private_key"
    
    read -p "Proceed with file copy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "File copy cancelled."
        return 1
    fi
    
    # Copy files to target server
    echo
    print_info "🔄 Copying files to $username@$target_ip:$remote_dir"
    
    # Build scp command with all files
    local scp_cmd="scp -i $private_key -o StrictHostKeyChecking=no"
    
    # Add all files to the command
    for file in "${existing_files[@]}"; do
        scp_cmd="$scp_cmd \"$file\""
    done
    
    # Add destination
    scp_cmd="$scp_cmd $username@$target_ip:$remote_dir"
    
    print_info "Running: $scp_cmd"
    
    if eval "$scp_cmd"; then
        print_success "✅ Successfully copied ${#existing_files[@]} files to $username@$target_ip:$remote_dir"
        echo "   Files copied: ${existing_files[*]}"
    else
        print_error "❌ Error copying files to $username@$target_ip"
        return 1
    fi
    
    return 0
}

# Function to copy files to servers from file list
copy_files_to_servers_from_file() {
    local key_name="$1"
    local files_list="$2"
    local servers_file="$3"
    
    print_header "📁 Copy Multiple Files to Servers (from files)"
    
    # Check if private key exists
    local private_key="$SSH_DIR/id_rsa_$key_name"
    if [ ! -f "$private_key" ]; then
        print_error "Private key does not exist: $private_key"
        return 1
    fi
    
    # Load files from file
    if [ ! -f "$files_list" ]; then
        print_error "Files list does not exist: $files_list"
        return 1
    fi
    
    local files=()
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            files+=("$line")
        fi
    done < "$files_list"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_error "No files found in $files_list"
        return 1
    fi
    
    # Load servers from file
    if [ ! -f "$servers_file" ]; then
        print_error "Servers file does not exist: $servers_file"
        return 1
    fi
    
    local servers=()
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            servers+=("$line")
        fi
    done < "$servers_file"
    
    if [ ${#servers[@]} -eq 0 ]; then
        print_error "No servers found in $servers_file"
        return 1
    fi
    
    # Display files list
    print_info "Files to copy:"
    for i in "${!files[@]}"; do
        if [ -f "${files[i]}" ]; then
            echo "   $((i+1)). ${files[i]} ✅"
        else
            echo "   $((i+1)). ${files[i]} ❌ (not found)"
        fi
    done
    
    # Check if all files exist
    local missing_files=()
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -gt 0 ]; then
        print_error "Missing files: ${missing_files[*]}"
        return 1
    fi
    
    # Display servers list
    echo
    print_info "Target servers:"
    for i in "${!servers[@]}"; do
        echo "   $((i+1)). ${servers[i]}"
    done
    
    # Get username for all servers
    echo
    read -p "Enter username for all servers: " username
    if [ -z "$username" ]; then
        print_error "Username cannot be empty"
        return 1
    fi
    
    # Get remote directory
    read -p "Enter remote directory (default: ~/): " remote_dir
    remote_dir="${remote_dir:-~/}"
    
    # Confirm before proceeding
    echo
    print_info "Summary:"
    echo "   Files: ${#files[@]} files from $files_list"
    echo "   Servers: ${#servers[@]} servers from $servers_file"
    echo "   Username: $username"
    echo "   Remote directory: $remote_dir"
    echo "   Using key: $private_key"
    
    read -p "Proceed with file copy? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "File copy cancelled."
        return 1
    fi
    
    local success_count=0
    local failed_servers=()
    
    # Copy files to each server
    for server in "${servers[@]}"; do
        echo
        print_info "🔄 Copying files to $username@$server:$remote_dir"
        
        # Build scp command with all files
        local scp_cmd="scp -i $private_key -o StrictHostKeyChecking=no"
        
        # Add all files to the command
        for file in "${files[@]}"; do
            scp_cmd="$scp_cmd \"$file\""
        done
        
        # Add destination
        scp_cmd="$scp_cmd $username@$server:$remote_dir"
        
        print_info "Running: $scp_cmd"
        
        if eval "$scp_cmd"; then
            print_success "Successfully copied files to $username@$server:$remote_dir"
            ((success_count++))
        else
            print_error "Error copying files to $username@$server"
            failed_servers+=("$server")
        fi
        
        echo "--- Completed for $server ---"
    done
    
    # Display results
    echo
    print_header "📊 Results"
    echo "   ✅ Success: $success_count/${#servers[@]}"
    
    if [ ${#failed_servers[@]} -gt 0 ]; then
        echo "   ❌ Failed: ${#failed_servers[@]} servers"
        echo "   Failed servers: ${failed_servers[*]}"
    fi
    
    return $([ $success_count -eq ${#servers[@]} ] && echo 0 || echo 1)
}

# Function to create Ansible vault
create_ansible_vault() {
    local vault_name="$1"
    shift
    local hosts=("$@")
    
    print_header "🔐 Create Ansible Vault"
    
    # Create vault directory
    if [ ! -d "$VAULT_DIR" ]; then
        print_info "Creating host_vars directory: $VAULT_DIR"
        mkdir -p "$VAULT_DIR"
    fi
    
    local vault_file="$VAULT_DIR/$vault_name.yml"
    local inventory_file="$VAULT_DIR/inventory_$vault_name.yml"
    
    # Create vault content
    cat > "$vault_file" << EOF
# Ansible Vault File: $vault_name
# Created: $(date)

vault_name: $vault_name
hosts:
EOF
    
    # Add hosts to vault file
    for host in "${hosts[@]}"; do
        echo "  - $host" >> "$vault_file"
    done
    
    # Create inventory file
    cat > "$inventory_file" << EOF
# Ansible Inventory File: $vault_name
# Created: $(date)

all:
  hosts:
EOF
    
    # Add hosts to inventory
    for host in "${hosts[@]}"; do
        cat >> "$inventory_file" << EOF
    $host:
      ansible_host: $host
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/id_rsa_$vault_name
EOF
    done
    
    # Add common variables
    cat >> "$inventory_file" << EOF
  vars:
    ansible_ssh_private_key_file: ~/.ssh/id_rsa_$vault_name
    ansible_user: root
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF
    
    # Create individual vault files for each host
    print_info "Creating vault files for each host..."
    for host in "${hosts[@]}"; do
        echo
        print_info "🔄 Creating vault for $host..."
        
        # Ask for vault content for each host
        read -p "Enter vault content for $host: " vault_content
        if [ -z "$vault_content" ]; then
            print_warning "Vault content is empty for $host, skipping..."
            continue
        fi
        
        # Create temporary file with content
        local temp_file=$(mktemp)
        cat > "$temp_file" << EOF
# Vault content for $host
# Created: $(date)

$vault_content
EOF
        
        # Create vault file using ansible-vault create
        local host_vault_file="$VAULT_DIR/$host.yml"
        
        if command -v ansible-vault &> /dev/null; then
            # Use ansible-vault create to encrypt the file
            if ansible-vault create "$host_vault_file" < "$temp_file"; then
                print_success "Created encrypted vault file: $host_vault_file"
            else
                print_error "Failed to create vault file for $host"
                rm -f "$temp_file"
                continue
            fi
        else
            # If ansible-vault not available, just copy the content
            cp "$temp_file" "$host_vault_file"
            print_success "Created plain text vault file: $host_vault_file"
        fi
        
        rm -f "$temp_file"
    done
    
    print_success "Vault files created:"
    echo "   Vault file: $vault_file"
    echo "   Inventory file: $inventory_file"
    echo "   Host vault files: ${#hosts[@]} files created in $VAULT_DIR/"
    
    return 0
}

# Function to load servers from file
load_servers_from_file() {
    local file_path="$1"
    local servers=()
    
    if [ ! -f "$file_path" ]; then
        print_error "File does not exist: $file_path"
        return 1
    fi
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
            servers+=("$line")
        fi
    done < "$file_path"
    
    echo "${servers[@]}"
}

# Function to show interactive menu
show_interactive_menu() {
    while true; do
        echo
        print_header "🚀 SSH Key Manager - Menu"
        echo "1. Generate SSH key"
        echo "2. Copy SSH key to servers from file"
        echo "3. Copy multiple files to server"
        echo "4. Create Ansible vault"
        echo "5. Exit"
        echo
        
        read -p "Choose option (1-5): " choice
        
        case $choice in
            1)
                read -p "Enter key name: " key_name
                if [ -n "$key_name" ]; then
                    generate_ssh_key "$key_name"
                fi
                ;;
            2)
                read -p "Enter existing key name: " key_name
                if [ -z "$key_name" ]; then
                    continue
                fi
                
                read -p "Enter servers file path: " servers_file
                if [ -f "$servers_file" ]; then
                    servers=($(load_servers_from_file "$servers_file"))
                    if [ ${#servers[@]} -gt 0 ]; then
                        copy_ssh_key_to_servers "$key_name" "${servers[@]}"
                    else
                        print_error "No servers found in file $servers_file"
                    fi
                else
                    print_error "Servers file not found: $servers_file"
                fi
                ;;
            3)
                read -p "Enter key name: " key_name
                if [ -z "$key_name" ]; then
                    continue
                fi
                
                copy_files_to_server "$key_name"
                ;;
            4)
                read -p "Enter vault name: " vault_name
                
                read -p "Enter hosts file path: " hosts_file
                if [ -f "$hosts_file" ]; then
                    hosts=($(load_servers_from_file "$hosts_file"))
                    if [ ${#hosts[@]} -gt 0 ]; then
                        create_ansible_vault "$vault_name" "${hosts[@]}"
                    else
                        print_error "No hosts found in file $hosts_file"
                    fi
                else
                    print_error "Hosts file not found: $hosts_file"
                fi
                ;;
            5)
                print_info "👋 Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid choice!"
                ;;
        esac
    done
}

# Function to show usage
show_usage() {
    cat << EOF
SSH Key Manager Script - Pure Bash Version

Usage: $0 [command] [options]

Commands:
  interactive                    Run in interactive mode
  create-key <key-name>         Generate SSH key
  copy-key-file <key-name> <file> Copy SSH key to servers from file
  copy-files <key-name> -f <files-list> Copy multiple files to server from file list
  create-vault-file <name> -f <hosts-file> Create Ansible vault from file
  help                          Show this help

Options:
  -f, --files-list <file>       Specify files list for copying
  -h, --hosts-file <file>       Specify hosts file for vault creation

Examples:
  $0 interactive
  $0 create-key my-key
  $0 copy-key-file my-key servers.txt
  $0 copy-files my-key -f files.txt
  $0 create-vault-file my-vault -f hosts.txt

File format (servers.txt or hosts.txt):
  10.10.10.10
  10.10.10.2
  # 10.10.10.3  # Comment lines
EOF
}

# Main function
main() {
    # Check dependencies
    check_dependencies
    
    # Setup SSH directory
    setup_ssh_directory
    
    # Parse command line arguments
    case "${1:-interactive}" in
        "interactive")
            show_interactive_menu
            ;;
        "create-key")
            if [ -z "$2" ]; then
                print_error "Please provide key name"
                show_usage
                exit 1
            fi
            generate_ssh_key "$2"
            ;;
        "copy-key-file")
            if [ -z "$2" ] || [ -z "$3" ]; then
                print_error "Please provide key name and server file"
                show_usage
                exit 1
            fi
            servers=($(load_servers_from_file "$3"))
            if [ ${#servers[@]} -gt 0 ]; then
                copy_ssh_key_to_servers "$2" "${servers[@]}"
            else
                print_error "Cannot read server list from file $3"
                exit 1
            fi
            ;;
        "copy-files")
            if [ -z "$2" ]; then
                print_error "Please provide key name"
                show_usage
                exit 1
            fi
            
            local key_name="$2"
            local files_list=""
            
            shift 2
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -f|--files-list)
                        if [ -z "$2" ]; then
                            print_error "Please provide files list path"
                            show_usage
                            exit 1
                        fi
                        files_list="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown option: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            
            if [ -z "$files_list" ]; then
                print_error "Please specify files list with -f option"
                show_usage
                exit 1
            fi
            
            copy_files_to_server "$key_name"
            ;;
        "create-vault-file")
            if [ -z "$2" ]; then
                print_error "Please provide vault name"
                show_usage
                exit 1
            fi
            
            # Parse options
            local vault_name="$2"
            local hosts_file=""
            
            shift 2
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -f|--hosts-file)
                        if [ -z "$2" ]; then
                            print_error "Please provide hosts file path"
                            show_usage
                            exit 1
                        fi
                        hosts_file="$2"
                        shift 2
                        ;;
                    *)
                        print_error "Unknown option: $1"
                        show_usage
                        exit 1
                        ;;
                esac
            done
            
            if [ -z "$hosts_file" ]; then
                print_error "Please specify hosts file with -f option"
                show_usage
                exit 1
            fi
            
            hosts=($(load_servers_from_file "$hosts_file"))
            if [ ${#hosts[@]} -gt 0 ]; then
                create_ansible_vault "$vault_name" "${hosts[@]}"
            else
                print_error "Cannot read host list from file $hosts_file"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Invalid command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 