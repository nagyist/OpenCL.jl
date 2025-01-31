# script to parse OpenCL headers and generate Julia wrappers


#
# Parsing
#

using Clang
using Clang.Generators

using JuliaFormatter

function wrap(name, headers...; defines=[], include_dirs=[], dependents=true)
    @info "Wrapping $name"

    args = get_default_args()
    for define in defines
        if isa(define, Pair)
            append!(args, ["-D", "$(first(define))=$(last(define))"])
        else
            append!(args, ["-D", "$define"])
        end
    end
    for include_dir in include_dirs
        push!(args, "-isystem$include_dir")
    end

    options = load_options(joinpath(@__DIR__, "$(name).toml"))

    # create context
    ctx = create_context([headers...], args, options)

    # run generator
    build!(ctx, BUILDSTAGE_NO_PRINTING)

    # if requested, only wrap stuff from the list of headers
    # (i.e., not from included ones)
    if !dependents
        function rewrite!(dag::ExprDAG)
            replace!(get_nodes(dag)) do node
                path = normpath(Clang.get_filename(node.cursor))
                if !in(path, headers)
                    return ExprNode(node.id, Generators.Skip(), node.cursor, Expr[], node.adj)
                end
                return node
            end
        end
        rewrite!(ctx.dag)
    end

    rewriter!(ctx, options)

    build!(ctx, BUILDSTAGE_PRINTING_ONLY)

    output_file = options["general"]["output_file_path"]

    # prepend "autogenerated, do not edit!" comment
    output_data = read(output_file, String)
    open(output_file, "w") do io
        println(io, """# This file is automatically generated. Do not edit!
                       # To re-generate, execute res/wrap/wrap.jl""")
        println(io)
        print(io, output_data)
    end

    format_file(output_file, YASStyle())

    return
end

function rewriter!(ctx, options)
    for node in get_nodes(ctx.dag)
        if Generators.is_function(node) && !Generators.is_variadic_function(node)
            expr = node.exprs[1]
            call_expr = expr.args[2].args[1].args[3]    # assumes `@ccall`

            target_expr = call_expr.args[1].args[1]
            fn = String(target_expr.args[2].value)

            # replace `@ccall` with `@ext_ccall` when dealing with an extension function
            if basename(get_filename(node.cursor)) == "cl_ext.h"
                expr.args[2].args[1].args[1] = Symbol("@ext_ccall")
            end

            # rewrite pointer return types
            if haskey(options, "api") && haskey(options["api"], fn)
                rettype = get(options["api"][fn], "rettype", nothing)
                if rettype !== nothing
                    call_expr.args[2] = Meta.parse(rettype)
                end
            end

            # rewrite pointer argument types
            arg_exprs = call_expr.args[1].args[2:end]
            if haskey(options, "api") && haskey(options["api"], fn)
                argtypes = get(options["api"][fn], "argtypes", Dict())
                for (arg, typ) in argtypes
                    i = parse(Int, arg)
                    arg_exprs[i].args[2] = Meta.parse(typ)
                end
            end

            # insert `@checked` before each function with a `ccall` returning a checked type`
            rettyp = call_expr.args[2]
            checked_types = if haskey(options, "api")
                get(options["api"], "checked_rettypes", String[])
            else
                String[]
            end
            if rettyp isa Symbol && String(rettyp) in checked_types
                node.exprs[1] = Expr(:macrocall, Symbol("@checked"), nothing, expr)
            end
        end

        if node isa ExprNode{<:AbstractMacroNodeType}
            isempty(node.exprs) && continue
            expr = node.exprs[1]
            if Meta.isexpr(expr, :const)
                expr = expr.args[1]
            end
            if Meta.isexpr(expr, :(=))
                lhs, rhs = expr.args
                if rhs isa Expr && rhs.head == :call
                    name = string(rhs.args[1])
                    if name == "CL_MAKE_VERSION"
                        rhs.head = :macrocall
                        rhs.args[1] = Symbol("@", name)
                        insert!(rhs.args, 2, nothing)
                    end
                end
            end
        end
    end
end


#
# Main application
#

using OpenCL_Headers_jll

function main()
    headers = ["cl.h", "cl_gl.h", "cl_ext.h"]
    include_dir = joinpath(OpenCL_Headers_jll.artifact_dir, "include")
    paths = map(headers) do header
        joinpath(include_dir, "CL", header)
    end
    cd(@__DIR__) do
        wrap("opencl", paths...; include_dirs=[include_dir],
             defines=["CL_TARGET_OPENCL_VERSION" => "300"],)
    end
end

isinteractive() || main()
