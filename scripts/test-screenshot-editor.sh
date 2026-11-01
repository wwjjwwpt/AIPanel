#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
mkdir -p .build/ModuleCache
swiftc -parse-as-library -module-cache-path .build/ModuleCache \
  Sources/PasteboardMemory/ScreenshotEditor.swift \
  Tests/PasteboardMemoryTests/ScreenshotCanvasTests.swift \
  -o .build/ScreenshotEditorTests
.build/ScreenshotEditorTests
