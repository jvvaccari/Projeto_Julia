module Quarto

using Random

export QuartoState,
       get_legal_actions,
       apply_action,
       check_win,
       is_terminal,
       play_game

const LINES = (
    (0, 1, 2, 3),
    (4, 5, 6, 7),
    (8, 9, 10, 11),
    (12, 13, 14, 15),
    (0, 4, 8, 12),
    (1, 5, 9, 13),
    (2, 6, 10, 14),
    (3, 7, 11, 15),
    (0, 5, 10, 15),
    (3, 6, 9, 12),
)

mutable struct QuartoState
    board::Vector{Union{Nothing, Int}}
    available_pieces::Vector{Int}
    piece_in_hand::Union{Nothing, Int}
    current_player::Int
end

QuartoState() = QuartoState(fill(nothing, 16), collect(0:15), nothing, 1)

function get_legal_actions(state::QuartoState)
    actions = Vector{Tuple{Union{Nothing, Int}, Union{Nothing, Int}}}()

    if state.piece_in_hand === nothing
        for piece in state.available_pieces
            push!(actions, (nothing, piece))
        end
        return actions
    end

    empty_spots = Int[]
    for (index, piece) in enumerate(state.board)
        if piece === nothing
            push!(empty_spots, index - 1)
        end
    end

    if isempty(state.available_pieces)
        for spot in empty_spots
            push!(actions, (spot, nothing))
        end
        return actions
    end

    for spot in empty_spots
        for piece in state.available_pieces
            push!(actions, (spot, piece))
        end
    end

    return actions
end

function apply_action(state::QuartoState, action::Tuple{Union{Nothing, Int}, Union{Nothing, Int}})
    new_state = QuartoState(copy(state.board), copy(state.available_pieces), state.piece_in_hand, state.current_player)
    position, next_piece = action

    if position !== nothing
        new_state.board[position + 1] = new_state.piece_in_hand
    end

    if next_piece !== nothing
        filter!(piece -> piece != next_piece, new_state.available_pieces)
    end

    new_state.piece_in_hand = next_piece
    new_state.current_player = 3 - state.current_player
    return new_state
end

function check_win(state::QuartoState)
    for line in LINES
        pieces = Int[]
        for index in line
            piece = state.board[index + 1]
            if piece !== nothing
                push!(pieces, piece)
            end
        end

        if length(pieces) != 4
            continue
        end

        p0, p1, p2, p3 = pieces
        same_one = (p0 & p1 & p2 & p3) > 0
        same_zero = ((~p0 & ~p1 & ~p2 & ~p3) & 15) > 0
        if same_one || same_zero
            return 3 - state.current_player
        end
    end

    return nothing
end

function is_terminal(state::QuartoState)
    winner = check_win(state)
    if winner !== nothing
        return true
    end
    return all(piece !== nothing for piece in state.board)
end

function format_piece(piece::Union{Nothing, Int})
    if piece === nothing
        return "[    ]"
    end
    return "[" * lpad(string(piece, base=2), 4, '0') * "]"
end

function print_board(state::QuartoState)
    println("\n" * repeat("=", 30))
    println("      TABULEIRO QUARTO      ")
    println(repeat("=", 30))

    for row in 0:3
        cells = [format_piece(state.board[row * 4 + column + 1]) for column in 0:3]
        println("L$(row):  " * join(cells, "  "))
    end

    println("\nPeças disponíveis:")
    available = ["$(piece) ($(lpad(string(piece, base=2), 4, '0')) )" for piece in state.available_pieces]
    for index in 1:length(available)
        print(available[index])
        if index % 4 != 0 && index != length(available)
            print(" | ")
        elseif index % 4 == 0 && index != length(available)
            println()
        end
    end
    println()

    if state.piece_in_hand !== nothing
        println("\n=> Peça a colocar: $(state.piece_in_hand) ($(lpad(string(state.piece_in_hand, base=2), 4, '0')))")
    end
    println(repeat("=", 30))
end

function human_turn(state::QuartoState)
    print_board(state)
    legal_actions = get_legal_actions(state)
    position = nothing
    next_piece = nothing

    if state.piece_in_hand !== nothing
        while true
            try
                row = parse(Int, readline())
                column = parse(Int, readline())
                position = row * 4 + column
                if 0 <= row <= 3 && 0 <= column <= 3 && state.board[position + 1] === nothing
                    break
                end
                println("Posição inválida ou já ocupada.")
            catch
                println("Por favor, introduza um número válido.")
            end
        end
    end

    if !isempty(state.available_pieces)
        while true
            try
                next_piece = parse(Int, readline())
                if next_piece in state.available_pieces
                    break
                end
                println("Peça indisponível. Escolha da lista.")
            catch
                println("Por favor, introduza um número válido.")
            end
        end
    end

    action = (position, next_piece)
    if action ∉ legal_actions
        println("Ação ilegal. Tente novamente.")
        return human_turn(state)
    end
    return action
end

function play_game(; ai_iterations=500)
    println("Bem-vindo ao QUARTO!")
    println("Modo: Humano vs MCTS")
    println("MCTS com $(ai_iterations) iterações")
    state = QuartoState()

    while !is_terminal(state)
        if state.current_player == 1
            println("\n--- SEU TURNO ---")
            action = human_turn(state)
        else
            println("\n--- TURNO DO AGENTE (MCTS) ---")
            action = mcts(state, ai_iterations)
            if action === nothing
                error("O agente não encontrou uma ação legal.")
            end
            println("O Agente colocou a peça na posição: $(action[1])")
            println("O Agente entregou-lhe a peça: $(action[2])")
        end
        state = apply_action(state, action)
    end

    print_board(state)
    winner = check_win(state)
    if winner !== nothing
        println("\nFIM DE JOGO! O Jogador $(winner) venceu!")
    else
        println("\nFIM DE JOGO! Empate!")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    play_game()
end

end
