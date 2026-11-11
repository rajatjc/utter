#!/bin/bash
# Regenerates Resources/AppIcon.icns and Resources/AppIcon.png from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift
