#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Stop Docker
# @raycast.mode compact
# @raycast.packageName Docker

# Optional parameters:
# @raycast.icon 🐳

# Documentation:
# @raycast.description Stop Docker Desktop engine to reduce CPU usage

docker desktop stop --detach

echo "Stopping Docker Desktop ⏹️"
