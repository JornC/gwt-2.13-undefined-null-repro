<!-- Formatted to gwtproject/gwt's .github/ISSUE_TEMPLATE.md -->

**GWT version:** 2.13.0 / 2.13.1 (regression from 2.12.x)
**Browser (with version):** any - compiler-output bug
**Operating System:** any

---

##### Description

Optimized compile only (SuperDevMode is fine). A native `@JsType(isNative=true)` **primitive**
field that is absent at runtime (JS `undefined`), autoboxed and null-checked, changed behavior in
2.13.0:

| GWT | property absent, `getValue() == null` |
|-----|---------------------------------------|
| 2.12.x | `true` |
| 2.13.x | `false` |

This breaks GWT's long-standing boundary contract that Java code need not distinguish JS `null` from
`undefined` (as niloc132 has described it on #10331: GWT normalizes the two away so Java code doesn't
worry about the difference). A value read out of native JsInterop can be `undefined`; a `== null`
check used to catch it and now silently doesn't.

Mechanism: autoboxing `double`->`Double` goes through `JsUtils.uncheckedCast`, represented as a
`JUnsafeTypeCoercion`. `JUnsafeTypeCoercion.getType()` strengthens its result to non-null whenever
the coerced expression can't be null - always true for a primitive. That strengthening predates
2.13; #10165 / `b5155aa` made `uncheckedCast` inlinable, so the non-null type now **propagates** out
into the surrounding expression instead of staying behind the opaque call. Two consumers then rely on
it: `DeadCodeElimination` folds `boxed == null` to `false`, and `EqualityNormalizer` skips the
`Cast.maskUndefined` it would otherwise insert. Either path lets the `undefined` leak past the null
check.

##### Steps to reproduce

Live, side by side - 2.12.1 / 2.13.1 / 2.13.1+proposed-fix: https://jornc.github.io/gwt-2.13-undefined-null-repro/
Project: https://github.com/JornC/gwt-2.13-undefined-null-repro

```java
@JsType(isNative = true, name = "Object", namespace = JsPackage.GLOBAL)
class NativeObj {
  private double value;                                       // OPTIONAL JS property
  @JsOverlay public final Double getValue() { return value; } // autobox double -> Double
}

NativeObj obj = /* opaque */ JSON.parse("{}");  // value is undefined
boolean isNull = obj.getValue() == null;        // 2.12: true, 2.13: false
```

##### Known workarounds

Box the field: `private Double value;` - read as a nullable reference, so the coercion is preserved.
(`-optimize 1` or lower also avoids it; `-optimize 2` through `9` all reproduce it.)

##### Links to further discussions

- #10165 - the PR that exposed this: it made `uncheckedCast` inlinable and already fixed one
  inlining/nullability interaction; this is a second one on the same path.
- #10298 - a related, already-fixed 2.13 optimizer regression on native-`@JsType` members. Same
  family (native-overlay nullability under the optimizer), different trigger.
- #10311 / #10331 - the invariant that JS `undefined` is treated as `null` at the JsInterop boundary.

A PR with a proposed fix + tests follows: a one-line guard in `JUnsafeTypeCoercion.getType()` that
skips the non-null strengthening when the coerced expression is a primitive. It only changes the
*nullability of the result type*, not whether `uncheckedCast` is inlinable - so #10165's actual win
is untouched (the `$clinit_Boolean` removal, which comes from inlinability, still happens; verified
against the fixed build). The cost is a small, deliberate deoptimization: a primitive `uncheckedCast`
result is no longer treated as provably non-null.

---
*Found and reported with [Claude Code](https://claude.com/claude-code).*
