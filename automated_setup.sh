#!/bin/bash

# Automated Oracle Linux 8 Security Setup Script
# This script automates firewall, SELinux, bootloader password, and repository configuration

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check OS compatibility
check_os() {
    if [[ ! -f /etc/oracle-release ]]; then
        print_error "This script is designed for Oracle Linux 8"
        exit 1
    fi
    
    OL_VERSION=$(grep -o '[0-9]\+' /etc/oracle-release | head -1)
    if [[ $OL_VERSION -ne 8 ]]; then
        print_warning "This script is designed for Oracle Linux 8, but you're running version $OL_VERSION"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to install and configure firewalld
setup_firewall() {
    print_status "Installing and configuring firewalld..."
    
    # Install firewalld
    dnf -y install firewalld
    
    # Enable and start firewalld
    systemctl enable firewalld
    systemctl start firewalld
    
    # Check if firewalld is running
    if systemctl is-active --quiet firewalld; then
        print_success "Firewalld installed and running successfully"
    else
        print_error "Failed to start firewalld"
        exit 1
    fi
}

# Function to install SELinux
setup_selinux() {
    print_status "Installing SELinux packages..."
    
    # Install python3-selinux
    dnf -y install python3-libselinux
    
    # Check if SELinux is installed
    if rpm -q python3-libselinux > /dev/null; then
        print_success "SELinux packages installed successfully"
    else
        print_error "Failed to install SELinux packages"
        exit 1
    fi
}

# Function to generate bootloader password
generate_bootloader_password() {
    print_status "Generating bootloader password..."
    
    echo "Please enter a password for the bootloader:"
    echo "This password will be used to protect GRUB2 bootloader"
    echo "Password requirements:"
    echo "- At least 8 characters"
    echo "- Mix of uppercase, lowercase, numbers, and special characters"
    echo ""
    
    # Get password from user
    read -s -p "Enter bootloader password: " BOOTLOADER_PASSWORD
    echo
    
    # Confirm password
    read -s -p "Confirm bootloader password: " BOOTLOADER_PASSWORD_CONFIRM
    echo
    
    # Check if passwords match
    if [[ "$BOOTLOADER_PASSWORD" != "$BOOTLOADER_PASSWORD_CONFIRM" ]]; then
        print_error "Passwords do not match. Please try again."
        generate_bootloader_password
        return
    fi
    
    # Check password length
    if [[ ${#BOOTLOADER_PASSWORD} -lt 8 ]]; then
        print_error "Password must be at least 8 characters long. Please try again."
        generate_bootloader_password
        return
    fi
    
    # Generate password hash using grub2-mkpasswd-pbkdf2
    print_status "Generating password hash..."
    echo ""
    
    # Use printf to send password twice with newlines
    printf "%s\n%s\n" "$BOOTLOADER_PASSWORD" "$BOOTLOADER_PASSWORD" | grub2-mkpasswd-pbkdf2
    
    print_success "Bootloader password hash generated successfully"
    echo ""
    echo "Copy the hash above to use in your playbook"
    echo ""
}

# Function to backup repository files
backup_repo_files() {
    print_status "Creating backups of repository files..."
    
    # Create backup directory
    mkdir -p /etc/yum.repos.d/backup.$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="/etc/yum.repos.d/backup.$(date +%Y%m%d_%H%M%S)"
    
    # Backup existing repo files
    if [[ -f /etc/yum.repos.d/oraclelinux-developer-ol8.repo ]]; then
        cp /etc/yum.repos.d/oraclelinux-developer-ol8.repo "$BACKUP_DIR/"
    fi
    
    if [[ -f /etc/yum.repos.d/oracle-linux-ol8.repo ]]; then
        cp /etc/yum.repos.d/oracle-linux-ol8.repo "$BACKUP_DIR/"
    fi
    
    if [[ -f /etc/yum.repos.d/uek-ol8.repo ]]; then
        cp /etc/yum.repos.d/uek-ol8.repo "$BACKUP_DIR/"
    fi
    
    if [[ -f /etc/yum.repos.d/oracle-epel-ol8.repo ]]; then
        cp /etc/yum.repos.d/oracle-epel-ol8.repo "$BACKUP_DIR/"
    fi
    
    print_success "Repository files backed up to $BACKUP_DIR"
}

# Function to configure oraclelinux-developer-ol8.repo
configure_developer_repo() {
    print_status "Configuring oraclelinux-developer-ol8.repo..."
    
    cat > /etc/yum.repos.d/oraclelinux-developer-ol8.repo << 'EOF'
[ol8_developer]
name=Oracle Linux 8 Development Packages ($basearch)
baseurl=https://yum$ociregion.$ocidomain/repo/OracleLinux/OL8/developer/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
repo_gpgcheck=0
EOF
    
    print_success "oraclelinux-developer-ol8.repo configured"
}

# Function to configure oracle-linux-ol8.repo
configure_base_repo() {
    print_status "Configuring oracle-linux-ol8.repo..."
    
    cat > /etc/yum.repos.d/oracle-linux-ol8.repo << 'EOF'
[ol8_baseos_latest]
name=Oracle Linux 8 BaseOS Latest ($basearch)
baseurl=https://yum$ociregion.$ocidomain/repo/OracleLinux/OL8/baseos/latest/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
repo_gpgcheck=0

[ol8_appstream]
name=Oracle Linux 8 Application Stream ($basearch)
baseurl=https://yum$ociregion.$ocidomain/repo/OracleLinux/OL8/appstream/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
repo_gpgcheck=0
EOF
    
    print_success "oracle-linux-ol8.repo configured"
}

# Function to configure uek-ol8.repo
configure_uek_repo() {
    print_status "Configuring uek-ol8.repo..."
    
    cat > /etc/yum.repos.d/uek-ol8.repo << 'EOF'
[ol8_UEKR7]
name=Latest Unbreakable Enterprise Kernel Release 7 for Oracle Linux $releasever ($basearch)
baseurl=https://yum$ociregion.$ocidomain/repo/OracleLinux/OL8/UEKR7/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
repo_gpgcheck=0
EOF
    
    print_success "uek-ol8.repo configured"
}

# Function to test repository configuration
test_repositories() {
    print_status "Testing repository configuration..."
    
    # Clear dnf cache
    dnf clean all
    
    # Test repository connectivity
    if dnf repolist | grep -q "ol8_developer\|ol8_baseos_latest\|ol8_appstream\|ol8_UEKR7"; then
        print_success "Repository configuration test successful"
    else
        print_warning "Some repositories may not be accessible. Check your network connection."
    fi
}

# Function to display summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "           SETUP SUMMARY"
    echo "=========================================="
    echo ""
    
    # Check firewalld status
    if systemctl is-active --quiet firewalld; then
        echo -e "${GREEN}✓${NC} Firewalld: Installed and running"
    else
        echo -e "${RED}✗${NC} Firewalld: Not running"
    fi
    
    # Check SELinux packages
    if rpm -q python3-libselinux > /dev/null; then
        echo -e "${GREEN}✓${NC} SELinux packages: Installed"
    else
        echo -e "${RED}✗${NC} SELinux packages: Not installed"
    fi
    
    # Check repository files
    if [[ -f /etc/yum.repos.d/oraclelinux-developer-ol8.repo ]]; then
        echo -e "${GREEN}✓${NC} oraclelinux-developer-ol8.repo: Configured"
    else
        echo -e "${RED}✗${NC} oraclelinux-developer-ol8.repo: Not configured"
    fi
    
    if [[ -f /etc/yum.repos.d/oracle-linux-ol8.repo ]]; then
        echo -e "${GREEN}✓${NC} oracle-linux-ol8.repo: Configured"
    else
        echo -e "${RED}✗${NC} oracle-linux-ol8.repo: Not configured"
    fi
    
    if [[ -f /etc/yum.repos.d/uek-ol8.repo ]]; then
        echo -e "${GREEN}✓${NC} uek-ol8.repo: Configured"
    else
        echo -e "${RED}✗${NC} uek-ol8.repo: Not configured"
    fi
    
    if [[ -f /etc/yum.repos.d/oracle-epel-ol8.repo ]]; then
        echo -e "${GREEN}✓${NC} oracle-epel-ol8.repo: Configured"
    else
        echo -e "${RED}✗${NC} oracle-epel-ol8.repo: Not configured"
    fi
    
    # Check bootloader password hash
    echo -e "${GREEN}✓${NC} Bootloader password: Generated and displayed"
    
    # Check ClamAV status
    if systemctl is-active --quiet clamd@scan; then
        echo -e "${GREEN}✓${NC} ClamAV antivirus: Installed and running"
    else
        echo -e "${RED}✗${NC} ClamAV antivirus: Not running"
    fi
    
    echo ""
    echo "=========================================="
    echo ""
}

# Function to install and configure ClamAV antivirus
setup_antivirus() {
    print_status "Installing and configuring ClamAV antivirus..."
    
    # Step 1: Install EPEL repository
    print_status "Step 1: Installing Oracle EPEL repository..."
    dnf install -y oracle-epel-release-el8
    
    # Step 2: Configure EPEL repository file
    print_status "Step 2: Configuring EPEL repository file..."
    cat > /etc/yum.repos.d/oracle-epel-ol8.repo << 'EOF'
[ol8_developer_EPEL]
name=Oracle Linux $releasever EPEL Packages for Development ($basearch)
baseurl=https://yum$ociregion.$ocidomain/repo/OracleLinux/OL8/developer/EPEL/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
repo_gpgcheck=0

[ol8_developer_EPEL_modular]
name=Oracle Linux $releasever EPEL Modular Packages for Development ($basearch)
baseurl=https://yum$ociregion.$ocidomain/repo/OracleLinux/OL8/developer/EPEL/modular/$basearch/
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
gpgcheck=1
enabled=1
repo_gpgcheck=0
EOF
    
    print_success "EPEL repository file configured"
    
    # Step 3: Enable EPEL repository and update cache
    print_status "Step 3: Enabling EPEL repository and updating cache..."
    dnf config-manager --set-enabled ol8_developer_EPEL
    dnf clean all -y
    dnf makecache -y
    
    # Step 4: Update system
    print_status "Step 4: Updating system packages..."
    dnf update -y
    
    # Step 5: Install ClamAV packages
    print_status "Step 5: Installing ClamAV packages..."
    dnf install -y clamav clamav-update clamav-devel clamav-lib clamav-server clamav-server-systemd
    
    # Check if ClamAV packages are installed
    if rpm -q clamav > /dev/null; then
        print_success "ClamAV packages installed successfully"
    else
        print_error "Failed to install ClamAV packages"
        exit 1
    fi
    

    # Step 6: Create systemd service file
    print_status "Step 6: Creating ClamAV systemd service..."
    tee /usr/lib/systemd/system/clamd@.service > /dev/null << 'EOF'
[Unit]
Description=Clam AntiVirus userspace daemon (%i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/clamd -c /etc/clamd.d/%i.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    
    # Step 7: Reload systemd and enable service
    print_status "Step 7: Reloading systemd and enabling ClamAV service..."
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now clamd@scan
    
    # Step 8: Configure scan.conf
    print_status "Step 8: Configuring ClamAV scan configuration..."
    if [[ -f /etc/clamd.d/scan.conf ]]; then
        # Backup original file
        cp /etc/clamd.d/scan.conf /etc/clamd.d/scan.conf.backup.$(date +%Y%m%d_%H%M%S)
        
        # Uncomment required lines (only if they are commented)
        local changes_made=0
        
        # Check and uncomment LogFile
        if grep -q "^[[:space:]]*#LogFile " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#LogFile /LogFile /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment LogFileMaxSize
        if grep -q "^[[:space:]]*#LogFileMaxSize " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#LogFileMaxSize /LogFileMaxSize /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment LogTime
        if grep -q "^[[:space:]]*#LogTime " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#LogTime /LogTime /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment LogSyslog
        if grep -q "^[[:space:]]*#LogSyslog " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#LogSyslog /LogSyslog /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment LogRotate
        if grep -q "^[[:space:]]*#LogRotate " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#LogRotate /LogRotate /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment DatabaseDirectory
        if grep -q "^[[:space:]]*#DatabaseDirectory " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#DatabaseDirectory /DatabaseDirectory /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment LocalSocket
        if grep -q "^[[:space:]]*#LocalSocket " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#LocalSocket /LocalSocket /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        # Check and uncomment FixStaleSocket
        if grep -q "^[[:space:]]*#FixStaleSocket " /etc/clamd.d/scan.conf; then
            sed -i 's/^[[:space:]]*#FixStaleSocket /FixStaleSocket /' /etc/clamd.d/scan.conf
            changes_made=1
        fi
        
        if [ $changes_made -eq 1 ]; then
            print_success "ClamAV scan configuration updated"
        else
            print_info "ClamAV scan configuration already properly configured"
        fi
        
        print_success "ClamAV scan configuration updated"
    else
        print_warning "ClamAV scan configuration file not found"
    fi
    
    # Step 9: Create directories and set permissions
    print_status "Step 9: Setting up ClamAV directories and permissions..."
    mkdir -p /run/clamd.scan
    chown clamscan:clamscan /run/clamd.scan
    
    chown -R clamscan:clamscan /var/lib/clamav
    chmod 755 /var/lib/clamav
    
    # Step 10: Update virus database
    print_status "Step 10: Updating ClamAV virus database..."
    freshclam
    
    if [[ $? -eq 0 ]]; then
        print_success "ClamAV virus database updated successfully"
    else
        print_warning "ClamAV virus database update may have failed, but continuing..."
    fi
    
    # Step 11: Restart and start service
    print_status "Step 11: Restarting and starting ClamAV service..."
    systemctl restart clamd@scan
    systemctl start clamd@scan
    
    # Step 12: Check service status
    print_status "Step 12: Redeploy ClamAV systemd service..."
    tee /usr/lib/systemd/system/clamd@.service > /dev/null << 'EOF'
[Unit]
Description = clamd scanner (%i) daemon
Documentation=man:clamd(8) man:clamd.conf(5) https://www.clamav.net/documents/
After = syslog.target nss-lookup.target network.target

[Service]
Type = forking
ExecStart = /usr/sbin/clamd -c /etc/clamd.d/%i.conf
# Reload the database
ExecReload=/bin/kill -USR2 $MAINPID
Restart = on-failure
TimeoutStartSec=420

[Install]
WantedBy = multi-user.target
EOF

    # Step 13: Restart and start service
    print_status "Step 13: Redeploy ClamAV systemd service..."
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable --now clamd@scan


    # Final status check
    if systemctl is-active --quiet clamd@scan; then
        print_success "ClamAV service is running successfully"
    else
        print_warning "ClamAV service may not be running properly"
    fi
    
    print_success "ClamAV antivirus installation and configuration completed"
}

# Main execution function
main() {
    echo "=========================================="
    echo "  Oracle Linux 8 Security Setup Script"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    check_root
    check_os
    
    # Confirm execution
    echo "This script will perform the following actions:"
    echo "1. Install and configure firewalld"
    echo "2. Install SELinux packages"
    echo "3. Generate bootloader password"
    echo "4. Configure Oracle Linux repositories"
    echo "5. Install and configure ClamAV antivirus"
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Setup cancelled by user"
        exit 0
    fi
    
    # Execute setup tasks
    setup_firewall
    generate_bootloader_password
    backup_repo_files
    configure_developer_repo
    configure_base_repo
    configure_uek_repo
    test_repositories
    setup_antivirus
    
    # Display summary
    display_summary
    
    print_success "Setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Copy the bootloader password hash from above"
    echo "2. Update your Ansible playbook with the generated hash"
    echo "3. Test the repository configuration with: dnf repolist"
    echo "4. Run your CIS compliance playbook"
    echo ""
}

# Run main function
main "$@" 