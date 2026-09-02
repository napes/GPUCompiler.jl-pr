using InteractiveUtils

# Definitions are registered at top level because overlay registration itself is a
# top-level operation. The Native test target supplies a backend-owned method table and
# compiles through it without requiring a GPU.

GPUCompiler.@device_function Native.test_method_table df_direct() =
    ccall("extern synthetic.device.direct", llvmcall, Cvoid, ())

GPUCompiler.@device_function Native.test_method_table @inline df_inline() =
    ccall("extern synthetic.device.inline", llvmcall, Cvoid, ())

GPUCompiler.@device_function Native.test_method_table @generated function df_generated(
    ::Type{T},
) where {T}
    return :(ccall("extern synthetic.device.generated", llvmcall, Cvoid, ()))
end

"""
Synthetic documented device function.
"""
GPUCompiler.@device_function Native.test_method_table df_documented() =
    ccall("extern synthetic.device.documented", llvmcall, Cvoid, ())

begin
    GPUCompiler.@device_function Native.test_method_table df_nested_block() =
        ccall("extern synthetic.device.block", llvmcall, Cvoid, ())
end

if true
    GPUCompiler.@device_function Native.test_method_table df_conditional() =
        ccall("extern synthetic.device.conditional", llvmcall, Cvoid, ())
end

const backend_method_table = Native.test_method_table
macro backend_device_function(ex)
    esc(:($GPUCompiler.@device_function($backend_method_table, $ex)))
end

@backend_device_function df_wrapped() =
    ccall("extern synthetic.device.wrapped", llvmcall, Cvoid, ())

module DeviceFunctionSubmodule
using ..GPUCompiler
using ..Native

const method_table = Native.test_method_table

GPUCompiler.@device_function method_table df_submodule() =
    ccall("extern synthetic.device.submodule", llvmcall, Cvoid, ())

call_submodule() = df_submodule()
end

call_direct() = df_direct()
call_inline() = df_inline()
call_generated() = df_generated(Int32)
call_documented() = df_documented()
call_nested_block() = df_nested_block()
call_conditional() = df_conditional()
call_wrapped() = df_wrapped()

const DEVICE_FUNCTION_CASES = (
    (df_direct, Tuple{}, call_direct, "synthetic.device.direct"),
    (df_inline, Tuple{}, call_inline, "synthetic.device.inline"),
    (df_generated, Tuple{Type{Int32}}, call_generated, "synthetic.device.generated"),
    (df_documented, Tuple{}, call_documented, "synthetic.device.documented"),
    (df_nested_block, Tuple{}, call_nested_block, "synthetic.device.block"),
    (df_conditional, Tuple{}, call_conditional, "synthetic.device.conditional"),
    (df_wrapped, Tuple{}, call_wrapped, "synthetic.device.wrapped"),
    (
        DeviceFunctionSubmodule.df_submodule,
        Tuple{},
        DeviceFunctionSubmodule.call_submodule,
        "synthetic.device.submodule",
    ),
)

@testset "device-only function declaration" begin
    @testset "host stubs" begin
        for (f, signature, _, _) in DEVICE_FUNCTION_CASES
            args = map(_ -> Int32, signature.parameters)
            @test_throws "not intended for use on the CPU" f(args...)
        end
    end

    @testset "host AOT isolation" begin
        for (_, _, caller, _) in DEVICE_FUNCTION_CASES
            ir = sprint(io -> code_llvm(
                io,
                caller,
                Tuple{};
                raw=true,
                dump_module=true,
                optimize=false,
            ))
            @test !occursin("synthetic.device", ir)
        end
    end

    @testset "device overlay" begin
        for (_, _, caller, symbol) in DEVICE_FUNCTION_CASES
            ir = sprint(io -> Native.code_llvm(io, caller, Tuple{}))
            @test occursin(symbol, ir)
            @test !occursin("not intended for use on the CPU", ir)
        end
    end

    @testset "documentation" begin
        doc = Base.Docs.doc(df_documented)
        @test doc !== nothing
        @test occursin("Synthetic documented device function", sprint(show, doc))
    end
end
