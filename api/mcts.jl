module MCTS

using Random
using Main.Quarto

export MCTSNode,
       ucb1,
       mcts

mutable struct MCTSNode
    state::Quarto.QuartoState
    parent::Union{MCTSNode, Nothing}
    action_taken::Union{Tuple{Union{Nothing, Int}, Union{Nothing, Int}}, Nothing}
    children::Vector{MCTSNode}
    untried_actions::Vector{Tuple{Union{Nothing, Int}, Union{Nothing, Int}}}
    visits::Int
    wins::Float64
end

function MCTSNode(state::Quarto.QuartoState, parent::Union{MCTSNode, Nothing}=nothing, action_taken::Union{Tuple{Union{Nothing, Int}, Union{Nothing, Int}}, Nothing}=nothing)
    return MCTSNode(state, parent, action_taken, MCTSNode[], Quarto.get_legal_actions(state), 0, 0.0)
end

function ucb1(node::MCTSNode; exploration_weight::Float64=1.41)
    if node.visits == 0 || node.parent === nothing
        return Inf
    end
    return (node.wins / node.visits) + exploration_weight * sqrt(log(node.parent.visits) / node.visits)
end

function mcts(root_state::Quarto.QuartoState, iterations::Int)
    root = MCTSNode(root_state)

    for _ in 1:iterations
        node = root

        while isempty(node.untried_actions) && !isempty(node.children)
            node = argmax(node.children) do child
                ucb1(child)
            end
        end

        if !isempty(node.untried_actions) && !Quarto.is_terminal(node.state)
            action = rand(node.untried_actions)
            deleteat!(node.untried_actions, findfirst(==(action), node.untried_actions))
            child_state = Quarto.apply_action(node.state, action)
            child = MCTSNode(child_state, node, action)
            push!(node.children, child)
            node = child
        end

        simulated_state = deepcopy(node.state)
        while !Quarto.is_terminal(simulated_state)
            actions = Quarto.get_legal_actions(simulated_state)
            action = rand(actions)
            simulated_state = Quarto.apply_action(simulated_state, action)
        end

        winner = Quarto.check_win(simulated_state)
        current = node
        while current !== nothing
            current.visits += 1
            if winner == 3 - current.state.current_player
                current.wins += 1.0
            elseif winner === nothing
                current.wins += 0.5
            end
            current = current.parent
        end
    end

    if isempty(root.children)
        error("Nenhuma ação legal encontrada para o MCTS.")
    end

    best_child = argmax(root.children) do child
        child.visits
    end
    return best_child.action_taken
end

end
