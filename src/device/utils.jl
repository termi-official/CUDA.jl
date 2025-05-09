# helpers for writing device functionality

# local method table for device functions
@static if isdefined(Base.Experimental, Symbol("@overlay"))
Base.Experimental.@MethodTable(method_table)
else
const method_table = nothing
end

macro device_override(ex)
    ex = macroexpand(__module__, ex)
    if VERSION >= v"1.12.0-DEV.745" || v"1.11-rc1" <= VERSION < v"1.12-"
        # this requires that the overlay method f′ is consistent with f, i.e.,
        #   - if f(x) returns a value, f′(x) must return the identical value.
        #   - if f(x) throws an exception, f′(x) must also throw an exception
        #     (although the exceptions do not need to be identical).
        esc(quote
            Base.Experimental.@consistent_overlay(CUDA.method_table, $ex)
        end)
    else
        esc(quote
            Base.Experimental.@overlay(CUDA.method_table, $ex)
        end)
    end
end

macro device_function(ex)
    ex = macroexpand(__module__, ex)
    def = splitdef(ex)

    # generate a function that errors
    def[:body] = quote
        error("This function is not intended for use on the CPU")
    end

    esc(quote
        $(combinedef(def))

        # NOTE: no use of `@consistent_overlay` here because the regular function errors
        Base.Experimental.@overlay(CUDA.method_table, $ex)
    end)
end

macro device_functions(ex)
    ex = macroexpand(__module__, ex)

    # recursively prepend `@device_function` to all function definitions
    function rewrite(block)
        out = Expr(:block)
        for arg in block.args
            if Meta.isexpr(arg, :block)
                # descend in blocks
                push!(out.args, rewrite(arg))
            elseif Meta.isexpr(arg, [:function, :(=)])
                # rewrite function definitions
                push!(out.args, :(@device_function $arg))
            else
                # preserve all the rest
                push!(out.args, arg)
            end
        end
        out
    end

    esc(rewrite(ex))
end


## alignment API

# we don't expose this as Aligned{N}, because we want to have the T typevar first
# to facilitate use in function signatures as ::Aligned{<:T}

struct Aligned{T, N}
    data::T
end

alignment(::Aligned{<:Any, N}) where {N} = N
Base.getindex(x::Aligned) = x.data

"""
    CUDA.align{N}(obj)

Construct an aligned object, providing alignment information to APIs that require it.
"""
struct align{N} end
(::Type{align{N}})(data::T) where {T,N} = Aligned{T,N}(data)

# default alignment for common types
Aligned(x::Aligned) = x
Aligned(x::Ptr{T}) where T = align{Base.datatype_alignment(T)}(x)
Aligned(x::LLVMPtr{T}) where T = align{Base.datatype_alignment(T)}(x)
