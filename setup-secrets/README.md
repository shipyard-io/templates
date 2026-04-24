# Automated GitHub Secrets Setup

This directory contains utilities to automatically and securely provision GitHub Secrets for your repository using the GitHub CLI, eliminating the need for manual data entry via the web interface.

## Prerequisites
Ensure the GitHub CLI (`gh`) is installed on your local machine:
- **macOS:** `brew install gh`
- **Windows:** `winget install --id GitHub.cli`
- **Ubuntu/Debian:** `sudo apt install gh`

After installation, authenticate your CLI session:
```bash
gh auth login
```
*(Select GitHub.com -> HTTPS -> Login with a web browser)*

## Setup Instructions

### Step 1: Create the Configuration File
From the root directory of your repository, duplicate the example file to create your local secrets file:
```bash
cp setup-secrets/.env.example .env.secrets
```
> **⚠️ CRITICAL:** The `.env.secrets` file is explicitly ignored via the root `.gitignore`. NEVER commit this file to version control, as it contains highly sensitive infrastructure credentials.

### Step 2: Populate the Variables
Open `.env.secrets` and populate it with your actual Server, Domain, and Certificate credentials.

**Note on Multiline Variables:**
Ensure that multiline values, such as `SSH_PRIVATE_KEY` and the Cloudflare Origin Certificates (`CLOUDFLARE_ORIGIN_CERT`, `CLOUDFLARE_ORIGIN_KEY`), remain strictly enclosed within double quotes (`""`). This formatting is required for the GitHub CLI to correctly parse line breaks (`\n`).

### Step 3: Provision Secrets to GitHub
Open your terminal at the root directory of the project and execute:
```bash
gh secret set -f .env.secrets
```
The GitHub CLI will automatically parse all variables and securely upload them as Repository Secrets.

You can verify the successfully imported secrets by navigating to your repository on GitHub: `Settings -> Secrets and variables -> Actions`.
