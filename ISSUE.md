# `undefined` leaks past `== null` for an autoboxed native-JsType primitive (regressed in 2.13.0)

## Summary

Reading an **absent** JS property (`undefined`) through a native
`@JsType(isNative = true)` field declared as a Java **primitive** (`double`/`int`/…), then
autoboxing it and null-checking the boxed value, returns the wrong answer in the optimized compile:

| GWT | `getValue() == null` when the property is absent |
|-----|--------------------------------------------------|
| 2.12.x | `true` (correct - `undefined` is treated as `null`) |
| 2.13.x | `false` (wrong - `undefined` leaks through) |

Only the optimized/production compile is affected; SuperDevMode is fine.

## Live demo & minimal reproducer

- Live (no build): https://jornc.github.io/gwt-2.13-undefined-null-repro/ - the same module compiled
  under 2.12.1, 2.13.1, and 2.13.1-with-the-proposed-fix, side by side.
- Source / `run.sh`: https://github.com/JornC/gwt-2.13-undefined-null-repro

The whole reproducer:

```java
@JsType(isNative = true, name = "Object", namespace = JsPackage.GLOBAL)
class NativeObj {
  private double value;                                   // maps an OPTIONAL JS property
  @JsOverlay public final Double getValue() { return value; }   // autoboxes double -> Double
}

NativeObj obj = /* opaque */ JSON.parse("{}");            // obj.value is undefined
Double boxed = obj.getValue();                            // autobox of undefined
boolean isNull = boxed == null;                           // 2.12: true, 2.13: false
```

## Root cause

Bisected to **#10165 / `b5155aa`** ("Allow JsUtils.uncheckedCast to be inlined away"), an ancestor
of 2.13.0 and not in 2.12.1.

1. Autoboxing `double`→`Double` compiles to `Double.$create(double)`, whose body is
   `return JsUtils.uncheckedCast(x);` (`java/lang/Double.java`, unchanged in the range).
2. At AST-build time the `@UncheckedCast` body is a `JUnsafeTypeCoercion`, and the `@DoNotAutobox`
   primitive argument is wrapped as `JUnsafeTypeCoercion(Object, primitive)`.
   `JUnsafeTypeCoercion.getType()` strengthens its result to **non-null** when the coerced
   expression cannot be null - and a primitive can never be null.
3. Before #10165, `uncheckedCast` was an opaque JSNI native method, so it was never inlined
   (`MethodInliner` rejects JSNI; `TypeTightener` skips it). The nullable boundary was preserved and
   the `undefined→null` normalization happened.
4. After #10165, `uncheckedCast` is plain inlinable Java. Once inlined, the strengthening in step 2
   fires: the autoboxed `Double` is typed **non-null**, so `DeadCodeElimination` constant-folds
   `boxed == null` to `false` (and `EqualityNormalizer` also skips `Cast.maskUndefined`). The
   `undefined` that arrived from JS is never normalized.

That the strengthening is the operative step is directly observable: on 2.13 the compiler bakes the
folded result into the emitted output, whereas 2.12 computes it at runtime.

Note the strengthening in `JUnsafeTypeCoercion.getType()` predates #10165 - it simply became
reachable for the primitive-autobox path once the cast could be inlined.

## Affected

GWT 2.13.0 and 2.13.1, optimized compile only. Any native-JsType overlay that models an **optional**
JS property as a Java primitive and null-checks the autoboxed value.

## Workaround (in user code)

Declare the optional native-overlay field as the **boxed** type so it is read as a nullable
reference (which stays `canBeNull`, so the coercion is preserved):

```java
private Double value;   // instead of: private double value;
```

## Related issues

This appears to be unreported. Cross-references:

- **#10165** - the root-cause PR ("Allow JsUtils.uncheckedCast to be inlined away"). It already
  fixed one inlining/nullability interaction (`@SpecializeMethod` methods over-tightened once
  callsites inlined), so this is another side effect of the same change rather than a new class.
- **#10298** - "String.isEmpty() fails on native JS strings from `@JsType(isNative=true)` after
  #10091" - precedent: a 2.13 optimizer regression on native-`@JsType` member access (different
  trigger, same bug class).
- **#10055** - the empty-`$clinit_Boolean` issue that #10165 was written to fix (context/motivation).
- **#10311 / #10331** - describe the "undefined is treated the same as null at the JsInterop edge"
  invariant and the `Cast.maskUndefined` machinery this regression violates.

## Proposed fix

A one-line guard in `JUnsafeTypeCoercion.getType()`: do not strengthen the result to non-null when
the coerced expression is a primitive, since a primitive-typed value may actually be JS `undefined`
when it originates in native JsInterop/JSNI code. This keeps #10165's inlining/clinit-removal win
(verified: the `$clinit_Boolean` case is still removed and byte-identical) and only restores the
nullable boundary for the autobox path. A PR with a regression test follows.
