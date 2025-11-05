#!/usr/bin/env bash
#
# SearXNG Automated Setup Script for Ubuntu 24.04
# This script automates the entire installation process including:
# - Network configuration (static IP, DNS)
# - Docker & Docker Compose installation
# - SearXNG deployment with multiple configuration options
# - mDNS/Avahi setup for local hostname resolution
#
# Usage: sudo bash searxng-setup.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/searxng-setup-$(date +%Y%m%d-%H%M%S).log"

# Global variables (will be set by user choices)
INSTALL_METHOD=""
STATIC_IP=""
NETMASK=""
GATEWAY=""
DNS_PRIMARY="8.8.8.8"
DNS_SECONDARY="8.8.4.4"
HOSTNAME_CHOICE=""
DOMAIN_NAME=""
LETSENCRYPT_EMAIL=""
SEARXNG_SECRET=""
NETWORK_INTERFACE=""

# Derived configuration
NETPLAN_RENDERER="networkd"

#######################################
# Helper Functions
#######################################

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

prompt_continue() {
    echo ""
    read -p "Press Enter to continue or Ctrl+C to abort..."
    echo ""
}

#######################################
# Prerequisite Checks
#######################################

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Check Ubuntu version
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu"
        exit 1
    fi
    
    log_info "Detected: $PRETTY_NAME"
    
    # Check internet connectivity
    log "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_error "No internet connectivity detected"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

#######################################
# Network Detection & Configuration
#######################################

detect_network_interface() {
    log "Detecting network interfaces..."
    
    # Get list of non-loopback interfaces
    local interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_error "No network interfaces found"
        exit 1
    fi
    
    if [[ ${#interfaces[@]} -eq 1 ]]; then
        NETWORK_INTERFACE="${interfaces[0]}"
        log_info "Using network interface: $NETWORK_INTERFACE"
    else
        echo ""
        echo "Multiple network interfaces detected:"
        for i in "${!interfaces[@]}"; do
            local iface="${interfaces[$i]}"
            local ip=$(ip -4 addr show "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            echo "  [$((i+1))] $iface ${ip:+(current IP: $ip)}"
        done
        echo ""
        read -p "Select interface [1-${#interfaces[@]}]: " choice
        NETWORK_INTERFACE="${interfaces[$((choice-1))]}"
        log_info "Selected interface: $NETWORK_INTERFACE"
    fi
}

scan_for_available_ip() {
    log "Scanning network for available IP addresses..."
    
    # Get current network info
    local current_ip=$(ip -4 addr show "$NETWORK_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    local current_cidr=$(ip -4 addr show "$NETWORK_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
    
    if [[ -z "$current_ip" ]]; then
        log_warn "No current IP detected on $NETWORK_INTERFACE"
        return 1
    fi
    
    log_info "Current IP: $current_cidr"
    
    # Extract network base and CIDR
    local network_base=$(echo "$current_ip" | cut -d. -f1-3)
    local cidr=$(echo "$current_cidr" | cut -d/ -f2)
    
    # Convert CIDR to netmask
    case $cidr in
        24) NETMASK="255.255.255.0" ;;
        16) NETMASK="255.255.0.0" ;;
        8) NETMASK="255.0.0.0" ;;
        *) NETMASK="255.255.255.0" ;;
    esac
    
    # Detect gateway
    GATEWAY=$(ip route | grep default | grep "$NETWORK_INTERFACE" | awk '{print $3}' | head -1)
    
    if [[ -z "$GATEWAY" ]]; then
        log_warn "Could not auto-detect gateway"
        GATEWAY="${network_base}.1"
    fi
    
    log_info "Detected gateway: $GATEWAY"
    log_info "Detected netmask: $NETMASK"
    
    # Suggest an IP (current + 10 or scan for free)
    local last_octet=$(echo "$current_ip" | cut -d. -f4)
    local suggested_ip="${network_base}.$((last_octet + 10))"
    
    echo ""
    echo "Network Configuration:"
    echo "  Current IP: $current_ip"
    echo "  Gateway: $GATEWAY"
    echo "  Netmask: $NETMASK"
    echo "  Suggested static IP: $suggested_ip"
    echo ""
    
    read -p "Use suggested IP ($suggested_ip)? [Y/n]: " use_suggested
    if [[ "$use_suggested" =~ ^[Nn] ]]; then
        read -p "Enter desired static IP: " STATIC_IP
    else
        STATIC_IP="$suggested_ip"
    fi
    
    # Confirm gateway and netmask
    read -p "Gateway [$GATEWAY]: " gw_input
    [[ -n "$gw_input" ]] && GATEWAY="$gw_input"
    
    read -p "Netmask [$NETMASK]: " nm_input
    [[ -n "$nm_input" ]] && NETMASK="$nm_input"
    
    read -p "Primary DNS [$DNS_PRIMARY]: " dns1_input
    [[ -n "$dns1_input" ]] && DNS_PRIMARY="$dns1_input"
    
    read -p "Secondary DNS [$DNS_SECONDARY]: " dns2_input
    [[ -n "$dns2_input" ]] && DNS_SECONDARY="$dns2_input"
    
    log_info "Network configuration set:"
    log_info "  IP: $STATIC_IP"
    log_info "  Gateway: $GATEWAY"
    log_info "  Netmask: $NETMASK"
    log_info "  DNS: $DNS_PRIMARY, $DNS_SECONDARY"
}

determine_netplan_renderer() {
    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        NETPLAN_RENDERER="NetworkManager"
    else
        NETPLAN_RENDERER="networkd"
    fi
    log_info "Using netplan renderer: $NETPLAN_RENDERER"
}

configure_static_ip() {
    log "Configuring static IP address..."
    
    # Backup existing netplan config
    local netplan_dir="/etc/netplan"
    local backup_dir="/etc/netplan.backup-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -d "$netplan_dir" ]]; then
        cp -r "$netplan_dir" "$backup_dir"
        log_info "Backed up netplan config to: $backup_dir"
        find "$netplan_dir" -maxdepth 1 -name '*.yaml' -type f -delete
    else
        install -d "$netplan_dir"
    fi
    
    # Create new netplan configuration
    local netplan_file="$netplan_dir/01-netcfg.yaml"

    determine_netplan_renderer

    cat > "$netplan_file" <<EOF
network:
  version: 2
  ethernets:
    $NETWORK_INTERFACE:
      renderer: $NETPLAN_RENDERER
      dhcp4: no
      addresses:
        - $STATIC_IP/$(netmask_to_cidr "$NETMASK")
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
          - $DNS_PRIMARY
          - $DNS_SECONDARY
EOF
    
    chmod 600 "$netplan_file"
    
    log_info "Created netplan configuration: $netplan_file"
    
    # Apply netplan
    log_warn "Applying network configuration. SSH connection may drop!"
    log_warn "If connection is lost, reconnect using: ssh user@$STATIC_IP"
    
    prompt_continue
    
    if command -v nmcli >/dev/null 2>&1; then
        nmcli device disconnect "$NETWORK_INTERFACE" >/dev/null 2>&1 || true
    fi

    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$NETWORK_INTERFACE" 2>/dev/null || true
    fi

    ip addr flush dev "$NETWORK_INTERFACE" 2>/dev/null || true

    netplan apply
    
    # Wait for network to stabilize
    sleep 5
    
    # Verify new IP
    local new_ip=$(ip -4 addr show "$NETWORK_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [[ "$new_ip" == "$STATIC_IP" ]]; then
        log "Static IP successfully configured: $STATIC_IP"
    else
        log_error "IP configuration may have failed. Current IP: $new_ip"
    fi
}

netmask_to_cidr() {
    local netmask=$1
    local cidr=0
    local IFS=.
    local -a octets=($netmask)
    
    for octet in "${octets[@]}"; do
        case $octet in
            255) ((cidr+=8)) ;;
            254) ((cidr+=7)) ;;
            252) ((cidr+=6)) ;;
            248) ((cidr+=5)) ;;
            240) ((cidr+=4)) ;;
            224) ((cidr+=3)) ;;
            192) ((cidr+=2)) ;;
            128) ((cidr+=1)) ;;
            0) ;;
        esac
    done
    
    echo $cidr
}

#######################################
# Installation Method Selection
#######################################

select_install_method() {
    echo ""
    echo "=========================================="
    echo "  SearXNG Installation Method"
    echo "=========================================="
    echo ""
    echo "Choose your installation method:"
    echo ""
    echo "  [1] Static IP Only (simplest)"
    echo "      Access via: https://$STATIC_IP"
    echo ""
    echo "  [2] Local Hostname with mDNS (recommended)"
    echo "      Access via: https://searxng.local"
    echo "      Requires: Avahi/mDNS configuration"
    echo ""
    echo "  [3] Public Domain with Let's Encrypt"
    echo "      Access via: https://yourdomain.com"
    echo "      Requires: Domain name, port forwarding"
    echo ""
    echo "  [4] Dual HTTP/HTTPS (best for software integration)"
    echo "      Browser: https://searxng.local"
    echo "      Software: http://searxng.local:8888"
    echo ""
    
    read -p "Select method [1-4]: " method_choice
    
    case $method_choice in
        1)
            INSTALL_METHOD="ip"
            HOSTNAME_CHOICE="$STATIC_IP"
            log_info "Selected: Static IP Only"
            ;;
        2)
            INSTALL_METHOD="mdns"
            read -p "Enter hostname (default: searxng): " hostname_input
            HOSTNAME_CHOICE="${hostname_input:-searxng}"
            log_info "Selected: Local Hostname ($HOSTNAME_CHOICE.local)"
            ;;
        3)
            INSTALL_METHOD="public"
            read -p "Enter your domain name (e.g., search.example.com): " DOMAIN_NAME
            read -p "Enter your email for Let's Encrypt: " LETSENCRYPT_EMAIL
            HOSTNAME_CHOICE="$DOMAIN_NAME"
            log_info "Selected: Public Domain ($DOMAIN_NAME)"
            ;;
        4)
            INSTALL_METHOD="dual"
            read -p "Enter hostname (default: searxng): " hostname_input
            HOSTNAME_CHOICE="${hostname_input:-searxng}"
            log_info "Selected: Dual HTTP/HTTPS ($HOSTNAME_CHOICE.local)"
            ;;
        *)
            log_error "Invalid selection"
            exit 1
            ;;
    esac
}

#######################################
# System Package Installation
#######################################

install_system_packages() {
    log "Installing system packages..."
    
    # Update package lists
    apt update
    
    # Install core utilities
    log "Installing core utilities..."
    apt install -y git bzip2 tar curl gnupg ca-certificates
    
    # Install build tools for kernel modules
    log "Installing build tools..."
    apt install -y build-essential dkms linux-headers-$(uname -r)
    
    log "System packages installed"
}

#######################################
# Docker Installation
#######################################

install_docker() {
    log "Installing Docker..."
    
    # Remove old Docker packages
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Add current user to docker group
    local actual_user="${SUDO_USER:-$USER}"
    if [[ "$actual_user" != "root" ]]; then
        usermod -aG docker "$actual_user"
        log_info "Added $actual_user to docker group"
    fi
    
    # Verify installation
    docker --version
    docker compose version
    
    log "Docker installed successfully"
}

#######################################
# Hostname & mDNS Configuration
#######################################

configure_hostname_mdns() {
    if [[ "$INSTALL_METHOD" == "mdns" ]] || [[ "$INSTALL_METHOD" == "dual" ]]; then
        log "Configuring hostname and mDNS..."
        
        # Set hostname
        hostnamectl set-hostname "$HOSTNAME_CHOICE"
        
        # Update /etc/hosts
        cat > /etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       $HOSTNAME_CHOICE
$STATIC_IP      $HOSTNAME_CHOICE $HOSTNAME_CHOICE.local

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF
        
        log_info "Updated /etc/hosts"
        
        # Install and configure Avahi
        log "Installing Avahi daemon..."
        apt install -y avahi-daemon avahi-utils
        
        # Start and enable Avahi
        systemctl start avahi-daemon
        systemctl enable avahi-daemon
        
        # Wait for Avahi to start
        sleep 2
        
        # Verify Avahi is advertising the correct hostname
        local avahi_status=$(systemctl status avahi-daemon | grep "running \[" || true)
        log_info "Avahi status: $avahi_status"
        
        log "Hostname and mDNS configured"
    fi
}

create_avahi_service() {
    if [[ "$INSTALL_METHOD" == "mdns" ]] || [[ "$INSTALL_METHOD" == "dual" ]]; then
        log "Creating Avahi service advertisement..."

        install -d /etc/avahi/services
        cat > /etc/avahi/services/searxng.service <<EOF
<?xml version="1.0" standalone='no'?><!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">$HOSTNAME_CHOICE SearXNG</name>
  <service>
    <type>_http._tcp</type>
    <port>8888</port>
  </service>
  <service>
    <type>_https._tcp</type>
    <port>443</port>
  </service>
</service-group>
EOF

        systemctl restart avahi-daemon
        log_info "Published mDNS services for HTTP (8888) and HTTPS (443)"
    fi
}

#######################################
# SearXNG Deployment
#######################################

deploy_searxng() {
    log "Deploying SearXNG..."
    
    local actual_user="${SUDO_USER:-$USER}"
    local user_home=$(eval echo ~$actual_user)
    local searxng_dir="$user_home/searxng"
    
    # Clone or update repository
    if [[ -d "$searxng_dir" ]]; then
        log_warn "SearXNG directory already exists, updating..."
        cd "$searxng_dir"
        sudo -u "$actual_user" git pull
    else
        log "Cloning SearXNG repository..."
        cd "$user_home"
        sudo -u "$actual_user" git clone https://github.com/searxng/searxng-docker.git searxng
        cd "$searxng_dir"
    fi
    
    # Generate secret key
    SEARXNG_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    log_info "Generated secret key"
    
    # Create .env file
    log "Creating .env configuration..."
    
    local base_url_protocol="https"
    local hostname_value="$HOSTNAME_CHOICE"
    
    if [[ "$INSTALL_METHOD" == "mdns" ]] || [[ "$INSTALL_METHOD" == "dual" ]]; then
        hostname_value="$HOSTNAME_CHOICE.local"
    fi
    
    if [[ "$INSTALL_METHOD" == "ip" ]]; then
        hostname_value="$STATIC_IP"
    fi
    
    cat > "$searxng_dir/.env" <<EOF
# SearXNG Configuration
SEARXNG_HOSTNAME=$hostname_value
SEARXNG_BASE_URL=$base_url_protocol://$hostname_value

# Ports
SEARXNG_PORT=8080
SEARXNG_BIND_ADDRESS=0.0.0.0:8080

EOF
    
    # Add Let's Encrypt email if public domain
    if [[ "$INSTALL_METHOD" == "public" ]]; then
        echo "# Let's Encrypt Configuration" >> "$searxng_dir/.env"
        echo "LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL" >> "$searxng_dir/.env"
        echo "" >> "$searxng_dir/.env"
    else
        echo "# If using Let's Encrypt (only if you have a public domain)" >> "$searxng_dir/.env"
        echo "# LETSENCRYPT_EMAIL=your-email@example.com" >> "$searxng_dir/.env"
        echo "" >> "$searxng_dir/.env"
    fi
    
    cat >> "$searxng_dir/.env" <<EOF
# Redis (leave defaults)
REDIS_URL=redis://redis:6379/0

# Limiter settings (optional)
LIMITER_ENABLED=false

# Instance settings
SEARXNG_SECRET=$SEARXNG_SECRET
EOF
    
    chown "$actual_user:$actual_user" "$searxng_dir/.env"
    log_info "Created .env file"
    
    # Update settings.yml
    log "Updating settings.yml..."
    
    cat > "$searxng_dir/searxng/settings.yml" <<EOF
# see https://docs.searxng.org/admin/settings/settings.html#settings-use-default-settings
use_default_settings: true
server:
  # base_url is defined in the SEARXNG_BASE_URL environment variable, see .env and docker-compose.yml
  secret_key: "$SEARXNG_SECRET"
  limiter: false  # enable this when running the instance for a public usage on the internet
  image_proxy: true
redis:
  url: redis://redis:6379/0
search:
  formats:
    - html
    - json
    - rss
    - text
EOF
    
    chown "$actual_user:$actual_user" "$searxng_dir/searxng/settings.yml"
    log_info "Updated settings.yml"
    
    # Prepare hostname for downstream configuration
    local caddy_hostname="$hostname_value"

    # Update docker-compose.yaml for dual HTTP/HTTPS or standard setup
    log "Configuring docker-compose.yaml..."
    
    if [[ "$INSTALL_METHOD" == "dual" ]] || [[ "$INSTALL_METHOD" == "ip" ]] || [[ "$INSTALL_METHOD" == "mdns" ]]; then
        # Add port 8888 mapping for HTTP access
        sed -i '/ports:/,/^[[:space:]]*[^[:space:]]/ {
            /- "127.0.0.1:8080:8080"/a\      - "8888:8080"
        }' "$searxng_dir/docker-compose.yaml" 2>/dev/null || true
        
        # If line doesn't exist, add it manually
        if ! grep -q '"8888:8080"' "$searxng_dir/docker-compose.yaml"; then
            # Find the searxng service ports section and add it
            awk '/searxng:/{flag=1} flag && /ports:/{print; print "      - \"8888:8080\""; flag=0; next} 1' \
                "$searxng_dir/docker-compose.yaml" > "$searxng_dir/docker-compose.yaml.tmp"
            mv "$searxng_dir/docker-compose.yaml.tmp" "$searxng_dir/docker-compose.yaml"
        fi
        
        log_info "Added port 8888 mapping for HTTP access"
    fi
    # Adjust Caddyfile depending on installation method
    local caddyfile_path="$searxng_dir/Caddyfile"
    if [[ "$INSTALL_METHOD" == "dual" ]]; then
        log "Updating Caddyfile for dual HTTP/HTTPS access..."
        cat > "$caddyfile_path" <<EOF
{
	admin off

	log {
		output stderr
		format filter {
			request>remote_ip ip_mask 8 32
			request>client_ip ip_mask 8 32
			request>remote_port delete
			request>headers delete
			request>uri query {
				delete url
				delete h
				delete q
			}
		}
	}

	servers {
		client_ip_headers X-Forwarded-For X-Real-IP
		trusted_proxies static private_ranges
		trusted_proxies_strict
	}
}

https://$caddy_hostname {
	tls internal
	encode zstd gzip

	@api {
		path /config
		path /healthz
		path /stats/errors
		path /stats/checker
	}

	@static {
		path /static/*
	}

	@imageproxy {
		path /image_proxy
	}

	header {
		Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; form-action 'self' https:; font-src 'self'; frame-ancestors 'self'; base-uri 'self'; connect-src 'self'; img-src * data:; frame-src https:;"
		Permissions-Policy "accelerometer=(),camera=(),geolocation=(),gyroscope=(),magnetometer=(),microphone=(),payment=(),usb=()"
		Referrer-Policy "same-origin"
		X-Content-Type-Options "nosniff"
		X-Robots-Tag "noindex, nofollow, noarchive, nositelinkssearchbox, nosnippet, notranslate, noimageindex"
		-Server
	}

	header @api {
		Access-Control-Allow-Methods "GET, OPTIONS"
		Access-Control-Allow-Origin "*"
	}

	route {
		header Cache-Control "no-cache"
		header @static Cache-Control "public, max-age=30, stale-while-revalidate=60"
		header @imageproxy Cache-Control "public, max-age=3600"
	}

	reverse_proxy 127.0.0.1:8080
}
EOF
    else
        if [[ -f "$caddyfile_path" ]] && grep -q "upgrade-insecure-requests;" "$caddyfile_path"; then
            log "Removing upgrade-insecure-requests directive from Caddyfile..."
            sed -i 's/Content-Security-Policy "upgrade-insecure-requests; \(.*\)/Content-Security-Policy "\1/' "$caddyfile_path"
        fi
    fi

    chown -R "$actual_user:$actual_user" "$searxng_dir"
    
    # Pull images and start containers
    log "Pulling Docker images..."
    cd "$searxng_dir"
    sudo -u "$actual_user" docker compose pull
    
    log "Starting SearXNG containers..."
    sudo -u "$actual_user" docker compose up -d
    
    # Wait for containers to start
    sleep 10
    
    # Check container status
    log "Checking container status..."
    sudo -u "$actual_user" docker compose ps
    
    log "SearXNG deployed successfully"
}

#######################################
# Post-Installation Verification
#######################################

verify_installation() {
    log "Verifying installation..."
    
    local actual_user="${SUDO_USER:-$USER}"
    local user_home=$(eval echo ~$actual_user)
    local searxng_dir="$user_home/searxng"
    
    cd "$searxng_dir"
    
    # Check if containers are running
    local running_containers=$(sudo -u "$actual_user" docker compose ps --format json | jq -r '.State' | grep -c "running" || echo "0")
    
    if [[ "$running_containers" -ge 3 ]]; then
        log "All containers are running"
    else
        log_warn "Some containers may not be running properly"
        sudo -u "$actual_user" docker compose ps
    fi
    
    # Test HTTP endpoint (port 8888)
    sleep 5
    log "Testing HTTP endpoint..."
    if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:8888" | grep -q "200\|301\|302"; then
        log "HTTP endpoint (port 8888) is responding"
    else
        log_warn "HTTP endpoint may not be ready yet"
    fi
    
    # Check logs for errors
    log "Checking for errors in logs..."
    local error_count=$(sudo -u "$actual_user" docker compose logs --tail=50 | grep -i "error" | wc -l)
    if [[ "$error_count" -gt 0 ]]; then
        log_warn "Found $error_count error messages in logs"
        log_info "Review logs with: cd ~/searxng && docker compose logs"
    fi
}

#######################################
# Final Summary
#######################################

print_summary() {
    echo ""
    echo "=========================================="
    echo "  SearXNG Installation Complete!"
    echo "=========================================="
    echo ""
    echo "Installation Details:"
    echo "  Method: $INSTALL_METHOD"
    echo "  Static IP: $STATIC_IP"
    echo "  Gateway: $GATEWAY"
    echo "  DNS: $DNS_PRIMARY, $DNS_SECONDARY"
    echo ""
    
    case $INSTALL_METHOD in
        ip)
            echo "Access URLs:"
            echo "  Browser (HTTPS): https://$STATIC_IP"
            echo "  Software (HTTP): http://$STATIC_IP:8888"
            ;;
        mdns|dual)
            echo "Access URLs:"
            echo "  Browser (HTTPS): https://$HOSTNAME_CHOICE.local"
            echo "  Software (HTTP): http://$HOSTNAME_CHOICE.local:8888"
            echo ""
            echo "Note: Accept the self-signed certificate warning in your browser"
            ;;
        public)
            echo "Access URLs:"
            echo "  Browser (HTTPS): https://$DOMAIN_NAME"
            echo ""
            echo "Note: Let's Encrypt certificate will be issued automatically"
            echo "      Allow 1-2 minutes for certificate generation"
            ;;
    esac
    
    echo ""
    echo "Management Commands:"
    echo "  View status:   cd ~/searxng && docker compose ps"
    echo "  View logs:     cd ~/searxng && docker compose logs -f"
    echo "  Restart:       cd ~/searxng && docker compose restart"
    echo "  Stop:          cd ~/searxng && docker compose down"
    echo "  Start:         cd ~/searxng && docker compose up -d"
    echo "  Update:        cd ~/searxng && docker compose pull && docker compose up -d"
    echo ""
    echo "Configuration Files:"
    echo "  Environment:   ~/searxng/.env"
    echo "  Settings:      ~/searxng/searxng/settings.yml"
    echo "  Compose:       ~/searxng/docker-compose.yaml"
    echo ""
    echo "Log file saved to: $LOG_FILE"
    echo ""
    echo "=========================================="
    echo ""
}

#######################################
# Main Execution Flow
#######################################

main() {
    clear
    echo ""
    echo "=========================================="
    echo "  SearXNG Automated Setup"
    echo "  Ubuntu 24.04"
    echo "=========================================="
    echo ""
    
    log "Starting SearXNG automated setup..."
    log "Log file: $LOG_FILE"
    
    # Step 1: Prerequisites
    check_prerequisites
    
    # Step 2: Network Configuration
    detect_network_interface
    
    echo ""
    read -p "Do you want to configure a static IP? [Y/n]: " configure_network
    if [[ ! "$configure_network" =~ ^[Nn] ]]; then
        scan_for_available_ip
        configure_static_ip
    else
        # Get current IP for later use
        STATIC_IP=$(ip -4 addr show "$NETWORK_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        log_info "Using current IP: $STATIC_IP"
    fi
    
    # Step 3: Select Installation Method
    select_install_method
    
    # Step 4: Install System Packages
    install_system_packages
    
    # Step 5: Install Docker
    install_docker
    
    # Step 6: Configure Hostname & mDNS (if needed)
    configure_hostname_mdns
    create_avahi_service
    
    # Step 7: Deploy SearXNG
    deploy_searxng
    
    # Step 8: Verify Installation
    verify_installation
    
    # Step 9: Print Summary
    print_summary
    
    log "Setup completed successfully!"
}

# Run main function
main "$@"
