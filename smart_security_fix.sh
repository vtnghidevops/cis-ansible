#!/bin/bash

# Smart Security Fix Script
# Author: DevOps Team
# Version: 2.0
# Description: Check, preview, and fix logrotate rotate values and password quality settings

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}===== [SECURITY] $1 =====${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_section() {
    echo -e "\n${PURPLE}🔍 $1${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check current logrotate status and return files to fix
check_logrotate_status() {
    local total_files=0
    local compliant_files=0
    local non_compliant_files=0
    local files_to_fix=()
    
    # Check main logrotate.conf
    if [ -f "/etc/logrotate.conf" ]; then
        rotate_value=$(grep "^[[:space:]]*rotate[[:space:]]" "/etc/logrotate.conf" | head -1 | awk '{print $2}')
        if [ -n "$rotate_value" ]; then
            if [ "$rotate_value" -ge 13 ]; then
                compliant_files=$((compliant_files + 1))
            else
                non_compliant_files=$((non_compliant_files + 1))
                files_to_fix+=("/etc/logrotate.conf:$rotate_value")
            fi
        fi
        total_files=$((total_files + 1))
    fi
    
    # Check logrotate.d directory
    if [ -d "/etc/logrotate.d" ]; then
        for file in /etc/logrotate.d/*; do
            if [ -f "$file" ] && [ -r "$file" ]; then
                total_files=$((total_files + 1))
                rotate_value=$(grep "^[[:space:]]*rotate[[:space:]]" "$file" | head -1 | awk '{print $2}')
                
                if [ -n "$rotate_value" ]; then
                    if [ "$rotate_value" -ge 13 ]; then
                        compliant_files=$((compliant_files + 1))
                    else
                        non_compliant_files=$((non_compliant_files + 1))
                        files_to_fix+=("$file:$rotate_value")
                    fi
                fi
            fi
        done
    fi
    
    # Return files to fix
    echo "${files_to_fix[@]}"
}

# Function to check password quality configuration
check_password_quality() {
    local pwquality_file="/etc/security/pwquality.conf"
    local needs_fix=0
    local current_settings=()
    
    if [ -f "$pwquality_file" ]; then
        # Check each required setting
        local settings=("dcredit" "ucredit" "lcredit" "ocredit" "minclass")
        local expected_values=("-1" "-1" "-1" "-1" "4")
        
        for i in "${!settings[@]}"; do
            local setting="${settings[$i]}"
            local expected="${expected_values[$i]}"
            
            # Get current value (commented or uncommented)
            local current_line=$(grep "^[[:space:]]*#\?[[:space:]]*${setting}[[:space:]]*=" "$pwquality_file" | head -1)
            
            if [ -n "$current_line" ]; then
                # Check if line is commented
                if echo "$current_line" | grep -q "^[[:space:]]*#"; then
                    current_settings+=("$setting:commented")
                    needs_fix=1
                else
                    # Check if value matches expected
                    local current_value=$(echo "$current_line" | awk -F'=' '{print $2}' | tr -d ' ')
                    if [ "$current_value" = "$expected" ]; then
                        current_settings+=("$setting:$current_value:OK")
                    else
                        current_settings+=("$setting:$current_value:needs_update")
                        needs_fix=1
                    fi
                fi
            else
                current_settings+=("$setting:not_found")
                needs_fix=1
            fi
        done
    else
        needs_fix=1
    fi
    
    # Return status
    echo "$needs_fix:${current_settings[*]}"
}

# Function to display current status
display_current_status() {
    print_header "Current Status Check"
    
    # Logrotate status
    print_section "Logrotate Configuration"
    local total_files=0
    local compliant_files=0
    local non_compliant_files=0
    
    # Check main logrotate.conf
    if [ -f "/etc/logrotate.conf" ]; then
        rotate_value=$(grep "^[[:space:]]*rotate[[:space:]]" "/etc/logrotate.conf" | head -1 | awk '{print $2}')
        if [ -n "$rotate_value" ]; then
            if [ "$rotate_value" -ge 13 ]; then
                print_success "Main config: rotate = $rotate_value (OK)"
                compliant_files=$((compliant_files + 1))
            else
                print_warning "Main config: rotate = $rotate_value (needs update)"
                non_compliant_files=$((non_compliant_files + 1))
            fi
        else
            print_warning "Main config: No rotate directive found"
        fi
        total_files=$((total_files + 1))
    else
        print_error "Main config: File not found"
    fi
    
    # Check logrotate.d directory
    if [ -d "/etc/logrotate.d" ]; then
        for file in /etc/logrotate.d/*; do
            if [ -f "$file" ] && [ -r "$file" ]; then
                total_files=$((total_files + 1))
                rotate_value=$(grep "^[[:space:]]*rotate[[:space:]]" "$file" | head -1 | awk '{print $2}')
                
                if [ -n "$rotate_value" ]; then
                    if [ "$rotate_value" -ge 13 ]; then
                        print_success "$(basename "$file"): rotate = $rotate_value (OK)"
                        compliant_files=$((compliant_files + 1))
                    else
                        print_warning "$(basename "$file"): rotate = $rotate_value (needs update)"
                        non_compliant_files=$((non_compliant_files + 1))
                    fi
                fi
            fi
        done
    fi
    
    print_info "Logrotate: $compliant_files compliant, $non_compliant_files need update"
    
    # Password quality status
    print_section "Password Quality Configuration"
    local pwquality_result=$(check_password_quality)
    IFS=':' read -r needs_fix settings_str <<< "$pwquality_result"
    IFS=' ' read -ra settings <<< "$settings_str"
    
    for setting_info in "${settings[@]}"; do
        IFS=':' read -r setting value status <<< "$setting_info"
        case $status in
            "OK")
                print_success "$setting = $value (OK)"
                ;;
            "commented")
                print_warning "$setting: commented out (needs uncomment)"
                ;;
            "needs_update")
                print_warning "$setting = $value (needs update)"
                ;;
            "not_found")
                print_error "$setting: not found (needs add)"
                ;;
        esac
    done
    
    if [ "$needs_fix" -eq 1 ]; then
        print_warning "Password quality configuration needs fixes"
    else
        print_success "Password quality configuration is compliant"
    fi
}

# Function to show preview of changes
show_preview() {
    local files_to_fix=("$@")
    
    print_header "Preview Changes"
    
    # Logrotate changes
    if [ ${#files_to_fix[@]} -gt 0 ]; then
        print_section "Logrotate Changes"
        echo -e "${YELLOW}The following logrotate files will be updated:${NC}\n"
        
        for file_info in "${files_to_fix[@]}"; do
            IFS=':' read -r file current_value <<< "$file_info"
            
            echo -e "${CYAN}File: $file${NC}"
            echo -e "  Current: rotate = $current_value"
            echo -e "  Change:  rotate = 13"
            echo ""
        done
    fi
    
    # Password quality changes
    print_section "Password Quality Changes"
    echo -e "${YELLOW}The following password quality settings will be configured:${NC}\n"
    echo -e "${CYAN}File: /etc/security/pwquality.conf${NC}"
    echo -e "  dcredit = -1 (minimum 1 digit)"
    echo -e "  ucredit = -1 (minimum 1 uppercase)"
    echo -e "  lcredit = -1 (minimum 1 lowercase)"
    echo -e "  ocredit = -1 (minimum 1 special character)"
    echo -e "  minclass = 4 (all 4 character classes required)"
    echo -e "  Backup:  /etc/security/pwquality.conf.backup.$(date +%Y%m%d_%H%M%S)"
    echo ""
}

# Function to apply logrotate fixes
apply_logrotate_fixes() {
    local files_to_fix=("$@")
    
    print_header "Applying Logrotate Fixes"
    
    local success_count=0
    local error_count=0
    
    for file_info in "${files_to_fix[@]}"; do
        IFS=':' read -r file current_value <<< "$file_info"
        
        print_info "Processing: $file"
        
        # Apply fix
        if sed -i "s/^\([[:space:]]*rotate[[:space:]]\+\)[0-9]\+/\113/" "$file"; then
            # Verify change
            new_value=$(grep "^[[:space:]]*rotate[[:space:]]" "$file" | head -1 | awk '{print $2}')
            if [ "$new_value" = "13" ]; then
                print_success "Updated: rotate $current_value → 13"
                success_count=$((success_count + 1))
            else
                print_error "Verification failed: expected 13, got $new_value"
                error_count=$((error_count + 1))
            fi
        else
            print_error "Failed to update: $file"
            error_count=$((error_count + 1))
        fi
    done
    
    print_section "Logrotate Fix Summary"
    print_success "Successfully updated: $success_count"
    if [ $error_count -gt 0 ]; then
        print_error "Errors: $error_count"
    fi
}

# Function to apply password quality fixes
apply_password_quality_fixes() {
    print_header "Applying Password Quality Fixes"
    
    local pwquality_file="/etc/security/pwquality.conf"
    local backup_file="${pwquality_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup
    if cp "$pwquality_file" "$backup_file" 2>/dev/null; then
        print_success "Backup created: $(basename "$backup_file")"
    else
        print_error "Failed to backup password quality file"
        return 1
    fi
    
    # Apply fixes
    local success_count=0
    
    # Uncomment and set dcredit
    if sed -i 's/^[[:space:]]*#[[:space:]]*dcredit[[:space:]]*=[[:space:]]*.*/dcredit = -1/' "$pwquality_file"; then
        print_success "Set dcredit = -1"
        success_count=$((success_count + 1))
    fi
    
    # Uncomment and set ucredit
    if sed -i 's/^[[:space:]]*#[[:space:]]*ucredit[[:space:]]*=[[:space:]]*.*/ucredit = -1/' "$pwquality_file"; then
        print_success "Set ucredit = -1"
        success_count=$((success_count + 1))
    fi
    
    # Uncomment and set lcredit
    if sed -i 's/^[[:space:]]*#[[:space:]]*lcredit[[:space:]]*=[[:space:]]*.*/lcredit = -1/' "$pwquality_file"; then
        print_success "Set lcredit = -1"
        success_count=$((success_count + 1))
    fi
    
    # Uncomment and set ocredit
    if sed -i 's/^[[:space:]]*#[[:space:]]*ocredit[[:space:]]*=[[:space:]]*.*/ocredit = -1/' "$pwquality_file"; then
        print_success "Set ocredit = -1"
        success_count=$((success_count + 1))
    fi
    
    # Uncomment and set minclass
    if sed -i 's/^[[:space:]]*#[[:space:]]*minclass[[:space:]]*=[[:space:]]*.*/minclass = 4/' "$pwquality_file"; then
        print_success "Set minclass = 4"
        success_count=$((success_count + 1))
    fi
    
    print_section "Password Quality Fix Summary"
    print_success "Successfully configured: $success_count settings"
}

# Function to remount filesystems
remount_filesystems() {
    print_header "Remounting Filesystems"
    
    local mount_points=("/home" "/tmp" "/var" "/var/log")
    local success_count=0
    local error_count=0
    
    for mount_point in "${mount_points[@]}"; do
        print_info "Remounting: $mount_point"
        
        if mount -o remount "$mount_point" 2>/dev/null; then
            print_success "Successfully remounted: $mount_point"
            success_count=$((success_count + 1))
        else
            print_warning "Failed to remount: $mount_point (may not be mounted or already remounted)"
            error_count=$((error_count + 1))
        fi
    done
    
    print_section "Remount Summary"
    print_success "Successfully remounted: $success_count"
    if [ $error_count -gt 0 ]; then
        print_warning "Warnings: $error_count (some filesystems may not need remounting)"
    fi
}

# Function to test configuration
test_configuration() {
    print_header "Testing Configuration"
    
    # Test logrotate configuration
    if command_exists logrotate; then
        if logrotate -d /etc/logrotate.conf >/dev/null 2>&1; then
            print_success "Logrotate configuration test passed"
        else
            print_warning "Logrotate configuration test failed - check syntax"
        fi
    else
        print_warning "Logrotate command not found - cannot test"
    fi
    
    # Test ClamAV antivirus status
    print_section "Checking ClamAV Antivirus Status"
    
    # Check if ClamAV is installed
    if command_exists clamscan; then
        print_success "ClamAV is installed"
        
        # Check if ClamAV daemon is running
        if systemctl is-active --quiet clamd@scan; then
            print_success "ClamAV daemon (clamd@scan) is running"
            
            # Check daemon status
            local daemon_status=$(systemctl is-active clamd@scan 2>/dev/null)
            print_info "Daemon status: $daemon_status"
            
            # Check if daemon is enabled
            if systemctl is-enabled --quiet clamd@scan; then
                print_success "ClamAV daemon is enabled (will start on boot)"
            else
                print_warning "ClamAV daemon is not enabled (won't start on boot)"
            fi
            
            # Test ClamAV functionality
            if command_exists freshclam; then
                print_info "Testing ClamAV virus database..."
                if freshclam --version >/dev/null 2>&1; then
                    print_success "ClamAV virus database is accessible"
                else
                    print_warning "ClamAV virus database may have issues"
                fi
            fi
            
        else
            print_error "ClamAV daemon (clamd@scan) is not running"
            print_info "Attempting to start ClamAV daemon..."
            
            if systemctl start clamd@scan 2>/dev/null; then
                print_success "ClamAV daemon started successfully"
            else
                print_error "Failed to start ClamAV daemon"
                print_info "Check ClamAV configuration and logs"
            fi
        fi
        
        # Check ClamAV socket
        if [ -S "/run/clamd.scan/clamd.sock" ]; then
            print_success "ClamAV socket exists and is accessible"
        else
            print_warning "ClamAV socket not found or not accessible"
        fi
        
    else
        print_warning "ClamAV is not installed"
        print_info "Consider installing ClamAV for antivirus protection"
    fi
    
    # Test mount options for security
    print_section "Checking Mount Options Security"
    
    local mount_points=("/home" "/tmp" "/var" "/var/log")
    local security_issues=0
    
    for mount_point in "${mount_points[@]}"; do
        print_info "Checking mount options for: $mount_point"
        
        # Get current mount options
        local mount_info=$(mount | grep " on $mount_point ")
        
        if [ -n "$mount_info" ]; then
            local has_nodev=0
            local has_nosuid=0
            
            # Check for nodev option
            if echo "$mount_info" | grep -q "nodev"; then
                has_nodev=1
            fi
            
            # Check for nosuid option
            if echo "$mount_info" | grep -q "nosuid"; then
                has_nosuid=1
            fi
            
            # Display results
            if [ $has_nodev -eq 1 ] && [ $has_nosuid -eq 1 ]; then
                print_success "$mount_point: nodev ✓, nosuid ✓"
            elif [ $has_nodev -eq 1 ]; then
                print_warning "$mount_point: nodev ✓, nosuid ✗ (missing)"
                security_issues=$((security_issues + 1))
            elif [ $has_nosuid -eq 1 ]; then
                print_warning "$mount_point: nodev ✗ (missing), nosuid ✓"
                security_issues=$((security_issues + 1))
            else
                print_error "$mount_point: nodev ✗ (missing), nosuid ✗ (missing)"
                security_issues=$((security_issues + 2))
            fi
        else
            print_warning "$mount_point: Not mounted or not found"
        fi
    done
    
    # Security summary
    print_section "Security Check Summary"
    if [ $security_issues -eq 0 ]; then
        print_success "All mount points have proper security options (nodev, nosuid)"
    else
        print_warning "Found $security_issues security issues with mount options"
        print_info "Consider adding nodev and nosuid options to /etc/fstab for better security"
    fi
}

# Main execution
main() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Smart Security Fix Script                     ║"
    echo "║                        Version 2.0                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
    
    # Step 1: Check current status
    print_info "Step 1: Checking current status..."
    display_current_status
    
    # Get files to fix for logrotate
    files_to_fix=($(check_logrotate_status))
    
    # Check password quality
    pwquality_result=$(check_password_quality)
    IFS=':' read -r pwquality_needs_fix <<< "$pwquality_result"
    
    # Step 2: Show preview
    print_info "Step 2: Showing preview of changes..."
    show_preview "${files_to_fix[@]}"
    
    # Step 3: Ask for confirmation
    if [ ${#files_to_fix[@]} -eq 0 ] && [ "$pwquality_needs_fix" -eq 0 ]; then
        echo -e "\n${GREEN}No changes needed! All configurations are already compliant.${NC}"
        exit 0
    fi
    
    echo -e "\n${YELLOW}Do you want to apply these changes? (y/N)${NC}"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled${NC}"
        exit 0
    fi
    
    # Step 4: Apply logrotate fixes
    if [ ${#files_to_fix[@]} -gt 0 ]; then
        print_info "Step 3: Applying logrotate fixes..."
        apply_logrotate_fixes "${files_to_fix[@]}"
    fi
    
    # Step 5: Apply password quality fixes
    if [ "$pwquality_needs_fix" -eq 1 ]; then
        print_info "Step 4: Applying password quality fixes..."
        apply_password_quality_fixes
    fi
    
    # Step 6: Remount filesystems
    print_info "Step 5: Remounting filesystems..."
    remount_filesystems
    
    # Step 7: Test configuration
    print_info "Step 6: Testing configuration..."
    test_configuration
    
    # Final summary
    echo -e "\n${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                    Security Fix Complete!                      ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "\n${YELLOW}Note: Backups created with .backup.YYYYMMDD_HHMMSS extension${NC}"
}

# Check if script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script should be run as root for complete functionality${NC}"
    echo -e "${YELLOW}Some operations may fail without root privileges${NC}\n"
fi

# Run main function
main "$@" 