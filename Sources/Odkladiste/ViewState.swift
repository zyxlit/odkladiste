import SwiftUI

/// Property wrapper wrapping `SwiftUI.State` without invoking the `@State` macro,
/// allowing compilation with Apple Command Line Tools when `SwiftUIMacros` is unavailable.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var storage: SwiftUI.State<Value>

    init(wrappedValue: Value) {
        self.storage = SwiftUI.State(wrappedValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> {
        storage.projectedValue
    }
}
