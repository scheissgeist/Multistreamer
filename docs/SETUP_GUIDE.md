# Multistreamer Setup Guide

A step-by-step guide to multistreaming with your own server. No prior experience with servers, terminals, or SSH required.

**What you'll have when you're done:** One OBS output that simultaneously streams to Twitch, Kick, and any other platform you want. Cost: ~$5/month for the server.

**Time required:** About 30 minutes the first time.

---

## Table of Contents

1. [Get a Server](#1-get-a-server)
2. [Set Up the Server](#2-set-up-the-server)
3. [Install the Dashboard on Your Computer](#3-install-the-dashboard-on-your-computer)
4. [Configure Your Stream Keys](#4-configure-your-stream-keys)
5. [Deploy](#5-deploy)
6. [Set Up OBS](#6-set-up-obs)
7. [Go Live](#7-go-live)
8. [Optional: API Setup](#8-optional-api-setup-titles-and-categories)

---

## 1. Get a Server

You need a server — a computer that runs 24/7 in a data center. Your stream goes to this server first, and the server copies it to every platform. You rent one for about $5/month.

We'll use **Hetzner Cloud** because it's the cheapest option that works well for this.

### Create a Hetzner Account

1. Go to [https://www.hetzner.com/cloud/](https://www.hetzner.com/cloud/)
2. Click **Sign Up** (top right)
3. Enter your email, create a password, verify your email
4. You'll need to add a payment method (credit card or PayPal)

### Create a Project

1. Once logged in, you'll see the **Cloud Console**
2. Click **+ New Project**
3. Name it anything — "Multistream" works
4. Click into the project

### Create an SSH Key

**What's an SSH key?** It's a pair of files on your computer that let you securely log into your server without a password. One file is "public" (you give it to the server), one is "private" (stays on your computer, never share it).

Follow GitHub's guide to create one — it works for any server, not just GitHub:

- **Windows:** [https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key)
- **Mac:** Same link, select the macOS tab at the top

The short version:

1. Open a **terminal** (see "How to Open a Terminal" below if you don't know how)
2. Run: `ssh-keygen -t ed25519 -C "your_email@example.com"`
3. Press Enter to accept the default file location
4. Enter a passphrase (or press Enter for none)
5. Two files are created:
   - `~/.ssh/id_ed25519` — your private key (NEVER share this)
   - `~/.ssh/id_ed25519.pub` — your public key (this is what you give to Hetzner)
6. Copy the public key to your clipboard:
   - **Windows:** `cat ~/.ssh/id_ed25519.pub | clip`
   - **Mac:** `cat ~/.ssh/id_ed25519.pub | pbcopy`

### Add the SSH Key to Hetzner

1. In the Hetzner Cloud Console, go to **Security** (left sidebar) > **SSH Keys**
2. Click **Add SSH Key**
3. Paste your public key (the one you just copied)
4. Give it a name like "My Laptop"
5. Click **Add SSH Key**

### Create the Server

1. Go back to your project, click **Add Server**
2. **Location:** Pick the one closest to you geographically
3. **Image:** Ubuntu 24.04
4. **Type:** Shared vCPU, x86, **CPX11** (2 vCPU, 4 GB RAM — about $5.59/month, this is more than enough)
5. **SSH Keys:** Check the box next to the key you just added
6. **Name:** Anything — "multistream" works
7. Click **Create & Buy Now**

Wait about 30 seconds. Your server will appear with an **IP address** (something like `203.0.113.42`). Write this down or copy it — you'll need it throughout this guide.

---

## 2. Set Up the Server

Now you'll connect to your server and install the software it needs (Docker, Stunnel).

### How to Open a Terminal

A **terminal** is a text-based interface where you type commands. Every computer has one built in.

- **Windows 10/11:** Press `Win + X`, then click **Windows Terminal** or **PowerShell**. Either one works.
- **Mac:** Press `Cmd + Space`, type **Terminal**, press Enter.

### Connect to Your Server

In your terminal, type this (replace `YOUR_IP` with the IP address from Hetzner):

```
ssh root@YOUR_IP
```

**What this does:** "SSH" means Secure Shell — it's remote-controlling the server through your terminal. You're logging in as `root` (the admin account) at your server's IP address.

The first time you connect, it will ask:

```
The authenticity of host '...' can't be established.
Are you sure you want to continue connecting (yes/no)?
```

Type `yes` and press Enter. This is normal — it's just your computer confirming it hasn't seen this server before.

You're now controlling the server. Your terminal prompt will change to something like `root@multistream:~#`.

### Install Docker and Stunnel

Copy and paste this entire block into the terminal and press Enter:

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Stunnel (needed for Kick's TLS requirement)
apt install stunnel4 -y
systemctl enable stunnel4

# Verify Docker is working
docker --version
```

Wait for it to finish. You'll see version numbers printed if everything worked.

### Disconnect from the Server

Type `exit` and press Enter. You're back on your own computer. The server is set up and will keep running on its own.

---

## 3. Install the Dashboard on Your Computer

The dashboard is a web page that runs on YOUR computer (not the server) and lets you manage everything without typing commands.

### Install Python

**Python** is the programming language the dashboard is written in. You need it installed to run the dashboard.

- Check if you already have it: open a terminal and type `python --version` or `python3 --version`
- If you get a version number (3.8 or higher), you're good — skip ahead
- If not, download it from [https://www.python.org/downloads/](https://www.python.org/downloads/)
  - **Windows:** Download the installer, run it, and **check the box that says "Add Python to PATH"** before clicking Install. This is important.
  - **Mac:** Download and install the .pkg file

### Install Git

**Git** is a tool for downloading and tracking code. You need it to get the Multistreamer code.

- Check if you already have it: `git --version`
- If not:
  - **Windows:** Download from [https://git-scm.com/download/win](https://git-scm.com/download/win) and install with default settings
  - **Mac:** It usually comes pre-installed. If not, the terminal will prompt you to install Apple's developer tools when you try to use it — say yes

### Download Multistreamer

Open a terminal and run these commands one at a time:

```bash
git clone https://github.com/scheissgeist/Multistreamer.git
cd Multistreamer
pip install -r requirements.txt
```

**What these do:**
1. `git clone` downloads the Multistreamer code to a folder on your computer
2. `cd Multistreamer` moves into that folder
3. `pip install` installs the one dependency the dashboard needs (Flask, a web framework)

If `pip` doesn't work, try `pip3` instead.

### Start the Dashboard

```bash
python web/server.py
```

(Try `python3 web/server.py` if `python` doesn't work.)

Open your web browser and go to: **http://localhost:3000**

You should see the Multistreamer dashboard. Leave the terminal running — closing it stops the dashboard.

---

## 4. Configure Your Stream Keys

A **stream key** is a secret code that tells a platform "this stream belongs to this account." Each platform gives you one. Anyone with your stream key can stream to your channel, so treat them like passwords.

### Enter Your Server IP

In the dashboard, find the Server IP field and enter the IP address you got from Hetzner in Step 1.

### Find Your Twitch Stream Key

1. Go to [https://dashboard.twitch.tv/settings/stream](https://dashboard.twitch.tv/settings/stream)
2. Log in if needed
3. Click **Copy** next to your Primary Stream Key
4. Paste it into the Twitch Stream Key field in the dashboard

### Find Your Kick Stream Key

1. Go to [https://kick.com/dashboard/settings/stream](https://kick.com/dashboard/settings/stream)
2. Log in if needed
3. Your stream key will be shown (you may need to click "Show" or "Reveal")
4. Copy it and paste it into the Kick Stream Key field in the dashboard

### Save

Click **Save** in the dashboard. Your keys are stored locally in a `.env` file on your computer — they never leave your machine except when deploying to your server.

---

## 5. Deploy

Click **Deploy** in the dashboard.

**What this does:** It uploads the configuration files and your stream keys to your server, then starts the streaming containers. The server is now ready to receive your stream and forward it to all platforms.

You can also deploy from the terminal:

```bash
bash scripts/multistream.sh deploy
```

---

## 6. Set Up OBS

Open **OBS Studio** (download from [https://obsproject.com](https://obsproject.com) if you don't have it).

1. Go to **Settings** (bottom right) > **Stream**
2. Set **Service** to **Custom...**
3. Set **Server** to: `rtmp://YOUR_IP/live` (replace YOUR_IP with your server's IP address)
4. Set **Stream Key** to: `livestream`
5. Click **Apply**, then **OK**

That's it. OBS will now send your stream to your server instead of directly to Twitch/Kick.

---

## 7. Go Live

1. Make sure your server is deployed (Step 5)
2. In OBS, click **Start Streaming**
3. Your stream is now live on every platform you configured

Check the dashboard — it will show active streams and container health. You can also check your Twitch and Kick channels to confirm they're receiving the stream.

To stop streaming, click **Stop Streaming** in OBS. The server stays running and ready for next time.

---

## 8. Optional: API Setup (Titles and Categories)

By default, Multistreamer just forwards your video. If you also want to set your stream **title** and **game/category** on Twitch and Kick from the dashboard (instead of going to each site separately), you need to register API apps.

This is optional. Skip this if you're fine setting titles on each platform's website.

### Register a Twitch App

1. Go to [https://dev.twitch.tv/console/apps](https://dev.twitch.tv/console/apps)
2. Log in with your Twitch account
3. Click **Register Your Application**
4. **Name:** Anything — "My Multistreamer" works
5. **OAuth Redirect URLs:** Add `http://localhost:3000`
6. **Category:** Broadcaster Suite
7. Click **Create**
8. Click **Manage** on your new app
9. Copy the **Client ID**
10. Click **New Secret** and copy the **Client Secret**

### Register a Kick App

1. Go to [https://dev.kick.com](https://dev.kick.com)
2. Log in with your Kick account
3. Create a new application
4. **Redirect URI:** `http://localhost:3000`
5. Copy the **Client ID** and **Client Secret**

### Run the Auth Setup

Open a terminal in the Multistreamer folder and run:

```bash
bash scripts/auth-setup.sh
```

This will:
1. Ask for your Client ID and Client Secret for each platform
2. Open your browser to authorize the app
3. Save the access tokens to your `.env` file

You can also set up one platform at a time:

```bash
bash scripts/auth-setup.sh twitch
bash scripts/auth-setup.sh kick
```

Once authenticated, you can set titles and categories from the dashboard or the command line:

```bash
bash scripts/multistream.sh golive "Stream Title" --game "Game Name"
bash scripts/multistream.sh title "New Title"
bash scripts/multistream.sh game "Just Chatting"
```

---

## Troubleshooting

### "Permission denied" when connecting via SSH

- Make sure you added the correct SSH key to Hetzner
- Make sure you're using the right IP address
- On Windows, make sure your SSH key is in `C:\Users\YourName\.ssh\`

### "pip is not recognized"

- Try `pip3` instead of `pip`
- On Windows, make sure you checked "Add Python to PATH" during installation. If you didn't, uninstall Python and reinstall with that box checked.

### OBS says "Failed to connect"

- Check that your server IP is correct in the OBS stream settings
- Make sure you deployed (Step 5) — the server needs the containers running
- Check the dashboard for container status

### Stream is live on Twitch but not Kick (or vice versa)

- Check the dashboard for container health — one container might have an error
- Verify the stream key is correct for the failing platform
- Try redeploying: click Deploy in the dashboard

### Dashboard won't start

- Make sure you ran `pip install -r requirements.txt`
- Make sure you're in the Multistreamer folder when running `python web/server.py`
- Check that port 3000 isn't being used by something else

---

## Adding More Platforms

Want to stream to YouTube, Facebook, X, or other platforms too? See the "Adding More Platforms" section in the main [README](../README.md). Each platform is just another container — you add a block to the config, put in your stream key, and redeploy.

---

## Monthly Cost

- **Hetzner CPX11:** ~$5.59/month (2 vCPU, 4 GB RAM, 20 TB traffic)
- **Everything else:** Free

The server uses almost no CPU because it's just copying stream data, not re-encoding it. One CPX11 can handle 5-10 platforms easily. Bandwidth is the real limit — at 6 Mbps per destination, 5 platforms uses about 10 TB/month (within the included 20 TB).
