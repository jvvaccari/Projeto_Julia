include("quarto.jl")
include("mcts.jl")
include("web_api.jl")

function main()
    if length(ARGS) > 0 && ARGS[1] == "server"
        port = length(ARGS) > 1 ? parse(Int, ARGS[2]) : 8000
        start_server("127.0.0.1", port)
        return
    end

    Quarto.play_game()
end

main()
