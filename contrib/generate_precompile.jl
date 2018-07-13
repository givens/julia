
tmp = tempname()
if haskey(Base.loaded_modules, Base.PkgId(Base.UUID("3fa0cd96-eef1-5676-8a61-b3b8758bbffb"), "REPL"))
    # Have a REPL, start julia + load repl and execute the repl replay script
    run(pipeline(`$(Base.julia_cmd()) --trace-compile=yes -e '
        @async while true
            sleep(0.01)
            isdefined(Base, :active_repl) && exit(0)
        end' -i`; stderr = tmp))
    d = joinpath(@__DIR__, "precompile_replay.jl")
    run(pipeline(`$(Base.julia_cmd()) --trace-compile=yes $d`; stderr=tmp, append=true))
else
    # Just record the startup
    run(pipeline(`$(Base.julia_cmd()) --trace-compile=yes -e 'exit(0)'`; stderr=tmp))
end

include("fixup_precompile.jl")
fixup_precompile(tmp; merge=false, keep_anonymous=true, header=false, output=joinpath(@__DIR__, "..", "base/precompile_local.jl"))
rm(tmp)