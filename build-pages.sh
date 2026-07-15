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

# ---- Third build: GWT 2.13.1 with the proposed compiler fix applied ----
# The fix touches one compiler class, so we recompile just that class against the released
# gwt-dev-2.13.1.jar and overlay it into a patched copy of the jar - no full GWT build needed.
echo "==================== GWT 2.13.1 + fix ===================="
rm -rf "docs/app/2.13.1-fixed" build/patch
mkdir -p build/patch/classes build/patch/lib

DEVJAR=$(ls lib/2.13.1/gwt-dev-2.13.1.jar)
javac --release 11 -cp "$DEVJAR" -d build/patch/classes fix/JUnsafeTypeCoercion.java

cp "$DEVJAR" build/patch/gwt-dev-2.13.1-patched.jar
# delete the original entry first so the overlaid class is the only one (deterministic load)
zip -q -d build/patch/gwt-dev-2.13.1-patched.jar 'com/google/gwt/dev/jjs/ast/JUnsafeTypeCoercion*.class' || true
( cd build/patch/classes && jar uf ../gwt-dev-2.13.1-patched.jar com/google/gwt/dev/jjs/ast/JUnsafeTypeCoercion*.class )

cp lib/2.13.1/*.jar build/patch/lib/
rm -f build/patch/lib/gwt-dev-*.jar
cp build/patch/gwt-dev-2.13.1-patched.jar build/patch/lib/

PDEV=build/patch/lib/gwt-dev-2.13.1-patched.jar
PREST=$(ls build/patch/lib/*.jar | grep -v gwt-dev | tr '\n' ':')
java -cp "$PDEV:$PREST:src/main/java" com.google.gwt.dev.Compiler \
  -sourceLevel 11 -optimize 9 \
  -war "docs/app/2.13.1-fixed" repro.Repro
cp pages/app-template.html "docs/app/2.13.1-fixed/index.html"

# Stage the real source so the landing page shows exactly what was compiled.
mkdir -p docs/src
cp src/main/java/repro/NativeObj.java docs/src/NativeObj.java
cp src/main/java/repro/Repro.java     docs/src/Repro.java
cp fix/JUnsafeTypeCoercion.patch      docs/src/JUnsafeTypeCoercion.patch

echo
echo "Built docs/. Preview: (cd docs && python3 -m http.server 9997) then open http://127.0.0.1:9997/"
