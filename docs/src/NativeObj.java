package repro;

import jsinterop.annotations.JsOverlay;
import jsinterop.annotations.JsPackage;
import jsinterop.annotations.JsType;

/**
 * A native JsInterop overlay over a plain JS object.
 *
 * <p>{@code value} maps a JS property that may be <b>absent</b> at runtime (i.e. {@code undefined}).
 * It is declared as a Java primitive {@code double}. The getter autoboxes it to {@link Double}.
 *
 * <p>This is the exact shape that regresses in GWT 2.13: reading an absent property through a
 * primitive field, autoboxing it, and later null-checking the boxed value.
 */
@JsType(isNative = true, name = "Object", namespace = JsPackage.GLOBAL)
public class NativeObj {

  private double value;

  @JsOverlay
  public final Double getValue() {
    // Autoboxes double -> Double. When the JS property is undefined, the boxed value should
    // compare == null (per GWT's "undefined is considered equal to null in Java code" contract).
    return value;
  }
}
