using HTTP
using JSON3
using Sockets

using .MCTS

const SESSIONS = Dict{String, Dict{String, Any}}()

function find_winning_line(board)
    for line in Quarto.LINES
        pieces = [board[index + 1] for index in line]
        if any(piece === nothing for piece in pieces)
            continue
        end

        p0, p1, p2, p3 = pieces
        same_one = (p0 & p1 & p2 & p3) > 0
        same_zero = ((~p0 & ~p1 & ~p2 & ~p3) & 15) > 0
        if same_one || same_zero
            return collect(line)
        end
    end
    return nothing
end

function serialize_state(state::Quarto.QuartoState, mode::String, session_id::String)
    winner = Quarto.check_win(state)
    is_game_over = winner !== nothing || all(piece !== nothing for piece in state.board)
    winning_line = winner !== nothing ? find_winning_line(state.board) : nothing

    session = get(SESSIONS, session_id, Dict())
    override_winner = get(session, "winner_override", nothing)
    override_line = get(session, "winning_line_override", nothing)
    if override_winner !== nothing
        winner = override_winner
        winning_line = override_line
        is_game_over = true
    end

    return Dict(
        "session_id" => session_id,
        "mode" => mode,
        "board" => state.board,
        "available_pieces" => state.available_pieces,
        "piece_in_hand" => state.piece_in_hand,
        "current_player" => state.current_player,
        "winner" => winner,
        "winning_line" => winning_line,
        "is_game_over" => is_game_over,
    )
end

function get_ai_action(session)
    state = session["state"]
    mode = session["mode"]
    if mode == "mcts"
        return MCTS.mcts(state, 500)
    end
    return nothing
end

function run_ai_until_human_turn(session)
    while session["mode"] != "pvp" && session["state"].current_player == 2 && !Quarto.is_terminal(session["state"])
        action = get_ai_action(session)
        if action === nothing
            break
        end
        session["state"] = Quarto.apply_action(session["state"], action)
    end
end

function try_apply_immediate_win_action(session, position, next_piece)
    state = session["state"]

    if position === nothing || next_piece !== nothing
        return false
    end
    if state.piece_in_hand === nothing
        return false
    end
    if !(position isa Int) || position < 0 || position >= 16
        return false
    end
    if state.board[position + 1] !== nothing
        return false
    end

    temp_board = copy(state.board)
    temp_board[position + 1] = state.piece_in_hand
    if find_winning_line(temp_board) === nothing
        return false
    end

    new_state = deepcopy(state)
    new_state.board[position + 1] = new_state.piece_in_hand
    new_state.piece_in_hand = nothing

    session["state"] = new_state
    session["winner_override"] = state.current_player
    session["winning_line_override"] = find_winning_line(new_state.board)
    return true
end

function json_response(payload; status=200)
    body = JSON3.write(payload)
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
        ("Access-Control-Allow-Headers", "Content-Type"),
    ]
    return HTTP.Response(status, headers, body)
end

function serve_static(path::String)
    raw = read(path)
    kind = endswith(path, ".html") ? "text/html; charset=utf-8" : "application/javascript; charset=utf-8"
    headers = [
        ("Content-Type", kind),
        ("Access-Control-Allow-Origin", "*"),
    ]
    return HTTP.Response(200, headers, raw)
end

function handle_request(req::HTTP.Request)
    uri = HTTP.URI(req.target)
    path = uri.path

    if req.method == "OPTIONS"
        return HTTP.Response(204, [
            ("Access-Control-Allow-Origin", "*"),
            ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
            ("Access-Control-Allow-Headers", "Content-Type"),
        ])
    end

    if path == "/health"
        return json_response(Dict("status" => "ok"))
    end

    if path == "/"
        project_root = joinpath(@__DIR__, "..")
        html_file = joinpath(project_root, "front", "quarto_board_game.html")
        return serve_static(html_file)
    end

    if path == "/quarto_board_game.js"
        project_root = joinpath(@__DIR__, "..")
        js_file = joinpath(project_root, "front", "quarto_board_game.js")
        return serve_static(js_file)
    end

    if path == "/api/state"
        query = HTTP.queryparams(uri)
        session_id = get(query, "session_id", nothing)
        if session_id === nothing || !haskey(SESSIONS, session_id)
            return json_response(Dict("error" => "Session not found."), status=404)
        end
        session = SESSIONS[session_id]
        return json_response(serialize_state(session["state"], session["mode"], session_id))
    end

    if path == "/api/new-game"
        payload = isempty(String(req.body)) ? Dict() : JSON3.read(String(req.body), Dict{String, Any})
        mode = get(payload, "mode", "pvp")
        if mode ∉ ("pvp", "mcts")
            return json_response(Dict("error" => "Invalid mode."), status=400)
        end

        session_id = string(rand(UInt128))
        SESSIONS[session_id] = Dict(
            "state" => Quarto.QuartoState(),
            "mode" => mode,
            "winner_override" => nothing,
            "winning_line_override" => nothing,
        )
        session = SESSIONS[session_id]
        return json_response(serialize_state(session["state"], mode, session_id), status=201)
    end

    if path == "/api/action"
        payload = isempty(String(req.body)) ? Dict() : JSON3.read(String(req.body), Dict{String, Any})
        session_id = get(payload, "session_id", nothing)
        position = get(payload, "position", nothing)
        next_piece = get(payload, "next_piece", nothing)

        if session_id === nothing || !haskey(SESSIONS, session_id)
            return json_response(Dict("error" => "Session not found."), status=404)
        end

        session = SESSIONS[session_id]
        state = session["state"]

        if session["winner_override"] !== nothing
            return json_response(Dict("error" => "Game is already over."), status=400)
        end
        if Quarto.is_terminal(state)
            return json_response(Dict("error" => "Game is already over."), status=400)
        end

        if try_apply_immediate_win_action(session, position, next_piece)
            return json_response(serialize_state(session["state"], session["mode"], session_id))
        end

        action = (position, next_piece)
        legal_actions = Quarto.get_legal_actions(state)
        if action ∉ legal_actions
            return json_response(Dict("error" => "Illegal action."), status=400)
        end

        session["state"] = Quarto.apply_action(state, action)
        run_ai_until_human_turn(session)
        return json_response(serialize_state(session["state"], session["mode"], session_id))
    end

    return json_response(Dict("error" => "Route not found."), status=404)
end

function next_free_port(start_port::Int=8000; max_attempts::Int=20)
    for port in start_port:(start_port + max_attempts - 1)
        try
            socket = Sockets.listen(Sockets.InetAddr(ip"127.0.0.1", port))
            close(socket)
            return port
        catch
        end
    end
    error("Nenhuma porta disponível entre $(start_port) e $(start_port + max_attempts - 1).")
end

function start_server(host::String="127.0.0.1", port::Int=8000)
    chosen_port = port
    try
        socket = Sockets.listen(Sockets.InetAddr(ip"127.0.0.1", port))
        close(socket)
    catch
        chosen_port = next_free_port(port)
        println("Porta $(port) em uso. Usando a porta livre $(chosen_port) em vez disso.")
    end

    println("Servidor Quarto Julia rodando em http://$(host):$(chosen_port)")
    HTTP.serve(handle_request, host, chosen_port)
end
