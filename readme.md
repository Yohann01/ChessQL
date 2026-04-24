# ♟️ ChessQL

![SQL Server](https://img.shields.io/badge/SQL%20Server-T--SQL-blue?logo=microsoftsqlserver)
![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)

ChessQL is a SQL-driven chess engine that validates and executes chess moves using stored procedures.  
It simulates a full chess board, enforces movement rules per piece, and prevents illegal moves — all inside SQL.

---

## 🚀 Features

- ♟️ Full chess board simulation using table structure
- ✅ Move validation per piece:
  - Pawn (double move, capture rules, direction control)
  - Knight (L-shape movement)
  - Bishop (diagonal movement + path blocking)
  - Rook (horizontal/vertical movement + path blocking)
- 🚫 Rule enforcement:
  - Prevent illegal moves
  - Prevent jumping over pieces (where applicable)
  - Prevent capturing your own pieces
  - Turn-based play system
- 🔄 Board reset + replay support
- 📊 Visual board output (pivoted A–H grid)

---

## 🧠 How It Works

ChessQL is powered by a main stored procedure that orchestrates the entire game logic.

### `ChessQL` Engine

- Initializes or resets the board
- Parses algebraic-like input (`E2 → E4`)
- Determines player turn
- Calls piece-specific validation procedures
- Executes move if valid

### Piece Validation Layer

Each chess piece has its own rule engine:

- `pr_Pawn_Validation`
- `pr_Knight_Validation`
- `pr_Bishop_Validation`
- `pr_Rook_Validation`

These enforce:
- Movement legality
- Path obstruction checks
- Capture rules
- Error messaging via `#tmpMessage`

---

## 🗃️ Board Schema

| Column | Description |
|--------|------------|
| RowNum | Rank (1–8) |
| Col    | File (A–H) |
| Piece  | Unicode chess piece |
| Moves  | Move counter |

---

## ▶️ Usage

### 1. Initialize / Reset Board

```sql
EXEC [dbo].[ChessQL] 
    @Side = 'White',
    @TargetTable = 'ChessRowCol',
    @IsReset = 1;
```
### 2. View the board without making a move

```sql
EXEC [dbo].[ChessQL] @Side = 'White',           -- varchar(10)
                     @TargetTable = 'ChessRowCol',  -- sysname
                     @IsDropTable = NULL,  -- bit
                     @IsReset = 0,      -- bit
                     @From = '',           -- varchar(2)
                     @To = '',             -- varchar(2)
                     @IsRevertMove = NULL, -- bit
                     @IsViewOnly = 1    -- bit
```

### 3. White pawn: E2 to E4 (double advance)

```sql
EXEC [dbo].[ChessQL] @Side = 'White',           -- varchar(10)
                     @TargetTable = 'ChessRowCol',  -- sysname
                     @IsDropTable = NULL,  -- bit
                     @IsReset = 0,      -- bit
                     @From = 'A2',           -- varchar(2)
                     @To = 'A4',             -- varchar(2)
                     @IsRevertMove = NULL, -- bit
                     @IsViewOnly = NULL    -- bit
```

### 3. Undo Move

```sql
EXEC [dbo].[ChessQL] @Side = 'White',           -- varchar(10)
                     @TargetTable = 'ChessRowCol',  -- sysname
                     @IsDropTable = NULL,  -- bit
                     @IsReset = 0,      -- bit
                     @From = 'A2',           -- varchar(2)
                     @To = 'A4',             -- varchar(2)
                     @IsRevertMove = 1, -- bit
                     @IsViewOnly = NULL    -- bit
```