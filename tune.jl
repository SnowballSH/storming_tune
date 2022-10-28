using Dates

ENGINE_REPO = "https://github.com/SnowballSH/Avalanche"
ENGINE_FOLDER = "engine/"
UPDATE_ENGINE = true

ENGINE_BUILD_COMMAND = `zig build -Drelease-fast -Dtarget-name=engine -p ./`
ENGINE_FILE = "$(ENGINE_FOLDER)/bin/engine"

PRECISION = 10

# https://www.chessprogramming.org/Stockfish%27s_Tuning_Method
# (Name, Base, MinDelta:MaxDelta, do_tune?, float?)
PARAMETERS = [
    ("LMRWeight", 0.647173874704215, Int(-0.40 * 10^PRECISION):Int(0.40 * 10^PRECISION), false, true),
    ("LMRBias", 1.301347679383754, Int(-0.70 * 10^PRECISION):Int(0.70 * 10^PRECISION), false, true),
    ("RFPDepth", 5, -4:4, false, false),
    ("RFPMultiplier", 62, -40:40, false, false),
    ("RFPImprovingDeduction", 70, -40:40, false, false),
    ("NMPBase", 5, -2:2, false, false),
    ("NMPDepthDivisor", 5, -2:2, false, false),
    ("NMPBetaDivisor", 214, -80:80, false, false),
    ("RazoringMargin", 320, -200:200, false, false),
    ("AspirationWindow", 15, -11:11, true, false),
    ("AspirationWindowBonus", 1.35, Int(-0.9 * 10^PRECISION):Int(0.9 * 10^PRECISION), true, true),
]

# This is multiplied to delta
APPLY_FACTOR = 0.44

CUTECHESS_COMMAND = "cutechess-cli"
CONCURRENCY = 8
GAMES = 32
BOOK = "noob_4moves.epd"
TC = "12+0.12"
NUM_ITERS = 8

function download_latest_engine()
    if (isdir(ENGINE_FOLDER))
        # Warning: Do not set ENGINE_FOLDER to something dangerous
        rm(ENGINE_FOLDER, recursive=true)
    end

    mkdir(ENGINE_FOLDER)

    run(`git clone --depth 1 $ENGINE_REPO $ENGINE_FOLDER`, wait=true)
end

function build_engine(name::String)
    run(Cmd(ENGINE_BUILD_COMMAND, dir=ENGINE_FOLDER), wait=true)

    if !isdir("temp/")
        mkdir("temp/")
    end

    cp(ENGINE_FILE, "temp/$name", force=true)
end

function test_engines(a::String, b::String)::AbstractFloat
    cmd_str::String = CUTECHESS_COMMAND

    cmd_str *= " -repeat -recover -resign movecount=4 score=500 -draw movenumber=40 movecount=6 score=5"
    cmd_str *= " -srand $(millisecond(unix2datetime(time())) * rand(1:50) * rand(1:50)) -concurrency $CONCURRENCY -games $GAMES"
    cmd_str *= " -engine dir=temp/ cmd=./$a proto=uci tc=$TC name=A"
    cmd_str *= " -engine dir=temp/ cmd=./$b proto=uci tc=$TC name=B"
    cmd_str *= " -openings file=$BOOK format=epd order=random plies=8"

    cmd = Cmd(map(x -> String(x), split(cmd_str, ' ')))
    out = IOBuffer()

    run(pipeline(cmd, stdout=out, stderr=devnull), wait=true)

    lines = split(String(take!(out)), '\n')
    reverse!(lines)
    for line = lines
        if startswith(line, "Score of A vs B: ")
            println(line)
            res = parse(Float64, split(split(line, '[')[2], ']')[1])
            return res
        end
    end

    error("No Result")
    return 0.0
end

smooth(x::AbstractFloat)::AbstractFloat = ℯ * log(x / (1 - x))

function update_value(prev_val::AbstractFloat, change::AbstractFloat, result::AbstractFloat)::AbstractFloat
    # Result of (prev_val + delta) vs (prev_val - delta) is (result)
    if result == 0.5
        prev_val += rand((-0.15, -0.07, 0.07, 0.15)) * change  # add some noises
    else
        prev_val += smooth(result) * change
    end
    return max(eps(), prev_val)
end

__dt = rng::UnitRange{Int} -> rng[Int(clamp(round((clamp(randn(), -4.0, 4.0) + 4.0) / 8.0 * (length(rng) + 1)), 1, length(rng)))]

function choose_delta(rng::UnitRange{Int})::Int
    k::Int = __dt(rng)
    i::Int = 0
    while k == 0
        i += 1
        if i > 50  # Taking too long
            break
        end
        k = __dt(rng)
    end
    return k
end

# Modify to adapt other formats
function param_to_code(params)::String
    s::String = ""
    for (i, param) = enumerate(params)
        if PARAMETERS[i][5]
            s *= "pub const $(param[1]) = $(round(param[2], digits=PRECISION));\n"
        else
            s *= "pub const $(param[1]) = $(Int(round(param[2])));\n"
        end
    end
    return s
end

function tune()
    current_params = []
    for param = PARAMETERS
        push!(current_params, (param[1], Float64(param[2])))
    end

    deltas = zeros(length(PARAMETERS))

    open("$ENGINE_FOLDER/src/engine/parameters.zig", "w") do io
        write(io, param_to_code(current_params))
    end

    println("Building Base...")

    build_engine("base")

    for iter = 1:NUM_ITERS
        println("Iteration $iter")

        a_params = copy(current_params)
        b_params = copy(current_params)
        for i in eachindex(PARAMETERS)
            if PARAMETERS[i][4]  # is tuning
                dt = choose_delta(PARAMETERS[i][3])
                if PARAMETERS[i][5]
                    dt *= (1.0 / 10^PRECISION)
                end
                deltas[i] = dt
                a_params[i] = (a_params[i][1], max(0.0, a_params[i][2] + dt))
                b_params[i] = (b_params[i][1], max(0.0, b_params[i][2] - dt))
            end
        end

        println("Building...")

        open("$ENGINE_FOLDER/src/engine/parameters.zig", "w") do io
            write(io, param_to_code(a_params))
        end
        build_engine("a")
        open("$ENGINE_FOLDER/src/engine/parameters.zig", "w") do io
            write(io, param_to_code(b_params))
        end
        build_engine("b")

        println("Starting Match...")
        res::AbstractFloat = test_engines("a", "b")
        println("Updating weights...")
        for i in eachindex(PARAMETERS)
            if PARAMETERS[i][4]
                current_params[i] = (current_params[i][1], update_value(current_params[i][2], APPLY_FACTOR * deltas[i], res))
            end
        end

        println("Weight after Iteration $iter:")

        for i in eachindex(PARAMETERS)
            if PARAMETERS[i][4]
                println(current_params[i][1], " = ", current_params[i][2])
            end
        end
    end


    println("Finishing Off with match vs base engine...")

    open("$ENGINE_FOLDER/src/engine/parameters.zig", "w") do io
        write(io, param_to_code(current_params))
    end

    build_engine("b")

    println("Match after tuning: $(test_engines("b", "base"))")
end

function main()
    if UPDATE_ENGINE || !isdir(ENGINE_FOLDER)
        download_latest_engine()
    end

    tune()
end

main()
