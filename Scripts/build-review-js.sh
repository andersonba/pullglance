#!/bin/sh
# Rebuilds Sources/Pullglance/Resources/review.js and review-presets.json from Web/. Node is needed only here.
set -eu
cd "$(dirname "$0")/../Web"
[ -d node_modules ] || npm install --no-audit --no-fund
npm run -s typecheck
npm test -- --reporter=dot
npm run -s build
ls -la ../Sources/Pullglance/Resources/review.js ../Sources/Pullglance/Resources/review-presets.json
