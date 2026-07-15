<!-- Formatted to gwtproject/gwt's .github/ISSUE_TEMPLATE.md -->

**GWT version:** 2.13.0 / 2.13.1 (regression from 2.12.x)
**Browser (with version):** any - compiler-output bug
**Operating System:** any

---

##### Description

Optimized compile only (SuperDevMode is fine): a native `@JsType(isNative=true)` **primitive** field
holding an absent JS property (`undefined`), autoboxed and null-checked, is wrong since 2.13.0.

| GWT | `getValue() == null`, property absent |
|-----|---------------------------------------|
| 2.12.x | `true` (undefined treated as null) |
| 2.13.x | `false` (undefined leaks through) |

Cause: #10165 / `b5155aa` made `JsUtils.uncheckedCast` inlinable. Autoboxing `double`→`Double` runs
through it as a `JUnsafeTypeCoercion`, and `JUnsafeTypeCoercion.getType()` strengthens its result to
non-null when the coerced expression can't be null - always true for a primitive. Once inlined, the
boxed `Double` is typed non-null, so `DeadCodeElimination` folds `boxed == null` to `false`; the
`undefined` is never normalized. (The strengthening predates #10165; inlining made it reachable.)

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

##### Links to further discussions

- #10165 - root-cause PR (already fixed one inlining/nullability interaction; this is another).
- #10298 - precedent: a 2.13 optimizer regression on native-`@JsType` members (same class).
- #10055 - the `$clinit_Boolean` issue #10165 fixed. #10311 / #10331 - the undefined-is-null-at-the-edge invariant.

Proposed fix + tests follow in a PR: a one-line guard in `JUnsafeTypeCoercion.getType()` skipping the
non-null strengthening for primitives; preserves #10165's win (`$clinit_Boolean` still removed,
byte-identical).

---
*Found and reported with [Claude Code](https://claude.com/claude-code).*
