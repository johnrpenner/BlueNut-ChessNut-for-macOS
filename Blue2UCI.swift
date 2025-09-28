//
//  Blue2UCI.swift v1.0
//  BlueNut to UCI ©2025 by John Roland Penner
//  Interprets ChessNut Air States to Chess Moves
//	
//  Created by John Roland Penner on 2025-09-28.
//


import Foundation

struct boardRecord {
    var who2move: Int = 0 // 0 = white, 1 = black (kept but unused for move detection)
    var halfmoves: Int = 0
    var square: [Int] = Array(repeating: 0, count: 64) // 64 squares, piece values
    var enPassantSq: Int? = nil
    var wCastleKside: Bool = true
    var wCastleQside: Bool = true
    var bCastleKside: Bool = true
    var bCastleQside: Bool = true
    var wHasCastled: Bool = false
    var bHasCastled: Bool = false
    var fischer: Bool = false
    var rookSq1: Int? = nil
    var rookSq2: Int? = nil
}

struct moveRecord {
    var fromSquare: Int? = nil
    var toSquare: Int? = nil
    var capturedPiece: Int? = nil
    var movingPiece: Int? = nil // Store piece type for capture validation
}

struct Difference: Equatable {
    let square: Int
    let oldPiece: Int
    let newPiece: Int
}

class Blue2UCI {
    
    // Piece values (matching Python constants)
    private let pieceValues: [String: Int] = [
        " ": 0, "q": 1, "k": 2, "b": 3, "p": 4, "n": 5,
        "R": 6, "P": 7, "r": 8, "B": 9, "N": 10, "Q": 11, "K": 12
    ]
    
    private let pieceSymbols: [Int: String] = [
        0: " ", 1: "q", 2: "k", 3: "b", 4: "p", 5: "n",
        6: "R", 7: "P", 8: "r", 9: "B", 10: "N", 11: "Q", 12: "K"
    ]
    
    // Current board state
    private var currentBoard = boardRecord()
    private var previousBoard = boardRecord()
    private var stableBoard = boardRecord()
    private var isFirstBoardState = true
    
    // Move detection state
    private var moveInProgress = false
    private var pendingMove = moveRecord()
    private var boardHistory: [boardRecord] = []
    private let maxHistorySize = 10
    private var pendingCaptureSquares: [Int] = []
    private var firstRemovedPiece: (square: Int, piece: Int)? = nil
    
    // Callbacks
    var onMoveDetected: ((String) -> Void)?
    var onLEDChange: (([String]) -> Void)?
    
    init() {
        // Initialize with empty board; first update sets stable baseline
        currentBoard.square = Array(repeating: 0, count: 64)
        stableBoard = currentBoard
        previousBoard = currentBoard
    }
    
    // Convert board data from BlueNutConnect to internal representation
    func updateBoardFromData(_ data: Data) {
        guard data.count >= 32 else { 
            print("Blue2UCI: Invalid data size: \(data.count)")
            return 
        }
        
        var newBoard = currentBoard
        
        // Convert from chessnut format to internal representation
        for i in 0..<32 {
            let byte = data[i]
            let leftPiece = Int(byte & 0x0F)
            let rightPiece = Int(byte >> 4)
            
            // Note: Chessnut sends data backwards, so we need to flip it
            let square1 = 63 - (i * 2)
            let square2 = 63 - (i * 2 + 1)
            
            if square1 >= 0 && square1 < 64 {
                newBoard.square[square1] = leftPiece
            }
            if square2 >= 0 && square2 < 64 {
                newBoard.square[square2] = rightPiece
            }
        }
        
        // Set first board as stable baseline
        if isFirstBoardState {
            print("Blue2UCI: Setting initial board as stable baseline")
            currentBoard = newBoard
            setCurrentBoardAsStable()
            isFirstBoardState = false
            return
        }
        
        processBoardUpdate(newBoard)
    }
    
    private func processBoardUpdate(_ newBoard: boardRecord) {
        // Check if board has actually changed
        if !boardsAreEqual(newBoard, currentBoard) {
            print("Blue2UCI: Board state changed")
            previousBoard = currentBoard
            currentBoard = newBoard
            
            addToHistory(newBoard)
            analyzeForMove()
        }
    }
    
    private func boardsAreEqual(_ board1: boardRecord, _ board2: boardRecord) -> Bool {
        return board1.square == board2.square
    }
    
    private func addToHistory(_ board: boardRecord) {
        boardHistory.append(board)
        if boardHistory.count > maxHistorySize {
            boardHistory.removeFirst()
        }
    }
    
    private func analyzeForMove() {
        let differences = findDifferences(from: stableBoard, to: currentBoard)
        
        if differences.isEmpty {
            // No differences, board is stable
            if moveInProgress {
                completeMove()
            }
            return
        }
        
        print("Blue2UCI: Detected \(differences.count) square changes")
        
        // Handle large difference counts (e.g., board reset)
        if differences.count > 10 {
            print("Blue2UCI: Too many changes (\(differences.count)), setting as stable baseline")
            setCurrentBoardAsStable()
            return
        }
        
        // Track differences
        var missingPieces: [Int] = []
        var appearedPieces: [Int] = []
        
        for diff in differences {
            if diff.oldPiece != 0 && diff.newPiece == 0 {
                missingPieces.append(diff.square)
            } else if diff.oldPiece == 0 && diff.newPiece != 0 {
                appearedPieces.append(diff.square)
            }
        }
        
        // Debug: Log differences for diagnosis
        print("Blue2UCI: Missing pieces at squares: \(missingPieces.map { squareIndexToName($0) })")
        print("Blue2UCI: Appeared pieces at squares: \(appearedPieces.map { squareIndexToName($0) })")
        
        // Handle single-difference updates (piece lifted)
        if differences.count == 1 && missingPieces.count == 1 {
            if !moveInProgress {
                moveInProgress = true
                firstRemovedPiece = (square: missingPieces[0], piece: stableBoard.square[missingPieces[0]])
                print("Blue2UCI: First piece removed: \(squareIndexToName(missingPieces[0])) (\(pieceSymbols[stableBoard.square[missingPieces[0]]] ?? "unknown"))")
                onLEDChange?([])
            }
            return
        }
        
        // Handle partial capture (two pieces removed)
        if differences.count == 2 && missingPieces.count == 2 {
            if !moveInProgress {
                moveInProgress = true
                firstRemovedPiece = (square: missingPieces[0], piece: stableBoard.square[missingPieces[0]])
                print("Blue2UCI: First piece removed: \(squareIndexToName(missingPieces[0])) (\(pieceSymbols[stableBoard.square[missingPieces[0]]] ?? "unknown"))")
                onLEDChange?([])
            }
            pendingCaptureSquares = missingPieces
            pendingMove.movingPiece = firstRemovedPiece?.piece
            print("Blue2UCI: Detected partial capture update at squares: \(missingPieces.map { squareIndexToName($0) })")
            return
        }
        
        // Check for capture completion
        if !pendingCaptureSquares.isEmpty && differences.count <= 3 {
            checkCaptureCompletion(differences: differences)
            if pendingMove.fromSquare != nil && pendingMove.toSquare != nil {
                completeMove()
                return
            }
        }
        
        // Simple move: one piece moved from one square to another
        if missingPieces.count == 1 && appearedPieces.count == 1 {
            pendingMove.fromSquare = missingPieces[0]
            pendingMove.toSquare = appearedPieces[0]
            let capturedPiece = stableBoard.square[appearedPieces[0]]
            if capturedPiece != 0 {
                pendingMove.capturedPiece = capturedPiece
                print("Blue2UCI: Detected possible capture move from \(squareIndexToName(missingPieces[0])) to \(squareIndexToName(appearedPieces[0]))")
            } else {
                print("Blue2UCI: Detected simple move from \(squareIndexToName(missingPieces[0])) to \(squareIndexToName(appearedPieces[0]))")
            }
            completeMove()
            return
        }
        
        // Capture move: two pieces disappear, one appears
        if missingPieces.count == 2 && appearedPieces.count == 1 {
            let toSquare = appearedPieces[0]
            let movingPiece = currentBoard.square[toSquare]
            let fromSquare = missingPieces.first { square in
                stableBoard.square[square] == movingPiece
            }
            if let fromSquare = fromSquare {
                pendingMove.fromSquare = fromSquare
                pendingMove.toSquare = toSquare
                pendingMove.capturedPiece = stableBoard.square[toSquare]
                print("Blue2UCI: Detected capture move from \(squareIndexToName(fromSquare)) to \(squareIndexToName(toSquare))")
                completeMove()
            } else {
                print("Blue2UCI: Failed to find matching fromSquare for capture move")
            }
            return
        }
        
        // Castling move: two pieces disappear, two appear
        if missingPieces.count == 2 && appearedPieces.count == 2 {
            detectCastling(missing: missingPieces, appeared: appearedPieces)
            if pendingMove.fromSquare != nil && pendingMove.toSquare != nil {
                completeMove()
            }
            return
        }
        
        // Handle new move starting while waiting for capture
        if !pendingCaptureSquares.isEmpty && differences.count >= 3 {
            let nonCaptureSquares = missingPieces.filter { !pendingCaptureSquares.contains($0) }
            let nonCaptureAppeared = appearedPieces.filter { !pendingCaptureSquares.contains($0) }
            if nonCaptureSquares.count == 1 && nonCaptureAppeared.count == 1 {
                // New simple move detected (e.g., g1f3)
                pendingMove.fromSquare = nonCaptureSquares[0]
                pendingMove.toSquare = nonCaptureAppeared[0]
                let capturedPiece = stableBoard.square[nonCaptureAppeared[0]]
                if capturedPiece != 0 {
                    pendingMove.capturedPiece = capturedPiece
                    print("Blue2UCI: Detected possible capture move from \(squareIndexToName(nonCaptureSquares[0])) to \(squareIndexToName(nonCaptureAppeared[0])) while waiting for capture")
                } else {
                    print("Blue2UCI: Detected simple move from \(squareIndexToName(nonCaptureSquares[0])) to \(squareIndexToName(nonCaptureAppeared[0])) while waiting for capture")
                }
                pendingCaptureSquares = [] // Clear pending capture to start new move
                firstRemovedPiece = nil
                completeMove()
            }
        }
    }
    
    private func findDifferences(from oldBoard: boardRecord, to newBoard: boardRecord) -> [Difference] {
        var differences: [Difference] = []
        
        for i in 0..<64 {
            if oldBoard.square[i] != newBoard.square[i] {
                differences.append(Difference(square: i, oldPiece: oldBoard.square[i], newPiece: newBoard.square[i]))
            }
        }
        
        return differences
    }
    
    private func checkCaptureCompletion(differences: [Difference]) {
        guard !pendingCaptureSquares.isEmpty, let firstPiece = firstRemovedPiece else {
            print("Blue2UCI: Failed to confirm capture: no pending squares or first removed piece")
            return
        }
        
        // Debug: Log current board state for capture squares
        let captureSquaresState = pendingCaptureSquares.map { square in
            "\(squareIndexToName(square)): \(pieceSymbols[currentBoard.square[square]] ?? "unknown")"
        }
        print("Blue2UCI: Checking capture completion, current board state: \(captureSquaresState)")
        
        // Check if the first removed piece's type appears on one of the pending squares
        let toSquare = pendingCaptureSquares.first { square in
            currentBoard.square[square] == firstPiece.piece
        }
        let fromSquare = pendingCaptureSquares.first { square in
            currentBoard.square[square] == 0 && stableBoard.square[square] == firstPiece.piece
        }
        
        if let toSquare = toSquare, let fromSquare = fromSquare {
            pendingMove.fromSquare = fromSquare
            pendingMove.toSquare = toSquare
            pendingMove.capturedPiece = stableBoard.square[toSquare]
            print("Blue2UCI: Detected capture move from \(squareIndexToName(fromSquare)) to \(squareIndexToName(toSquare))")
        } else {
            print("Blue2UCI: Failed to confirm capture: piece mismatch or invalid board state")
        }
    }
    
    private func detectCastling(missing: [Int], appeared: [Int]) {
        // Look for king movement (two squares)
        let kingSquares = missing.filter { square in
            let piece = stableBoard.square[square]
            return piece == 12 || piece == 2 // White king or black king
        }
        
        if kingSquares.count == 1 {
            let kingFrom = kingSquares[0]
            // Find where the king appeared
            for square in appeared {
                let piece = currentBoard.square[square]
                if (piece == 12 || piece == 2) && abs(square - kingFrom) == 2 {
                    // This is castling
                    pendingMove.fromSquare = kingFrom
                    pendingMove.toSquare = square
                    print("Blue2UCI: Detected castling move from \(squareIndexToName(kingFrom)) to \(squareIndexToName(square))")
                    break
                }
            }
        }
    }
    
    private func completeMove() {
        if let fromSq = pendingMove.fromSquare, let toSq = pendingMove.toSquare {
            let uciMove = generateUCI(from: fromSq, to: toSq)
            let fromSquareName = squareIndexToName(fromSq)
            let toSquareName = squareIndexToName(toSq)
            print("Blue2UCI: UCI move \(uciMove) detected, lighting squares: \(fromSquareName), \(toSquareName)")
            onMoveDetected?(uciMove)
            onLEDChange?([fromSquareName, toSquareName])
            
            // Update stable board
            stableBoard = currentBoard
            stableBoard.who2move = 1 - stableBoard.who2move
            stableBoard.halfmoves += 1
            pendingCaptureSquares = [] // Clear pending capture
            firstRemovedPiece = nil
        } else if !pendingCaptureSquares.isEmpty {
            print("Blue2UCI: Partial capture detected, waiting for next update")
            return // Don’t reset, wait for capture completion
        } else {
            print("Blue2UCI: No valid move detected, resetting state")
            pendingCaptureSquares = [] // Clear pending capture
            firstRemovedPiece = nil
        }
        
        // Reset state
        moveInProgress = false
        pendingMove = moveRecord()
    }
    
    private func generateUCI(from: Int, to: Int) -> String {
        let fromName = squareIndexToName(from)
        let toName = squareIndexToName(to)
        
        // Basic UCI move (promotion detection can be added later)
        return fromName + toName
    }
    
    private func squareIndexToName(_ index: Int) -> String {
        let file = index % 8
        let rank = index / 8
        let fileChar = Character(UnicodeScalar(97 + file)!) // 'a' + file
        let rankChar = String(rank + 1)
        return String(fileChar) + rankChar
    }
    
    private func squareNameToIndex(_ name: String) -> Int {
        guard name.count == 2 else { return -1 }
        let fileChar = name.first!
        let rankChar = name.last!
        
        guard let fileValue = fileChar.asciiValue, let rankValue = Int(String(rankChar)) else { return -1 }
        
        let file = Int(fileValue - 97) // 'a' = 97
        let rank = rankValue - 1
        
        return rank * 8 + file
    }
    
    // Public method to manually set current board as stable baseline
    func setCurrentBoardAsStable() {
        stableBoard = currentBoard
        moveInProgress = false
        pendingMove = moveRecord()
        pendingCaptureSquares = []
        firstRemovedPiece = nil
        print("Blue2UCI: Set current board as stable baseline")
    }
    
    // Public method to get current board as FEN
    func getCurrentBoardAsFEN() -> String {
        var fen = ""
        var emptyCount = 0
        
        for rank in (0..<8).reversed() {
            for file in 0..<8 {
                let square = rank * 8 + file
                let piece = currentBoard.square[square]
                
                if piece == 0 {
                    emptyCount += 1
                } else {
                    if emptyCount > 0 {
                        fen += String(emptyCount)
                        emptyCount = 0
                    }
                    fen += pieceSymbols[piece] ?? " "
                }
            }
            
            if emptyCount > 0 {
                fen += String(emptyCount)
                emptyCount = 0
            }
            
            if rank > 0 {
                fen += "/"
            }
        }
        
        // Add side to move, castling, en passant, etc.
        fen += currentBoard.who2move == 0 ? " w " : " b "
        
        var castling = ""
        if currentBoard.wCastleKside { castling += "K" }
        if currentBoard.wCastleQside { castling += "Q" }
        if currentBoard.bCastleKside { castling += "k" }
        if currentBoard.bCastleQside { castling += "q" }
        if castling.isEmpty { castling = "-" }
        fen += castling
        
        let enPassant = currentBoard.enPassantSq != nil ? squareIndexToName(currentBoard.enPassantSq!) : "-"
        fen += " " + enPassant
        
        fen += " 0 \(currentBoard.halfmoves / 2 + 1)"
        
        return fen
    }
}

