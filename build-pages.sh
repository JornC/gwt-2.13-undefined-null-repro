#!/usr/bin/env bash
# Build the GitHub Pages demo into docs/ : both GWT versions compiled + the real source staged
# so the landing page can display it. Enable Pages on: main branch, /docs folder.
set -euo pipefail
cd "$(dirname "$0")"

VERSIONS=("2.12.1" "2.13.1")

for V in "${VERSIONS[@]}"; do
  echo "==================== GWT $V ===================="
  rm -rf "docs/app/$V"
  mvn -q -Dgwt.version="$V" dependency:copy-dependencies -DoutputDirectory="lib/$V"

  # gwt-dev first on the classpath (see run.sh for why).
  DEV=$(ls lib/$V/gwt-dev*.jar | head -1)
  REST=$(ls lib/$V/*.jar | grep -v '/gwt-dev' | tr '\n' ':')

  java -cp "$DEV:$REST:src/main/java" com.google.gwt.dev.Compiler \
    -sourceLevel 11 -optimize 9 \
    -war "docs/app/$V" repro.Repro

  cp pages/app-template.html "docs/app/$V/index.html"
done

# Stage the real source so the landing page shows exactly what was compiled.
mkdir -p docs/src
cp src/main/java/repro/NativeObj.java docs/src/NativeObj.java
cp src/main/java/repro/Repro.java     docs/src/Repro.java

echo
echo "Built docs/. Preview: (cd docs && python3 -m http.server 9997) then open http://127.0.0.1:9997/"
