const API_BASE_URL = 'http://127.0.0.1:8000';

const INITIAL_STATE = {
    sessionId: null,
    board: Array(16).fill(null),
    availablePieces: Array.from({ length: 16 }, (_, i) => i),
    pieceInHand: null,
    currentPlayer: 1,
    gameMode: 'pvp',
    pendingPosition: null,
    isGameOver: false,
    winner: null,
    winningLine: null,
    aiThinking: false,
    lastError: null
};

let state = { ...INITIAL_STATE };

function syncStateFromServer(payload) {
    state.sessionId = payload.session_id;
    state.board = [...payload.board];
    state.availablePieces = [...payload.available_pieces];
    state.pieceInHand = payload.piece_in_hand;
    state.currentPlayer = payload.current_player;
    state.gameMode = payload.mode;
    state.isGameOver = payload.is_game_over;
    state.winner = payload.winner;
    state.winningLine = payload.winning_line ? [...payload.winning_line] : null;
    state.pendingPosition = null;
    state.lastError = null;
}

function isHumanTurn() {
    return state.gameMode === 'pvp' || state.currentPlayer === 1;
}

function getCurrentStep() {
    if (state.isGameOver) return 'GAME_OVER';
    if (state.pieceInHand === null) return 'SELECT_NEXT_PIECE';
    if (state.pendingPosition === null) return 'PLACE_PIECE';
    if (state.availablePieces.length === 0) return 'FINALIZE_NO_PIECE';
    return 'SELECT_NEXT_PIECE';
}

function getPieceAttributes(pieceId) {
    return {
        isTall: (pieceId & 8) !== 0,
        isDark: (pieceId & 4) !== 0,
        isSquare: (pieceId & 2) !== 0,
        isHollow: (pieceId & 1) !== 0,
        bitString: pieceId.toString(2).padStart(4, '0')
    };
}

function renderPieceElement(pieceId, sizeMultiplier = 1) {
    if (pieceId === null || pieceId === undefined) return null;

    const attr = getPieceAttributes(pieceId);
    const container = document.createElement('div');
    container.className = `quarto-piece ${attr.isTall ? 'piece-tall' : 'piece-short'} ${attr.isDark ? 'piece-dark' : 'piece-light'} ${attr.isSquare ? 'piece-square' : 'piece-round'} ${attr.isHollow ? 'piece-hollow' : ''}`;

    if (sizeMultiplier !== 1) {
        container.style.transform = `scale(${sizeMultiplier})`;
    }

    const bitTag = document.createElement('span');
    bitTag.className = 'text-[10px] font-mono font-extrabold opacity-70 select-none';
    bitTag.innerText = attr.bitString;
    container.appendChild(bitTag);

    return container;
}

function getDisplayBoard() {
    const board = [...state.board];
    if (state.pendingPosition !== null && state.pieceInHand !== null && board[state.pendingPosition] === null) {
        board[state.pendingPosition] = state.pieceInHand;
    }
    return board;
}

function isWinningPlacement(cellIndex) {
    if (state.pieceInHand === null) return false;
    if (state.board[cellIndex] !== null) return false;

    const testBoard = [...state.board];
    testBoard[cellIndex] = state.pieceInHand;

    const lines = [
        [0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15],
        [0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15],
        [0, 5, 10, 15], [3, 6, 9, 12]
    ];

    for (const line of lines) {
        const pieces = line.map(index => testBoard[index]);
        if (pieces.some(piece => piece === null)) continue;

        const [p0, p1, p2, p3] = pieces;
        const sameOne = (p0 & p1 & p2 & p3) > 0;
        const sameZero = ((~p0 & ~p1 & ~p2 & ~p3) & 15) > 0;
        if (sameOne || sameZero) {
            return true;
        }
    }

    return false;
}

async function apiPost(path, body) {
    const response = await fetch(`${API_BASE_URL}${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });
    const payload = await response.json();
    if (!response.ok) {
        throw new Error(payload.error || 'Request failed');
    }
    return payload;
}

function setModeButtonStyles() {
    ['pvp', 'mcts'].forEach(m => {
        const btn = document.getElementById(`mode-${m}`);
        if (m === state.gameMode) {
            btn.className = 'px-3 py-1.5 rounded-lg transition font-semibold bg-sky-500 text-white shadow';
        } else {
            btn.className = 'px-3 py-1.5 rounded-lg transition font-medium text-slate-300 hover:text-white';
        }
    });
}

function renderUI() {
    setModeButtonStyles();
    renderStatus();
    renderBoard();
    renderHandPiece();
    renderAvailablePieces();
}

function renderStatus() {
    const statusMsg = document.getElementById('status-message');
    const playerInd = document.getElementById('player-indicator');
    const aiThinking = document.getElementById('ai-thinking');

    if (state.aiThinking) {
        aiThinking.classList.remove('hidden');
    } else {
        aiThinking.classList.add('hidden');
    }

    if (state.currentPlayer === 1) {
        playerInd.className = 'w-3.5 h-3.5 rounded-full bg-sky-400 animate-pulse';
    } else {
        playerInd.className = 'w-3.5 h-3.5 rounded-full bg-amber-400 animate-pulse';
    }

    const playerText = state.currentPlayer === 1
        ? 'Player 1'
        : (state.gameMode === 'pvp' ? 'Player 2' : 'AI Agent');
    const step = getCurrentStep();

    if (state.lastError) {
        statusMsg.innerText = `Erro: ${state.lastError}`;
    } else if (!state.sessionId) {
        statusMsg.innerText = 'Conectando ao servidor...';
    } else if (step === 'GAME_OVER') {
        statusMsg.innerText = 'Game Over';
    } else if (step === 'PLACE_PIECE') {
        statusMsg.innerText = `${playerText}: Place the current piece on the board`;
    } else if (step === 'SELECT_NEXT_PIECE') {
        statusMsg.innerText = `${playerText}: Choose the next piece for the opponent`;
    } else {
        statusMsg.innerText = `${playerText}: Confirming move...`;
    }
}

function renderBoard() {
    const grid = document.getElementById('board-grid');
    grid.innerHTML = '';

    const displayBoard = getDisplayBoard();
    const step = getCurrentStep();
    const canPlace = !state.isGameOver && !state.aiThinking && isHumanTurn() && step === 'PLACE_PIECE';

    for (let i = 0; i < 16; i++) {
        const cell = document.createElement('div');
        const isWinningCell = state.winningLine && state.winningLine.includes(i);

        cell.className = `board-cell rounded-2xl flex items-center justify-center relative border border-slate-700/60 ${isWinningCell ? 'winning-cell border-2' : ''}`;

        if (canPlace && displayBoard[i] === null) {
            cell.classList.add('highlight-placeable');
            cell.onclick = () => handleCellClick(i);
        }

        const pieceId = displayBoard[i];
        if (pieceId !== null) {
            const pieceEl = renderPieceElement(pieceId);
            cell.appendChild(pieceEl);
        }

        grid.appendChild(cell);
    }
}

function renderHandPiece() {
    const container = document.getElementById('piece-in-hand-container');
    const bitCode = document.getElementById('hand-bit-code');
    container.innerHTML = '';

    if (state.pieceInHand !== null) {
        const pieceEl = renderPieceElement(state.pieceInHand, 1.1);
        container.appendChild(pieceEl);
        bitCode.innerText = `ID: ${state.pieceInHand} | Code: ${getPieceAttributes(state.pieceInHand).bitString}`;
    } else {
        container.innerHTML = '<span class="text-xs text-slate-500 italic">None Selected</span>';
        bitCode.innerText = '';
    }
}

function renderAvailablePieces() {
    const rack = document.getElementById('available-pieces-grid');
    const countLabel = document.getElementById('pieces-count');
    rack.innerHTML = '';

    countLabel.innerText = `${state.availablePieces.length} / 16 remaining`;

    const step = getCurrentStep();
    const canSelect = !state.isGameOver && !state.aiThinking && isHumanTurn() && step === 'SELECT_NEXT_PIECE';

    state.availablePieces.forEach(pieceId => {
        const wrapper = document.createElement('div');
        wrapper.className = 'p-2 rounded-xl bg-slate-800/60 border border-slate-700/40 flex items-center justify-center h-20 transition relative';

        if (canSelect) {
            wrapper.classList.add('piece-selectable');
            wrapper.onclick = () => handlePieceSelect(pieceId);
        }

        const pieceEl = renderPieceElement(pieceId, 0.75);
        wrapper.appendChild(pieceEl);
        rack.appendChild(wrapper);
    });
}

function showWinModal(winner) {
    const modal = document.getElementById('win-modal');
    const title = document.getElementById('win-title');
    const reason = document.getElementById('win-reason');

    if (winner === null) {
        title.innerText = 'Game Draw!';
        reason.innerText = 'All pieces placed without a winning line.';
    } else {
        const winnerName = winner === 1
            ? 'Player 1'
            : (state.gameMode === 'pvp' ? 'Player 2' : 'AI Agent');
        title.innerText = `${winnerName} Wins!`;
        reason.innerText = 'Successfully formed 4 matching attributes in a row!';
    }

    modal.classList.remove('opacity-0', 'pointer-events-none');
    document.getElementById('win-modal-card').classList.remove('scale-95');
}

function hideWinModal() {
    const modal = document.getElementById('win-modal');
    modal.classList.add('opacity-0', 'pointer-events-none');
    document.getElementById('win-modal-card').classList.add('scale-95');
}

function bindWinModalEvents() {
    const modal = document.getElementById('win-modal');
    modal.addEventListener('click', (event) => {
        if (event.target === modal) {
            hideWinModal();
        }
    });

    document.addEventListener('keydown', (event) => {
        if (event.key === 'Escape') {
            hideWinModal();
        }
    });
}

async function createNewGame(mode) {
    state.aiThinking = false;
    state.pendingPosition = null;
    state.lastError = null;
    hideWinModal();
    renderUI();

    try {
        const payload = await apiPost('/api/new-game', { mode });
        syncStateFromServer(payload);
        renderUI();
    } catch (error) {
        state.lastError = error.message;
        renderUI();
    }
}

async function submitAction(position, nextPiece) {
    if (!state.sessionId || state.isGameOver) return;

    state.aiThinking = state.gameMode !== 'pvp';
    state.lastError = null;
    renderUI();

    try {
        const payload = await apiPost('/api/action', {
            session_id: state.sessionId,
            position,
            next_piece: nextPiece
        });
        syncStateFromServer(payload);
        state.aiThinking = false;
        renderUI();

        if (state.isGameOver) {
            showWinModal(state.winner);
        }
    } catch (error) {
        state.aiThinking = false;
        state.lastError = error.message;
        renderUI();
    }
}

function setGameMode(mode) {
    state.gameMode = mode;
    createNewGame(mode);
}

function resetGame() {
    createNewGame(state.gameMode);
}

function handleCellClick(cellIndex) {
    if (state.isGameOver || state.aiThinking || !isHumanTurn()) return;
    if (getCurrentStep() !== 'PLACE_PIECE') return;
    if (state.board[cellIndex] !== null) return;

    state.pendingPosition = cellIndex;

    if (isWinningPlacement(cellIndex)) {
        submitAction(state.pendingPosition, null);
        return;
    }

    if (state.availablePieces.length === 0) {
        submitAction(state.pendingPosition, null);
        return;
    }

    renderUI();
}

function handlePieceSelect(pieceId) {
    if (state.isGameOver || state.aiThinking || !isHumanTurn()) return;
    if (getCurrentStep() !== 'SELECT_NEXT_PIECE') return;
    if (!state.availablePieces.includes(pieceId)) return;

    const position = state.pieceInHand === null ? null : state.pendingPosition;
    submitAction(position, pieceId);
}

window.onload = function() {
    bindWinModalEvents();
    setGameMode('pvp');
};
