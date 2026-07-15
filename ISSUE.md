<!-- Formatted to gwtproject/gwt's .github/ISSUE_TEMPLATE.md -->

**GWT version:** 2.13.0 and 2.13.1 (regression from 2.12.x)
**Browser (with version):** any - compiler-output bug, browser-agnostic
**Operating System:** any

---

##### Description

In the optimized/production compile (SuperDevMode is fine), reading an **absent** JS property
(`undefined`) through a native `@JsType(isNative = true)` field declared as a Java **primitive**
(`double`/`int`/…), then autoboxing it and null-checking the boxed value, returns the wrong answer:

| GWT | `getValue() == null` when the property is absent |
|-----|--------------------------------------------------|
| 2.12.x | `true` (correct - `undefined` is treated as `null`) |
| 2.13.x | `false` (wrong - `undefined` leaks past the null check) |

**Root cause.** Bisected to #10165 / `b5155aa` ("Allow JsUtils.uncheckedCast to be inlined away").
Autoboxing `double`→`Double` compiles to `Double.$create(double)` → `JsUtils.uncheckedCast(x)`, which
is represented as a `JUnsafeTypeCoercion`. `JUnsafeTypeCoercion.getType()` strengthens its result to
non-null when the coerced expression cannot be null - always true for a primitive. Before #10165,
`uncheckedCast` was opaque JSNI and never inlined, so the nullable boundary survived. After #10165 it
inlines, the strengthening fires, the autoboxed `Double` is typed non-null, and `DeadCodeElimination`
constant-folds `boxed == null` to `false` (the `undefined` is never normalized to `null`). The
strengthening predates #10165; it just became reachable once the cast could be inlined.

##### Steps to reproduce

Live demo (no build - 2.12.1, 2.13.1, and 2.13.1-with-a-proposed-fix side by side):
https://jornc.github.io/gwt-2.13-undefined-null-repro/

Demo project / `run.sh`: https://github.com/JornC/gwt-2.13-undefined-null-repro

The whole reproducer:

```java
@JsType(isNative = true, name = "Object", namespace = JsPackage.GLOBAL)
class NativeObj {
  private double value;                                         // maps an OPTIONAL JS property
  @JsOverlay public final Double getValue() { return value; }   // autoboxes double -> Double
}

NativeObj obj = /* opaque */ JSON.parse("{}");   // obj.value is undefined
Double boxed = obj.getValue();                   // autobox of undefined
boolean isNull = boxed == null;                  // 2.12: true, 2.13: false
```

##### Known workarounds

Declare the optional native-overlay field as the **boxed** type, so it is read as a nullable
reference (which stays `canBeNull`, preserving the `undefined`→`null` coercion):

```java
private Double value;   // instead of: private double value;
```

##### Links to further discussions

- #10165 - root-cause PR; already fixed one inlining/nullability interaction (`@SpecializeMethod`
  over-tightening), so this is another side effect of the same change.
- #10298 - precedent: a 2.13 optimizer regression on native-`@JsType` member access (same bug class).
- #10055 - the empty-`$clinit_Boolean` issue #10165 was written to fix (motivation/context).
- #10311 / #10331 - the "`undefined` is treated as `null` at the JsInterop edge" invariant and the
  `Cast.maskUndefined` machinery this regression violates.

A proposed fix + regression tests: PR (one-line guard in `JUnsafeTypeCoercion.getType()` so a coerced
primitive is not strengthened to non-null). It preserves #10165's win - the `$clinit_Boolean` case is
still removed and output is byte-identical for that case.
