#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$DOTFILES_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    echo "$ENV_FILE already exists"
    exit 0
fi

cat > "$ENV_FILE" <<'EOF'
export XAI_API_KEY=
export X_BEARER_TOKEN=
EOF
echo "Created $ENV_FILE (値は手動で埋める)"
