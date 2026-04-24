# ♟️ ChessQL

ChessQL is a SQL-driven chess engine that validates and executes chess moves using stored procedures.  
It simulates a full chess board, enforces movement rules per piece, and prevents illegal moves — all inside SQL.

---

## 🚀 Features

- ♟️ Full chess board simulation using table structure
- ✅ Move validation per piece:
  - Pawn (including double move + capture rules)
  - Knight (L-shape movement)
  - Bishop (diagonal + path blocking)
  - Rook (straight lines + path blocking)
- 🚫 Prevents:
  - Illegal moves
  - Moving through pieces
  - Capturing your own pieces
  - Playing out of turn
- 🔄 Board reset and replay support
- 📊 Board returned as pivoted grid (A–H columns)

---

## 🧠 How It Works

The system is powered by a main stored procedure:

### `ChessQL`

- Initializes the board
- Parses moves (e.g. `E2 → E4`)
- Determines turn order
- Delegates validation to piece-specific procedures
- Applies the move if valid

### Piece Validators

Each piece has its own validation procedure:

- `pr_Pawn_Validation`
- `pr_Knight_Validation`
- `pr_Bishop_Validation`
- `pr_Rook_Validation`

These procedures:
- Enforce movement rules
- Check path blocking (for sliding pieces)
- Validate captures
- Return errors via `#tmpMessage`

---

## 🗃️ Board Structure

The board is stored as a table:

| Column  | Description |
|--------|------------|
| RowNum | 1–8 (rank) |
| Col    | A–H (file) |
| Piece  | Unicode chess piece |
| Moves  | Move counter |

---

## ▶️ Usage

### 1. Initialize / Reset Board

```sql
EXEC [dbo].[ChessQL] @Side = 'White',           -- varchar(10)
                     @TargetTable = 'ChessRowCol',  -- sysname
                     @IsDropTable = NULL,  -- bit
                     @IsReset = 1,      -- bit
                     @From = '',           -- varchar(2)
                     @To = '',             -- varchar(2)
                     @IsRevertMove = NULL, -- bit
                     @IsViewOnly = NULL    -- bit
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