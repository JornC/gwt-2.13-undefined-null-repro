#!/usr/bin/env bash
# Compile the same module under two GWT versions and show the behavior flip.
# Requires: JDK 11+ and Maven (only used to resolve the GWT jars from Maven Central).
set -euo pipefail
cd "$(dirname "$0")"

VERSIONS=("2.12.1" "2.13.1")

for V in "${VERSIONS[@]}"; do
  echo "==================== GWT $V ===================="
  rm -rf "lib/$V" "war/$V"
  mkdir -p "war/$V"

  # Resolve gwt-user + gwt-dev (+ transitive deps) for this version into lib/$V
  mvn -q -Dgwt.version="$V" dependency:copy-dependencies -DoutputDirectory="lib/$V"

  # Classpath ordering matters: 2.12's gwt-dev bundles its own JDT (and ships a stale, conflicting
  # ecj-3.19 as a transitive), while 2.13's gwt-dev has no bundled JDT and needs the external
  # ecj-3.33. Putting gwt-dev FIRST makes its bundled JDT win for 2.12, while 2.13 still finds the
  # (correct) external ecj later on the path.
  DEV=$(ls lib/$V/gwt-dev*.jar | head -1)
  REST=$(ls lib/$V/*.jar | grep -v '/gwt-dev' | tr '\n' ':')
  CP="$DEV:$REST"

  # Full production/optimized compile (-optimize 9). Style DETAILED keeps method names readable
  # so the generated code can be inspected; it does NOT disable optimizations, so the bug still
  # reproduces (unlike SuperDevMode, which disables optimizations and hides it).
  java -cp "${CP}src/main/java" com.google.gwt.dev.Compiler \
    -sourceLevel 11 -optimize 9 -style DETAILED \
    -war "war/$V" repro.Repro

  cp war-template/index.html "war/$V/index.html"
  echo "compiled -> war/$V/index.html"

  # Browser-free signal: the optimizer bakes `isNull` into the emitted string only when it can
  # prove the boxed value's nullness statically. On the buggy version it folds to the constant
  # `false`; on the correct version it stays a runtime computation.
  JS=$(ls war/"$V"/repro/*.cache.js | head -1)
  if grep -q "REPRO_RESULT isNull=false" "$JS"; then
    echo "  static check: isNull constant-folded to FALSE  ->  optimizer proved boxed != null (BUG)"
  elif grep -q "REPRO_RESULT isNull=true" "$JS"; then
    echo "  static check: isNull constant-folded to TRUE"
  else
    echo "  static check: isNull computed at runtime (not folded)  ->  CORRECT"
  fi
done

echo
echo "Open each in a browser:"
for V in "${VERSIONS[@]}"; do echo "  file://$(pwd)/war/$V/index.html"; done
echo
echo "Expected: 2.12.1 prints 'true (CORRECT)', 2.13.1 prints 'false (BUG)'."
