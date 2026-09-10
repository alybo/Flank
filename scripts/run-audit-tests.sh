#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
audit_tmp="$(mktemp -d "${TMPDIR:-/tmp}/slideover-tests.XXXXXX")"
trap 'rm -rf "$audit_tmp"' EXIT
cd "$project_root"
xcrun swiftc -swift-version 5 -default-isolation MainActor \
  -enable-upcoming-feature DisableOutwardActorInference \
  -enable-upcoming-feature InferSendableFromCaptures \
  -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
  -enable-upcoming-feature MemberImportVisibility \
  -enable-upcoming-feature InferIsolatedConformances \
  -enable-upcoming-feature NonisolatedNonsendingByDefault \
  -module-cache-path "$audit_tmp/ModuleCache" \
  Flank/EdgeSettings.swift \
  Flank/WindowDragIntent.swift \
  Flank/Accessibility.swift \
  Flank/WindowCatalog.swift \
  Flank/AXWindowAccess.swift \
  Flank/WindowGeometry.swift \
  Flank/CancellableDelay.swift \
  Flank/PanelEntranceAnimation.swift \
  Flank/FlankManager.swift \
  Flank/FlankManagerRegistry.swift \
  Tests/Audit/main.swift -o "$audit_tmp/audit-tests"
"$audit_tmp/audit-tests"
