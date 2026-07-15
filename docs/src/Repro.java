package repro;

import com.google.gwt.core.client.EntryPoint;
import com.google.gwt.dom.client.Document;

public class Repro implements EntryPoint {

  /**
   * Produces a plain JS object with NO {@code value} property, opaquely, so the compiler cannot
   * see its shape and must read {@code value} as {@code undefined} at runtime.
   */
  private static native NativeObj emptyObject() /*-{
    return JSON.parse("{}");
  }-*/;

  private static native void log(String s) /*-{
    $wnd.console.log(s);
  }-*/;

  @Override
  public void onModuleLoad() {
    NativeObj obj = emptyObject();       // {} : obj.value is undefined
    Double boxed = obj.getValue();       // autobox of undefined
    boolean isNull = boxed == null;      // GWT <= 2.12: true. GWT >= 2.13 (optimized): false (BUG)

    String verdict = isNull ? "true  (CORRECT: undefined coerced to null)"
                            : "false (BUG: undefined leaked past == null)";
    String msg = "getValue() == null  ->  " + verdict;

    Document.get().getBody().setInnerText(msg);
    // Stable marker for headless/automated reading:
    log("REPRO_RESULT isNull=" + isNull);
    log(msg);
  }
}
