# This file is a part of Julia. License is MIT: https://julialang.org/license

function needs_USE_GPL_LIBS(s::String)
    occursin("CHOLMOD", s) && return true
    return false
end

const HEADER = """
# This file is a part of Julia. License is MIT: https://julialang.org/license

# Steps to regenerate this file:
# 1. Remove all `precompile` calls
# 2. Rebuild system image
# 4. Run `./julia --trace-compile 2> precompiles.txt` and do various things.
# 5. Run `./julia contrib/fixup_precompile.jl precompiles.txt to overwrite `precompile.jl`
#    or ./julia contrib/fixup_precompile.jl --merge precompiles.txt to merge into existing
#    `precompile.jl`
"""

function fixup_precompile(new_precompile_file; merge, keep_anonymous, header, output)
    precompile_statements = Set{String}()

    isfile(output) || touch(output)
    for file in [new_precompile_file; merge ? output : []]
        for line in eachline(file)
            line = strip(line)
            # filter out closures, which might have different generated names in different environments
            if !keep_anonymous && occursin(r"#[0-9]", line)
                continue
            end

            # WAOW!
            line = replace(line, "FakeTerminals.FakeTerminal" => "REPL.Terminals.TTYTerminal")

            (occursin(r"Main.", line) || occursin(r"FakeTerminals.", line)) && continue
            # Other stuff than precompile statements might have been written to STDERR
            startswith(line, "precompile(Tuple{") || continue
            # Ok, add the line
            push!(precompile_statements, line)
        end
    end

    open(output, "w") do f
        if header
            println(f, HEADER)
            println(f, """
            let
            PrecompileStagingArea = Module()
            for (_pkgid, _mod) in Base.loaded_modules
                if !(_pkgid.name in ("Main", "Core", "Base"))
                    @eval PrecompileStagingArea \$(Symbol(_mod)) = \$_mod
                end
            end
            f = joinpath(@__DIR__, "precompile_local.jl")
            isfile(f) && include(PrecompileStagingArea, f)
            @eval PrecompileStagingArea begin
            """)
        end
        for statement in sort(collect(precompile_statements))
            isgpl = needs_USE_GPL_LIBS(statement)
            isgpl && print(f, "if Base.USE_GPL_LIBS\n    ")
            println(f, statement)
            isgpl && println(f, "end")
        end
        if header
            println(f, "end\nend")
        end
    end
    if merge
        "Merged $new_precompile_file into $output"
    else
        "Overwrote $output with $new_precompile_file"
    end
end

function runit()
    output = joinpath(Sys.BINDIR, "..", "..", "base", "precompile.jl")
    merge = false
    keep_anonymous = false
    header=true
    for arg in ARGS[1:end-1]
        if arg == "--merge"
            merge = true
        elseif arg == "--keep-anonymous"
            keep_anonymous = true
        elseif arg == "--no-header"
            header = false
        elseif startswith(arg, "--output")
            output = split(arg, "=")[2]
        else
            error("unknown argument $arg")
        end
    end
    fixup_precompile(joinpath(pwd(), ARGS[end]); merge=merge, keep_anonymous=keep_anonymous, header=header, output=output)
end

running_as_script = abspath(PROGRAM_FILE) == @__FILE__
if running_as_script
    runit()
end