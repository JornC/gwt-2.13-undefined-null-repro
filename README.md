# GWT 2.13: `undefined` leaks past `== null` when autoboxing a native-JsType primitive field

Minimal reproducer for a behavioral regression introduced in GWT **2.13.0**.

**Live demo (no build needed):** https://jornc.github.io/gwt-2.13-undefined-null-repro/ - the same
module compiled under both GWT versions, running side by side in the browser.

## Summary

Reading an **absent** JS property (`undefined`) through a native `@JsType(isNative = true)`
field that is declared as a Java **primitive** (`double`/`int`/...), then autoboxing it and
null-checking the boxed value, returns the wrong answer in the optimized compile:

| GWT version | `getValue() == null` (property absent) |
|-------------|----------------------------------------|
| 2.12.1      | `true`  ✅ (undefined coerced to null)  |
| 2.13.1      | `false` ❌ (undefined leaks through)    |

It only reproduces in the **optimized/production** compile. SuperDevMode is unaffected.

## The code (all of it)

`NativeObj` - a native overlay whose `value` property may be absent at runtime:

```java
@JsType(isNative = true, name = "Object", namespace = JsPackage.GLOBAL)
public class NativeObj {
  private double value;                 // maps an OPTIONAL JS property
  @JsOverlay public final Double getValue() {
    return value;                       // autoboxes double -> Double
  }
}
```

`Repro` - builds an object with no `value`, autoboxes it, null-checks it:

```java
NativeObj obj = /* opaque */ JSON.parse("{}");   // obj.value is undefined
Double boxed = obj.getValue();                    // autobox of undefined
boolean isNull = boxed == null;                   // 2.12: true, 2.13: false
```

## Run it

Requires JDK 11+ and Maven (used only to fetch the GWT jars from Maven Central):

```
./run.sh
```

This compiles the identical module under GWT 2.12.1 and 2.13.1 (full `-optimize 9`) and prints
where to open each. Open the two pages in any browser:

- `war/2.12.1/index.html` → `getValue() == null -> true  (CORRECT ...)`
- `war/2.13.1/index.html` → `getValue() == null -> false (BUG ...)`

(Also swap `<gwt.version>` in `pom.xml` to try other versions.)

## Root cause

Bisected to **PR #10165 / commit `b5155aa`** ("Allow JsUtils.uncheckedCast to be inlined away").
It is an ancestor of `2.13.0` and not in `2.12.1`.

The causal chain (verified against the 2.13.1 source):

1. Autoboxing `double`→`Double` compiles to `Double.$create(double x)`, whose body is
   `return JsUtils.uncheckedCast(x);` (`java/lang/Double.java`). Unchanged in the range.
2. `== null` is compiled by `EqualityNormalizer`, which only inserts the undefined→null
   coercion `Cast.maskUndefined` when **`canBeNull(lhs) && canBeNull(rhs)`**. Unchanged in the range.
3. #10165 changed `JsUtils.uncheckedCast` from an opaque JSNI native method
   (`/*-{ return o; }-*/`) to plain inlinable Java (`return (T) o;`), and let `MethodInliner`
   inline it.

Effect:

- **2.12:** the JSNI barrier blocked nullability analysis, so the boxed `Double` stayed
  "can be null" → `maskUndefined` was applied → `undefined` coerced to `null` → `== null` **true**.
- **2.13:** `uncheckedCast` is inlined, so type-tightening traces the value back to a primitive
  `double` (inherently non-null) → the boxed `Double` is tightened to **non-null**. Now
  `DeadCodeElimination` constant-folds `boxed == null` straight to the literal `false` (a boxed
  non-null value is never null), before any undefined→null normalization runs. So the JS
  `undefined` is never coerced and `== null` is **false**. (The same non-null typing also skips the
  `Cast.maskUndefined` coercion in `EqualityNormalizer`, which bites additional mixed-type
  comparisons; but for `getX() == null` the constant-fold is the operative step.)

The constant-fold is directly observable: `run.sh` shows that on 2.13.1 the compiler bakes the
result into the emitted string, whereas 2.12.1 computes it at runtime.

This also explains why it is optimized-compile-only: inlining, type-tightening, and dead-code
elimination do not run in SuperDevMode, so the barrier survives there and the coercion still happens.

## Workaround

Declare the field as the boxed type. A native field typed `Double` is read as a nullable
reference (stays `canBeNull`), so `maskUndefined` is still emitted:

```java
private Double value;   // instead of: private double value;
```

## Live demo / GitHub Pages

`docs/` is a ready-to-serve GitHub Pages site: a single static page that iframes both compiled
apps (`docs/app/2.12.1` and `docs/app/2.13.1`) and reports the flip. Rebuild it with
`./build-pages.sh`; serve locally with `(cd docs && python3 -m http.server)`. Pages is served from
the `main` branch `/docs` folder.

## Environment

- GWT 2.12.1 (correct) vs 2.13.1 (regressed)
- JDK 11+, any browser
