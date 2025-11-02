# SearXNG Installation Guide for Ubuntu 24.04

**Updated: November 1, 2025**

A comprehensive guide for installing SearXNG in a VM with Ubuntu 24.04 on a local LAN, updated for Python 3.12 compatibility.

## Credits

Original instructions by **Roaster-Dude** on Reddit:  
https://www.reddit.com/r/Searx/comments/w7csyl/so_this_worked_for_me_searxng_in_a_vm_on_a_local/

This guide has been updated to address compatibility issues with Ubuntu 24.04 (Python 3.12) and Docker Compose V2.

---

## Overview

This guide walks you through setting up a SearXNG instance on Ubuntu 24.04 in a virtual machine. SearXNG is a privacy-respecting metasearch engine that aggregates results from multiple search engines without tracking you.

### System Requirements

- **VM Specs**: 4 vCPU, 8GB RAM, 120GB drive (adjust as needed)
- **OS**: Ubuntu 24.04 (Noble Numbat)
- **Network**: Static IP on your local LAN (e.g., 192.168.10.10/24)

> **Important**: Ubuntu 24.04 uses Python 3.12, which is incompatible with the old `docker-compose` package. This guide uses Docker Compose V2 to avoid compatibility issues.

---

## Choose Your Setup Method

Before starting, decide which setup method you want:

### 🏠 Method 1: Local Network with IP Address (Simplest)
- **Access via**: `https://192.168.10.10`
- **SSL**: Self-signed certificate (browser warning - accept once)
- **Requirements**: Just the VM with static IP
- **Best for**: Quick setup, no hostname needed
- **Follow**: All standard instructions, use IP in `.env` file

### 🌐 Method 2: Local Network with Hostname (Recommended)
- **Access via**: `https://searxng.local`
- **SSL**: Self-signed certificate (browser warning - accept once)
- **Requirements**: VM + mDNS (Avahi) configuration
- **Best for**: Easy-to-remember local access
- **Follow**: Standard instructions + hostname/mDNS setup (Section 4)

### 🌍 Method 3: Public Domain with Let's Encrypt (Advanced)
- **Access via**: `https://search.yourdomain.com`
- **SSL**: Trusted certificate (no browser warnings)
- **Requirements**: Domain name + port forwarding + public IP
- **Best for**: Internet-accessible search engine
- **Follow**: Standard instructions + Let's Encrypt setup (SSL Configuration section)

### 🔄 Method 4: Dual HTTP/HTTPS (Best for Software Integration + Browser)
- **Access via**: 
  - Browser: `https://searxng.local` (HTTPS with self-signed cert)
  - Software/API: `http://searxng.local:8888` (HTTP, no SSL issues)
- **SSL**: Self-signed for HTTPS, none for HTTP
- **Requirements**: VM + mDNS (Avahi) + Caddyfile configuration
- **Best for**: Using with third-party software that doesn't handle SSL well, while still having secure browser access
- **Follow**: Standard instructions + hostname/mDNS setup + Dual HTTP/HTTPS configuration

> **This guide covers all four methods.** Follow the base installation steps, then configure based on your chosen method.

---

## Initial Setup

### 1. Create the VM

Create an Ubuntu 24.04 virtual machine with your preferred hypervisor (VirtualBox, VMware, xcp-ng, etc.).

**Critical**: Set a **static IP address** for the VM that matches your network subnet. For example:
- IP: `192.168.10.10/24`
- Gateway: `192.168.10.1`
- DNS: `8.8.8.8, 8.8.4.4`

### 2. Connect via SSH

Use SSH to connect to your VM (e.g., PuTTY on Windows, Terminal on macOS/Linux):

```bash
ssh username@192.168.10.10
```

### 3. Verify Network Connectivity

**Before proceeding**, verify network connectivity and DNS resolution. This prevents repository connection errors:

```bash
# Test internet connectivity
ping -c 3 8.8.8.8

# If ping fails or you get DNS errors, fix DNS:
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo bash -c 'echo "nameserver 8.8.4.4" >> /etc/resolv.conf'

# Test DNS resolution
ping -c 3 google.com
```

### 4. Set the Hostname and Configure mDNS (Optional - Method 2 Only)

> **Skip this section if you're using Method 1 (IP address only) or Method 3 (public domain).**

To access your VM by hostname (`searxng.local`) without router or client configuration, set the hostname FIRST, then install Avahi for mDNS (Multicast DNS). This is completely self-contained within the VM.

#### Step 1: Set the Hostname

```bash
# Set the hostname to 'searxng'
sudo hostnamectl set-hostname searxng

# Verify the change
hostname
```

#### Step 2: Update /etc/hosts

```bash
sudo nano /etc/hosts
```

Make sure the file includes these lines (replace `192.168.10.10` with your VM's IP):

```
127.0.0.1       localhost
127.0.1.1       searxng
192.168.10.10   searxng searxng.local
```

Save and exit (Ctrl+X, then Y, then Enter).

#### Step 3: Install and Configure Avahi

```bash
# Install Avahi daemon
sudo apt install avahi-daemon avahi-utils

# Start and enable the service
sudo systemctl start avahi-daemon
sudo systemctl enable avahi-daemon

# Verify it's running - should show "avahi-daemon: running [searxng.local]"
sudo systemctl status avahi-daemon
```

**Important**: The status output should show `[searxng.local]` not `[SearxngOnUbuntu.local]`. If it shows the wrong hostname, you set the hostname AFTER installing Avahi. Fix it:

```bash
# Restart Avahi to pick up the new hostname
sudo systemctl restart avahi-daemon

# Verify again
sudo systemctl status avahi-daemon
```

#### Test from Other Machines

**Linux/macOS:**
```bash
ping searxng.local
```

**Windows:**
Windows doesn't support mDNS natively. You have two options:

1. **Install Bonjour Print Services** (free from Apple) - enables `.local` resolution
2. **Or manually add to hosts file** (one-time setup):
   - Open Notepad as Administrator
   - Open: `C:\Windows\System32\drivers\etc\hosts`
   - Add: `192.168.10.10   searxng.local`
   - Save and close

#### Access SearXNG by Hostname

Once configured, you can access SearXNG at:
- **`https://searxng.local`** (from Linux/macOS/Windows with Bonjour)
- **`https://192.168.10.10`** (always works as fallback)

> **Note**: The `.local` suffix is required for mDNS. This is automatic and requires no router or client changes. Linux and macOS support mDNS natively. Windows requires Bonjour Print Services (free) or a manual hosts file entry.

### 5. Update the System

```bash
sudo apt update
sudo apt upgrade
```

If you see errors about "unable to locate package" or repository connection failures, make sure DNS is working properly (see above).

**Reboot the VM:**

```bash
sudo reboot
```

---

## Install Required Packages

### 1. Navigate to /usr/local

```bash
cd /usr/local
```

### 2. Install Git and Docker

```bash
sudo apt install git
sudo apt install docker.io
```

> **Note**: Do NOT install the old `docker-compose` package - it's incompatible with Python 3.12.

### 3. Clone SearXNG Repository

```bash
sudo git clone https://github.com/searxng/searxng-docker.git
```

### 4. Navigate to the Directory

```bash
cd searxng-docker
```

You should now be in: `/usr/local/searxng-docker/`

---

## Configure SearXNG

### 1. Edit the Environment File

The `.env` file is hidden. Verify it exists:

```bash
ls -ah
```

Edit the file:

```bash
sudo nano .env
```

**Modify based on your chosen method:**

#### Method 1: IP Address Only
```
SEARXNG_HOSTNAME=192.168.10.10
# LETSENCRYPT_EMAIL=<email>
```

#### Method 2: Local Hostname (mDNS)
```
SEARXNG_HOSTNAME=searxng.local
# LETSENCRYPT_EMAIL=<email>
```

#### Method 3: Public Domain with Let's Encrypt
```
SEARXNG_HOSTNAME=search.yourdomain.com
LETSENCRYPT_EMAIL=your@email.com
```

#### Method 4: Dual HTTP/HTTPS
```
SEARXNG_HOSTNAME=searxng.local
# LETSENCRYPT_EMAIL=<email>
```

> **Note for Method 4**: You'll also need to edit the Caddyfile (see Dual HTTP/HTTPS Configuration section below).

Replace the IP address or domain with your actual values.

Save and exit (Ctrl+X, then Y, then Enter).

> **Note**: Methods 1 and 2 use self-signed certificates (browser warning). Method 3 uses Let's Encrypt (trusted certificate, no warnings).

### 2. Generate Secret Key

While still in `/usr/local/searxng-docker/`, run:

```bash
sudo sed -i "s|ultrasecretkey|$(openssl rand -hex 32)|g" searxng/settings.yml
```

This adds a randomly generated secret key to the `settings.yml` file in `/usr/local/searxng-docker/searxng/`.

---

## Install Docker Compose V2

Docker Compose V2 is compatible with Python 3.12. Install it using the direct binary method:

### 1. Create the CLI Plugins Directory

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
```

### 2. Download Docker Compose V2

```bash
sudo curl -SL https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
```

### 3. Make it Executable

```bash
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
```

### 4. Verify Installation

```bash
docker compose version
```

You should see output like: `Docker Compose version v2.24.5`

---

## Start SearXNG

### 1. Reboot (Optional but Recommended)

```bash
sudo reboot
```

### 2. Start Docker Containers

Log back in and navigate to the directory:

```bash
cd /usr/local/searxng-docker
```

Start Docker in the background:

```bash
# NOTE: Use "docker compose" (with space) instead of "docker-compose" (with hyphen)
# This is the new Docker Compose V2 syntax
sudo docker compose up -d
```

### 3. Verify Containers are Running

```bash
sudo docker ps
```

You should see the SearXNG containers running.

---

## Access SearXNG

Open a web browser on any machine on your network and navigate to your SearXNG instance based on your chosen method:

### Method 1: IP Address
```
https://192.168.10.10
```
Replace with your VM's IP address.

### Method 2: Local Hostname
```
https://searxng.local
```

### Method 3: Public Domain
```
https://search.yourdomain.com
```

### Method 4: Dual HTTP/HTTPS
**Browser access (HTTPS)**:
```
https://searxng.local
```

**Software/API access (HTTP)**:
```
http://searxng.local:8888
```

---

### Accepting Self-Signed Certificates (Methods 1, 2 & 4)

If you're using Method 1 or 2, you'll see a certificate warning on first access. This is **normal and safe** for local networks:

1. You'll see "Your connection is not private" or similar
2. Click **"Advanced"** or **"Show Details"**
3. Click **"Proceed to [address] (unsafe)"** or **"Accept the Risk and Continue"**
4. The warning appears only once per browser

The connection is still encrypted - the certificate just isn't signed by a public authority.

### No Certificate Warning (Method 3)

If you're using Method 3 with Let's Encrypt, there will be **no certificate warning** - the certificate is trusted by all browsers.

---

## SSL Configuration

### Option 1: Self-Signed Certificate (Local Network - Default)

If you configured `SEARXNG_HOSTNAME=searxng.local`, SearXNG automatically generates a self-signed SSL certificate. This is **secure for local network use** but browsers will show a warning.

**To accept the certificate:**
1. Navigate to `https://searxng.local`
2. Click "Advanced" or "Show Details"
3. Click "Proceed to searxng.local (unsafe)" or "Accept the Risk"
4. The warning appears only once per browser

**This is perfectly safe for local network use** - the connection is encrypted, but the certificate isn't signed by a trusted authority.

---

### Option 2: Let's Encrypt SSL (Public Domain Required)

To use Let's Encrypt for a **trusted SSL certificate**, you need:
1. A **public domain name** (e.g., `search.yourdomain.com`)
2. Port **80 and 443** forwarded from your router to the VM
3. The domain pointing to your **public IP address**

> **Important**: Let's Encrypt does NOT work with `.local` addresses or private IP addresses. It requires a publicly accessible domain.

#### Setup Steps:

1. **Get a domain name** (from Namecheap, Cloudflare, etc.)

2. **Configure DNS**: Point your domain to your public IP
   ```
   A Record: search.yourdomain.com → Your.Public.IP.Address
   ```

3. **Port forward on your router**:
   - Port 80 (HTTP) → VM IP:80
   - Port 443 (HTTPS) → VM IP:443

4. **Update SearXNG configuration**:
   ```bash
   cd /usr/local/searxng-docker
   sudo nano .env
   ```
   
   Change to:
   ```
   SEARXNG_HOSTNAME=search.yourdomain.com
   LETSENCRYPT_EMAIL=your@email.com
   ```

5. **Restart SearXNG**:
   ```bash
   sudo docker compose down
   sudo docker compose up -d
   ```

6. **Wait 1-2 minutes** for Let's Encrypt to issue the certificate

7. **Access via**: `https://search.yourdomain.com`

Let's Encrypt will automatically renew the certificate every 90 days.

---

### Option 3: Dual HTTP/HTTPS Configuration (Method 4)

This configuration allows simultaneous access via:
- **HTTPS on port 443** for secure browser access
- **HTTP on port 8888** for third-party software/API access (no SSL certificate issues)

**Perfect for**: Integrating with software that doesn't handle self-signed certificates while maintaining secure browser access.

#### Prerequisites

- Method 2 setup complete (hostname and mDNS configured)
- `.env` file configured with `SEARXNG_HOSTNAME=searxng.local`

#### Configuration Steps

1. **Stop containers**:
   ```bash
   cd /usr/local/searxng-docker
   sudo docker compose down
   ```

2. **Edit Caddyfile**:
   ```bash
   sudo nano Caddyfile
   ```

3. **Find this section** (around line 33):
   ```
   {$SEARXNG_HOSTNAME}
   
   tls {$SEARXNG_TLS}
   ```

4. **Replace with** (IMPORTANT: both addresses on ONE line with comma):
   ```
   http://searxng.local:8888, https://searxng.local {
   	tls internal
   ```
   
   Make sure:
   - Both addresses are on the SAME line, separated by a comma
   - Opening brace `{` is at the end of that line
   - `tls internal` is on the next line, indented with a tab

5. **Find the Content-Security-Policy line** (around line 58):
   ```
   Content-Security-Policy "upgrade-insecure-requests; default-src 'none'; ...
   ```

6. **Remove `upgrade-insecure-requests;`** from the beginning:
   ```
   Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; ...
   ```

7. **Verify proper indentation**: All directives after the opening `{` must be indented with a tab (not spaces).

8. **Verify the file ends with a closing brace** `}` after the line `reverse_proxy localhost:8080`

9. **Save and restart**:
   ```bash
   sudo docker compose up -d
   
   # Verify all containers are running (Caddy should NOT be restarting)
   sudo docker ps
   ```

#### Access Your SearXNG Instance

**For Browsers**:
- URL: `https://searxng.local`
- Port: 443 (default HTTPS, no need to specify)
- Accept the self-signed certificate warning once
- Full CSS/JS/styling works correctly

**For Third-Party Software/API**:
- URL: `http://searxng.local:8888`
- Port: 8888 (HTTP)
- No SSL certificate issues
- Example API call: `http://searxng.local:8888/search?q=test&format=json`

#### Troubleshooting Dual Configuration

**Caddy keeps restarting**:
```bash
# Check logs for syntax errors
sudo docker compose logs caddy | tail -50
```

Common issues:
- Both addresses must be on ONE line separated by comma: `http://searxng.local:8888, https://searxng.local {`
- Opening brace `{` must be on the same line as the addresses
- All directives inside `{ }` must be indented with tabs (not spaces)
- Must have closing `}` at end of file after `reverse_proxy localhost:8080`

**Browser shows unstyled page (missing CSS)**:
- Make sure you removed `upgrade-insecure-requests;` from the Content-Security-Policy
- Clear browser cache (Ctrl+Shift+Delete)
- Hard refresh the page (Ctrl+F5)
- Verify `.env` has only `SEARXNG_HOSTNAME=searxng.local` (no port number, no `http://` prefix)
- Check browser console for CSP errors (F12 → Console tab)

**Port 8888 not responding**:
```bash
# Check if port is listening
sudo netstat -tlnp | grep 8888

# Verify Caddyfile configuration
cat Caddyfile | head -40

# Should show: http://searxng.local:8888, https://searxng.local {
```

**HTTP works but HTTPS doesn't (or vice versa)**:
- Restart the containers: `sudo docker compose restart`
- Check firewall isn't blocking ports 443 or 8888
- Verify both ports in Caddyfile address line

---

### Option 4: Use HTTP Only (Not Recommended)

If you want to avoid certificate warnings and don't need encryption on your local network:

1. Edit `.env`:
   ```bash
   sudo nano /usr/local/searxng-docker/.env
   ```

2. Change to HTTP:
   ```
   SEARXNG_HOSTNAME=searxng.local
   SEARXNG_HTTPS=false
   ```

3. Restart:
   ```bash
   sudo docker compose down
   sudo docker compose up -d
   ```

4. Access via: `http://searxng.local` (no 's')

> **Warning**: This sends all search queries in plain text over your network. Only use on trusted networks.

---

## Managing SearXNG

### Stop and Restart Containers

If you edit the `settings.yml` file in `/usr/local/searxng-docker/searxng/`, restart Docker to load changes:

```bash
# NOTE: Use "docker compose" (with space) for V2
sudo docker compose down
sudo docker compose up -d
```

### Configure Auto-Restart on Reboot

**Recommended**: Add yourself to the docker group to avoid permission issues:

```bash
# Create docker group if it doesn't exist
sudo groupadd docker 2>/dev/null || true

# Add the current user to the docker group
sudo usermod -aG docker $USER
```

**Log out and back in** to update your groups, or restart the VM.

After logging back in, verify you can run docker without sudo:

```bash
docker ps
```

Set containers to auto-restart after reboot:

```bash
# If you're in the docker group (without sudo):
docker update --restart unless-stopped $(docker ps -q)

# Or with sudo if you haven't added yourself to the docker group:
sudo docker update --restart unless-stopped $(sudo docker ps -q)
```

---

## Updating SearXNG

To update your SearXNG container from GitHub:

### 1. Navigate to the Directory

```bash
cd /usr/local/searxng-docker
```

### 2. Pull Latest Images

```bash
# NOTE: use "docker compose" with space
sudo docker compose pull
```

### 3. Restart Containers

```bash
sudo docker compose up -d
```

### 4. Clean Up Old Images

```bash
# Delete all unused images
sudo docker image prune -f
```

### 5. Verify Auto-Restart is Still Enabled

```bash
# Use sudo for both commands to avoid permission errors
sudo docker update --restart unless-stopped $(sudo docker ps -q)

# Or if you're in the docker group (without sudo):
docker update --restart unless-stopped $(docker ps -q)
```

---

## Troubleshooting

### 1. "ERR_SSL_PROTOCOL_ERROR" or "sent an invalid response"

**Symptoms**: Browser shows `ERR_SSL_PROTOCOL_ERROR` or "This site can't provide a secure connection"

**Causes**:
- Containers not running properly
- Wrong hostname in `.env` file
- Port conflict

**Solution**:
```bash
cd /usr/local/searxng-docker

# Check if containers are running
sudo docker ps

# Check container logs for errors
sudo docker compose logs

# Verify your .env configuration
cat .env | grep SEARXNG_HOSTNAME

# Restart containers
sudo docker compose down
sudo docker compose up -d

# Wait 30 seconds, then try accessing again
```

If the hostname shows your IP but you're trying to access via `searxng.local`, edit `.env`:
```bash
sudo nano .env
```
Change `SEARXNG_HOSTNAME=192.168.10.10` to `SEARXNG_HOSTNAME=searxng.local`, then restart.

---

### 2. Hostname resolves but SSL error persists

**Solution**: Try HTTP instead of HTTPS temporarily to test:
```bash
# Edit .env
sudo nano /usr/local/searxng-docker/.env
```

Add this line:
```
SEARXNG_HTTPS=false
```

Restart:
```bash
sudo docker compose down
sudo docker compose up -d
```

Access via `http://searxng.local` (no 's'). If this works, the issue is SSL-specific.

---

### 3. "ModuleNotFoundError: No module named 'distutils'"

**Cause**: Old `docker-compose` installed (incompatible with Python 3.12)

**Solution**:
```bash
sudo apt remove docker-compose
```
Then follow the Docker Compose V2 installation steps above.

---

### 4. "Unable to locate package docker-compose-plugin"

**Cause**: Package isn't in default Ubuntu repos

**Solution**: Use the direct binary installation method (see "Install Docker Compose V2" section above). Do NOT try to add Docker's repository if you have network issues.

---

### 5. Repository Connection Errors

**Symptoms**: "Failed to fetch", "Temporary failure resolving"

**Solution**: Fix DNS first
```bash
# Verify internet connectivity
ping -c 3 8.8.8.8

# Set Google DNS
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo bash -c 'echo "nameserver 8.8.4.4" >> /etc/resolv.conf'

# Test DNS resolution
ping -c 3 google.com
```

---

### 6. "permission denied while trying to connect to the Docker daemon socket"

**Solution**: Add yourself to docker group
```bash
sudo usermod -aG docker $USER
```

Log out and back in for changes to take effect.

For the restart command, use:
```bash
sudo docker update --restart unless-stopped $(sudo docker ps -q)
```

---

### 7. GPG Key Errors

**Cause**: Trying to add Docker's repository

**Solution**: Don't bother with the repository - use direct binary installation instead. The direct method is simpler and more reliable.

---

### 8. Docker Compose Commands Not Working

**Cause**: Using old syntax

**Solution**: Make sure you're using `docker compose` (with space) not `docker-compose` (with hyphen). V2 uses the space syntax.

Verify installation:
```bash
docker compose version
```

---

### 9. Can't access via hostname, only IP works

**Cause**: mDNS not configured or hostname not set in `.env`

**Solution**:
1. Verify Avahi is running: `sudo systemctl status avahi-daemon`
2. Check hostname: `hostname` (should show `searxng`)
3. Verify `.env` has correct hostname: `cat /usr/local/searxng-docker/.env | grep SEARXNG_HOSTNAME`
4. Should show `SEARXNG_HOSTNAME=searxng.local` not an IP address
5. Restart containers: `sudo docker compose down && sudo docker compose up -d`

---

## Additional Resources

- **SearXNG Documentation**: https://docs.searxng.org/
- **SearXNG GitHub**: https://github.com/searxng/searxng
- **SearXNG Docker**: https://github.com/searxng/searxng-docker
- **Original Reddit Post**: https://www.reddit.com/r/Searx/comments/w7csyl/so_this_worked_for_me_searxng_in_a_vm_on_a_local/

---

## License

This guide is provided as-is for educational purposes. SearXNG is licensed under the GNU Affero General Public License v3.0.

---

## Contributing

Found an issue or have an improvement? Feel free to submit a pull request or open an issue.

---

**Happy Searching! 🔍**
