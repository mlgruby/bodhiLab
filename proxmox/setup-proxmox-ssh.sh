#!/usr/bin/env bash
# setup-proxmox-ssh.sh  —  painless SSH key + config for a Proxmox node
set -euo pipefail

###############################################################################
# 0.  Interactive prompts
###############################################################################
# Function to read a value with a default
ask () {                   # ask "Prompt text" "default"
  local var
  read -rp "$1 [$2]: " var
  echo "${var:-$2}"
}

echo "🔑  Proxmox SSH bootstrap"
echo "    (Press Enter to accept the value in [brackets])"
echo

NICK=$(ask "Short nickname you'll type (Host)" "vayu")
HOST=$(ask "IP or FQDN of the node" "192.168.1.141")
USER=$(ask "Login user" "root")
KEYFILE=$(ask "Private key file (will be created if missing)" "$HOME/.ssh/id_ed25519")
PUBFILE="${KEYFILE}.pub"
CONFIG="$HOME/.ssh/config"

echo
echo "Summary:"
printf "  %-12s %s\n" "Nickname:" "$NICK"
printf "  %-12s %s\n" "Host:"     "$HOST"
printf "  %-12s %s\n" "User:"     "$USER"
printf "  %-12s %s\n" "Keyfile:"  "$KEYFILE"
echo
read -rp "Proceed? [y/N] " CONFIRM
[[ $CONFIRM =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

###############################################################################
# 1. Ensure the key exists
###############################################################################
if [[ ! -f "$KEYFILE" ]]; then
  echo "► Generating new ed25519 key at $KEYFILE ..."
  ssh-keygen -t ed25519 -f "$KEYFILE" -C "${USER}@${NICK}"
fi

###############################################################################
# 2. Load the key into the agent
###############################################################################
echo "► Loading key into ssh-agent ..."
eval "$(ssh-agent -s)" >/dev/null
ssh-add -q "$KEYFILE"

###############################################################################
# 3. Copy the public key to the server
###############################################################################
echo "► Copying public key to ${USER}@${HOST} (you'll be asked for the password once)..."
ssh-copy-id -i "$PUBFILE" "${USER}@${HOST}"

###############################################################################
# 4. Add / update the block in ~/.ssh/config
###############################################################################
echo "► Updating $CONFIG ..."
mkdir -p "$(dirname "$CONFIG")"
touch "$CONFIG"
chmod 600 "$CONFIG"

# Strip any existing block for this Host nickname
awk -v nick="$NICK" '
  $1=="Host" && $2==nick {skip=1; next}
  skip && NF && $1=="Host" {skip=0}
  !skip
' "$CONFIG" > "${CONFIG}.tmp"

cat >> "${CONFIG}.tmp" <<EOF

# Proxmox node – added $(date '+%Y-%m-%d')
Host $NICK
  HostName $HOST
  User $USER
  IdentityFile $KEYFILE
  IdentitiesOnly yes
EOF

mv "${CONFIG}.tmp" "$CONFIG"

###############################################################################
# 5. Done
###############################################################################
echo
echo "✓ All set.  Test with:"
echo "    ssh $NICK"
