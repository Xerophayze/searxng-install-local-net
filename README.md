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

### 4. Update the System

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

**Modify the following:**
- Uncomment the `SEARXNG_HOSTNAME=` line
- Change the IP address to your VM's static IP
- Leave `LETSENCRYPT_EMAIL=` commented out (for local LAN use)

Example:
```
SEARXNG_HOSTNAME=192.168.10.10
# LETSENCRYPT_EMAIL=<email>
```

Save and exit (Ctrl+X, then Y, then Enter).

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

Open a web browser on any machine on your network and navigate to:

```
https://192.168.10.10
```

Replace with your VM's IP address.

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

### 1. "ModuleNotFoundError: No module named 'distutils'"

**Cause**: Old `docker-compose` installed (incompatible with Python 3.12)

**Solution**:
```bash
sudo apt remove docker-compose
```
Then follow the Docker Compose V2 installation steps above.

---

### 2. "Unable to locate package docker-compose-plugin"

**Cause**: Package isn't in default Ubuntu repos

**Solution**: Use the direct binary installation method (see "Install Docker Compose V2" section above). Do NOT try to add Docker's repository if you have network issues.

---

### 3. Repository Connection Errors

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

### 4. "permission denied while trying to connect to the Docker daemon socket"

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

### 5. GPG Key Errors

**Cause**: Trying to add Docker's repository

**Solution**: Don't bother with the repository - use direct binary installation instead. The direct method is simpler and more reliable.

---

### 6. Docker Compose Commands Not Working

**Cause**: Using old syntax

**Solution**: Make sure you're using `docker compose` (with space) not `docker-compose` (with hyphen). V2 uses the space syntax.

Verify installation:
```bash
docker compose version
```

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
