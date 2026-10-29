#!/usr/bin/env bash
# Borra el clúster del demo.
set -euo pipefail
kind delete cluster --name shop
