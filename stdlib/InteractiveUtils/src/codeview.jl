# This file is a part of Julia. License is MIT: https://julialang.org/license

# displaying type warnings

function warntype_type_printer(io::IO, @nospecialize(ty))
    if ty isa Type && (!Base.isdispatchelem(ty) || ty == Core.Box)
        if ty isa Union && Base.is_expected_union(ty)
            Base.emphasize(io, "::$ty", Base.warn_color()) # more mild user notification
        else
            Base.emphasize(io, "::$ty")
        end
    else
        Base.printstyled(io, "::$ty", color=:cyan)
    end
    nothing
end

"""
    code_warntype([io::IO], f, types; verbose_linetable=false)

Prints lowered and type-inferred ASTs for the methods matching the given generic function
and type signature to `io` which defaults to `stdout`. The ASTs are annotated in such a way
as to cause "non-leaf" types to be emphasized (if color is available, displayed in red).
This serves as a warning of potential type instability. Not all non-leaf types are particularly
problematic for performance, so the results need to be used judiciously.
In particular, unions containing either [`missing`](@ref) or [`nothing`](@ref) are displayed in yellow, since
these are often intentional.
If the `verbose_linetable` keyword is set, the linetable will be printed
in verbose mode, showing all available information (rather than applying
the usual heuristics).
See [`@code_warntype`](@ref man-code-warntype) for more information.
"""
function code_warntype(io::IO, @nospecialize(f), @nospecialize(t); verbose_linetable=false)
    for (src, rettype) in code_typed(f, t)
        print(io, "Body")
        warntype_type_printer(io, rettype)
        println(io)
        # TODO: static parameter values
        ir = Core.Compiler.inflate_ir(src)
        Base.IRShow.show_ir(io, ir, warntype_type_printer;
                            argnames = Base.sourceinfo_slotnames(src),
                            verbose_linetable = verbose_linetable)
    end
    nothing
end
code_warntype(@nospecialize(f), @nospecialize(t); kwargs...) =
    code_warntype(stdout, f, t; kwargs...)

import Base.CodegenParams

# Printing code representations in IR and assembly
function _dump_function(@nospecialize(f), @nospecialize(t), native::Bool, wrapper::Bool,
                        strip_ir_metadata::Bool, dump_module::Bool, syntax::Symbol=:att,
                        optimize::Bool=true, params::CodegenParams=CodegenParams())
    ccall(:jl_is_in_pure_context, Bool, ()) && error("code reflection cannot be used from generated functions")
    if isa(f, Core.Builtin)
        throw(ArgumentError("argument is not a generic function"))
    end
    # get the MethodInstance for the method match
    world = typemax(UInt)
    meth = which(f, t)
    t = to_tuple_type(t)
    tt = signature_type(f, t)
    (ti, env) = ccall(:jl_type_intersection_with_env, Any, (Any, Any), tt, meth.sig)::Core.SimpleVector
    meth = Base.func_for_method_checked(meth, ti)
    linfo = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance}, (Any, Any, Any, UInt), meth, ti, env, world)
    # get the code for it
    if native
        str = _dump_function_linfo_native(linfo, world, wrapper, syntax)
    else
        str = _dump_function_linfo_llvm(linfo, world, wrapper, strip_ir_metadata, dump_module, optimize, params)
    end
    # TODO: use jl_is_cacheable_sig instead of isdispatchtuple
    isdispatchtuple(linfo.specTypes) || (str = "; WARNING: This code may not match what actually runs.\n" * str)
    return str
end

function _dump_function_linfo_native(linfo::Core.MethodInstance, world::UInt, wrapper::Bool, syntax::Symbol=:att)
    if syntax != :att && syntax != :intel
        throw(ArgumentError("'syntax' must be either :intel or :att"))
    end
    str = ccall(:jl_dump_method_asm, Ref{String},
                (Any, UInt, Cint, Bool, Ptr{UInt8}), linfo, world, 0, wrapper, syntax)
    return str
end

function _dump_function_linfo_llvm(
        linfo::Core.MethodInstance, world::UInt, wrapper::Bool,
        strip_ir_metadata::Bool, dump_module::Bool,
        optimize::Bool=true, params::CodegenParams=CodegenParams())
    llvmf = ccall(:jl_get_llvmf_defn, Ptr{Cvoid}, (Any, UInt, Bool, Bool, CodegenParams), linfo, world, wrapper, optimize, params)
    llvmf == C_NULL && error("could not compile the specified method")
    str = ccall(:jl_dump_function_ir, Ref{String},
                (Ptr{Cvoid}, Bool, Bool), llvmf, strip_ir_metadata, dump_module)
    return str
end

"""
    code_llvm([io=stdout,], f, types)

Prints the LLVM bitcodes generated for running the method matching the given generic
function and type signature to `io`.

All metadata and dbg.* calls are removed from the printed bitcode. Use `code_llvm_raw` for the full IR.
"""
code_llvm(io::IO, @nospecialize(f), @nospecialize(types=Tuple), strip_ir_metadata=true, dump_module=false) =
    print(io, _dump_function(f, types, false, false, strip_ir_metadata, dump_module))
code_llvm(@nospecialize(f), @nospecialize(types=Tuple)) = code_llvm(stdout, f, types)
code_llvm_raw(@nospecialize(f), @nospecialize(types=Tuple)) = code_llvm(stdout, f, types, false)

"""
    code_native([io=stdout,], f, types; syntax = :att)

Prints the native assembly instructions generated for running the method matching the given
generic function and type signature to `io`.
Switch assembly syntax using `syntax` symbol parameter set to `:att` for AT&T syntax or `:intel` for Intel syntax.
"""
code_native(io::IO, @nospecialize(f), @nospecialize(types=Tuple); syntax::Symbol = :att) =
    print(io, _dump_function(f, types, true, false, false, false, syntax))
code_native(@nospecialize(f), @nospecialize(types=Tuple); syntax::Symbol = :att) =
    code_native(stdout, f, types, syntax = syntax)
code_native(::IO, ::Any, ::Symbol) = error("illegal code_native call") # resolve ambiguous call
