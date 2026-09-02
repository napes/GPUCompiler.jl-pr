# Device-only function declarations.
#
# A target-only intrinsic must not be materialized through the ordinary host method
# table: host AOT compilation would retain a link obligation for a symbol that only the
# device toolchain provides. GPU backends solve this by pairing an erroring host stub with
# the real definition in a backend-owned overlay method table.

"""
    GPUCompiler.@device_function method_table definition

Declare a function whose implementation is visible only through the overlay
`method_table`. The ordinary host method table receives a matching method that throws,
while the real `definition` is registered with `Base.Experimental.@overlay` for device
compilation.

This macro deliberately centralizes only the uniform device-function declaration. It
does not choose an overlay-consistency policy for overrides of host-meaningful methods;
backends retain that policy in their own `@device_override` helpers.

A backend normally binds its method table with a thin wrapper:

```julia
macro device_function(ex)
    esc(:(GPUCompiler.@device_function(method_table, \$ex)))
end
```
"""
macro device_function(method_table, ex)
    ex = macroexpand(__module__, ex)
    def = splitdef(ex)

    # Keep the device-only implementation out of the ordinary host method table.
    def[:body] = quote
        error("This function is not intended for use on the CPU")
    end

    esc(quote
        # Attach a preceding docstring to the host stub and therefore to the function
        # binding. The real implementation remains available only in the overlay.
        Base.@__doc__ $(combinedef(def))
        Base.Experimental.@overlay($method_table, $ex)
    end)
end

@public @device_function
