import WebKit

extension WKWebView {
    /// Hides the form-assistant bar (Prev/Next/Done) iOS attaches above the
    /// keyboard for web inputs. The chat has a single input, so the bar is
    /// pure noise; keyboard dismissal is covered by the scroll view's
    /// interactive dismiss.
    ///
    /// There is no public API for this. The standard technique (shipped by
    /// the major embedded-chat SDKs) swaps the web content view's class for a
    /// runtime subclass whose `inputAccessoryView` returns nil. If WebKit's
    /// internal view naming ever changes, this degrades to a no-op and the
    /// bar simply shows again.
    func removeInputAccessoryView() {
        guard let target = scrollView.subviews.first(where: {
            String(describing: type(of: $0)).hasPrefix("WKContent")
        }) else { return }

        let subclassName = "GradientChat_NoInputAccessory_\(String(describing: type(of: target)))"
        if let existing = NSClassFromString(subclassName) {
            object_setClass(target, existing)
            return
        }

        guard let targetClass = object_getClass(target),
              let subclass = objc_allocateClassPair(targetClass, subclassName, 0)
        else { return }

        let selector = #selector(getter: UIResponder.inputAccessoryView)
        if let method = class_getInstanceMethod(UIResponder.self, selector) {
            let returnsNil: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
            class_addMethod(
                subclass,
                selector,
                imp_implementationWithBlock(returnsNil),
                method_getTypeEncoding(method)
            )
        }
        objc_registerClassPair(subclass)
        object_setClass(target, subclass)
    }
}
