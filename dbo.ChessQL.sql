SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [ChessQL]
(
    @Side VARCHAR(10),
    @TargetTable sysname,
    @IsDropTable BIT = 0,
    @IsReset BIT = 0,
    @From VARCHAR(2) = NULL,
    @To VARCHAR(2) = NULL,
    @IsRevertMove BIT = 0,
    @IsViewOnly BIT = 0
)
AS
BEGIN
    BEGIN TRAN;

    -- =========================================================
    -- Variable declarations
    -- =========================================================
    DECLARE @FromColumn VARCHAR(1);
    DECLARE @FromRow VARCHAR(1);
    DECLARE @ToColumn VARCHAR(1);
    DECLARE @ToRow VARCHAR(1);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @IsTableExist BIT;
    DECLARE @Piece NVARCHAR(100);
    DECLARE @Turn VARCHAR(10);
    DECLARE @SortOrder NVARCHAR(4);

    -- Pawn validation
    DECLARE @FromRowNum INT;
    DECLARE @ToRowNum INT;
    DECLARE @MidRowNum INT; -- pre-computed jump-over row (no inline expr in EXEC)
    DECLARE @FromColOrd INT;
    DECLARE @ToColOrd INT;
    DECLARE @RowDiff INT;
    DECLARE @ColDiff INT;
    DECLARE @Dir INT;
    DECLARE @StartRow INT;
    DECLARE @MidPiece NVARCHAR(100);
    DECLARE @TargetPiece NVARCHAR(100);

    CREATE TABLE #tmpMessage
    (
        MessageID INT IDENTITY(1, 1),
        MessageText NVARCHAR(500),
        CreatedAt DATETIME
            DEFAULT GETDATE()
    );

    -- =========================================================
    -- Normalise inputs
    -- =========================================================
    SET @Side = UPPER(LTRIM(RTRIM(@Side)));

    IF @TargetTable IS NULL
    BEGIN
        PRINT '@TargetTable is null';
        ROLLBACK TRAN;
        RETURN;
    END;

    IF @TargetTable NOT LIKE '%RowCol%'
    BEGIN
        PRINT '@TargetTable should contain RowCol';
        ROLLBACK TRAN;
        RETURN;
    END;

    SET @TargetTable = @TargetTable + '_Normalized';
    SET @IsTableExist = ISNULL(OBJECT_ID(@TargetTable, 'U'), 0);

    -- =========================================================
    -- Drop table if requested
    -- =========================================================
    IF @IsTableExist = 1
       AND ISNULL(@IsDropTable, 0) = 1
    BEGIN
        SET @SQL = N'DROP TABLE ' + QUOTENAME(@TargetTable);
        EXEC sp_executesql @SQL;
        COMMIT TRAN;
        RETURN;
    END;

    -- =========================================================
    -- Create / reset the board
    -- =========================================================
    IF @IsTableExist = 0
       OR ISNULL(@IsReset, 0) = 1
    BEGIN
        IF @IsTableExist = 0
        BEGIN
            SET @SQL
                = N'
                CREATE TABLE ' + QUOTENAME(@TargetTable)
                  + N'
                (
                    RowNum INT,
                    Col    CHAR(1),
                    Piece  NVARCHAR(MAX),
                    Moves  INT
                )';
            EXEC sp_executesql @SQL;
        END;
        ELSE
        BEGIN
            SET @SQL = N'TRUNCATE TABLE ' + QUOTENAME(@TargetTable);
            EXEC sp_executesql @SQL;
        END;

        SET @SQL
            = N'
            INSERT INTO ' + QUOTENAME(@TargetTable)
              + N' (RowNum, Col, Piece, Moves)
            VALUES
            (1,''A'',N''♖'',0),(1,''B'',N''♘'',0),(1,''C'',N''♗'',0),(1,''D'',N''♕'',0),
            (1,''E'',N''♔'',0),(1,''F'',N''♗'',0),(1,''G'',N''♘'',0),(1,''H'',N''♖'',0),

            (2,''A'',N''♙'',0),(2,''B'',N''♙'',0),(2,''C'',N''♙'',0),(2,''D'',N''♙'',0),
            (2,''E'',N''♙'',0),(2,''F'',N''♙'',0),(2,''G'',N''♙'',0),(2,''H'',N''♙'',0),

            (3,''A'',N'''',0),(3,''B'',N'''',0),(3,''C'',N'''',0),(3,''D'',N'''',0),
            (3,''E'',N'''',0),(3,''F'',N'''',0),(3,''G'',N'''',0),(3,''H'',N'''',0),

            (4,''A'',N'''',0),(4,''B'',N'''',0),(4,''C'',N'''',0),(4,''D'',N'''',0),
            (4,''E'',N'''',0),(4,''F'',N'''',0),(4,''G'',N'''',0),(4,''H'',N'''',0),

            (5,''A'',N'''',0),(5,''B'',N'''',0),(5,''C'',N'''',0),(5,''D'',N'''',0),
            (5,''E'',N'''',0),(5,''F'',N'''',0),(5,''G'',N'''',0),(5,''H'',N'''',0),

            (6,''A'',N'''',0),(6,''B'',N'''',0),(6,''C'',N'''',0),(6,''D'',N'''',0),
            (6,''E'',N'''',0),(6,''F'',N'''',0),(6,''G'',N'''',0),(6,''H'',N'''',0),

            (7,''A'',N''♟'',0),(7,''B'',N''♟'',0),(7,''C'',N''♟'',0),(7,''D'',N''♟'',0),
            (7,''E'',N''♟'',0),(7,''F'',N''♟'',0),(7,''G'',N''♟'',0),(7,''H'',N''♟'',0),

            (8,''A'',N''♜'',0),(8,''B'',N''♞'',0),(8,''C'',N''♝'',0),(8,''D'',N''♛'',0),
            (8,''E'',N''♚'',0),(8,''F'',N''♝'',0),(8,''G'',N''♞'',0),(8,''H'',N''♜'',0)
        ';
        EXEC sp_executesql @SQL;
    END;

    -- =========================================================
    -- Parse coordinates
    -- Format: letter then digit, e.g. 'E2'
    -- @FromColumn = letter (Col), @FromRow = digit char (RowNum)
    -- =========================================================
    SET @FromColumn = LEFT(@From, 1);
    SET @FromRow = SUBSTRING(@From, 2, 1);
    SET @ToColumn = LEFT(@To, 1);
    SET @ToRow = SUBSTRING(@To, 2, 1);

    -- =========================================================
    -- Determine whose turn it is
    -- =========================================================
    SET @SQL = N'
        SELECT @TurnOut = IIF((MAX(Moves) + 1) % 2 = 0, ''BLACK'', ''WHITE'')
        FROM ' + QUOTENAME(@TargetTable);

    EXEC sp_executesql @SQL, N'@TurnOut NVARCHAR(10) OUTPUT', @Turn OUTPUT;

    -- =========================================================
    -- Basic guard checks
    -- =========================================================
    IF (@Turn NOT LIKE '%' + @Side + '%')
       AND ISNULL(@IsViewOnly, 0) = 0
       AND ISNULL(@IsRevertMove, 0) = 0
        INSERT INTO #tmpMessage
        VALUES
        ('It''s not your turn yet', GETDATE());

    IF NULLIF(@Side, '') IS NULL
        INSERT INTO #tmpMessage
        VALUES
        ('Select your side', GETDATE());

    IF NULLIF(@To, '') IS NULL
       OR NULLIF(@From, '') IS NULL
        INSERT INTO #tmpMessage
        VALUES
        ('No coordinates provided', GETDATE());

    -- =========================================================
    -- Move processing
    -- =========================================================
    IF
    (
        SELECT COUNT(*)FROM #tmpMessage
    ) = 0
    AND ISNULL(@IsViewOnly, 0) = 0
    BEGIN
        -- Fetch the piece on the FROM square.
        -- RowNum is INT; CAST inside the query avoids a type mismatch.
        SET @SQL
            = N'
            SELECT @PieceOut = Piece
            FROM   ' + QUOTENAME(@TargetTable)
              + N'
            WHERE  RowNum = CAST(@FromRow AS INT)
            AND    Col    = @FromCol';

        EXEC sp_executesql @SQL,
                           N'@FromRow CHAR(1), @FromCol CHAR(1), @PieceOut NVARCHAR(100) OUTPUT',
                           @FromRow,
                           @FromColumn,
                           @Piece OUTPUT;

        IF NULLIF(@Piece, '') IS NULL
           AND NULLIF(@IsRevertMove, 0) IS NULL
            INSERT INTO #tmpMessage
            VALUES
            ('No piece on the selected square', GETDATE());

        -- =====================================================
        -- PAWN VALIDATION
        -- Runs when the moving piece is a pawn (White: N'♙', Black: N'♟')
        -- =====================================================
        IF (NULLIF(@IsRevertMove, 0) IS NULL)
        BEGIN
            IF
            (
                SELECT COUNT(*)FROM #tmpMessage
            ) = 0
            AND @Piece IN ( N'♙', N'♟' )
            BEGIN
                SET @FromRowNum = CAST(@FromRow AS INT);
                SET @ToRowNum = CAST(@ToRow AS INT);
                SET @FromColOrd = ASCII(@FromColumn) - ASCII('A') + 1;
                SET @ToColOrd = ASCII(@ToColumn) - ASCII('A') + 1;


                SELECT @FromRowNum;
                SELECT @ToRowNum;
                SELECT @FromColOrd;
                SELECT @ToColOrd;

                SET @RowDiff = @ToRowNum - @FromRowNum;
                SET @ColDiff = ABS(@ToColOrd - @FromColOrd);

                -- White moves toward row 8 (+1); Black toward row 1 (-1)
                SET @Dir = CASE
                               WHEN @Side = 'WHITE' THEN
                                   1
                               ELSE
                                   -1
                           END;

                -- -------------------------------------------------
                -- Rule 1: Must advance in the correct direction
                -- -------------------------------------------------
                IF @RowDiff * @Dir <= 0
                BEGIN
                    INSERT INTO #tmpMessage
                    VALUES
                    ('Pawns cannot move backwards', GETDATE());
                END;

                -- -------------------------------------------------
                -- Rule 2: Forward move (same column)
                -- -------------------------------------------------
                ELSE IF @ColDiff = 0
                BEGIN
                    -- Destination must be empty
                    SET @SQL
                        = N'
                    SELECT @POut = Piece
                    FROM   ' + QUOTENAME(@TargetTable)
                          + N'
                    WHERE  RowNum = CAST(@ToRow AS INT)
                    AND    Col    = @ToCol';

                    EXEC sp_executesql @SQL,
                                       N'@ToRow CHAR(1), @ToCol CHAR(1), @POut NVARCHAR(100) OUTPUT',
                                       @ToRow,
                                       @ToColumn,
                                       @TargetPiece OUTPUT;

                    IF NULLIF(@TargetPiece, '') IS NOT NULL
                    BEGIN
                        INSERT INTO #tmpMessage
                        VALUES
                        ('Cannot move forward into an occupied square', GETDATE());
                    END;

                    -- Double-square advance from starting rank
                    ELSE IF ABS(@RowDiff) = 2
                    BEGIN
                        SET @StartRow = CASE
                                            WHEN @Side = 'WHITE' THEN
                                                2
                                            ELSE
                                                7
                                        END;
                        -- Pre-compute the intermediate row so no expression appears in EXEC params
                        SET @MidRowNum = @FromRowNum + @Dir;

                        IF @FromRowNum <> @StartRow
                        BEGIN
                            INSERT INTO #tmpMessage
                            VALUES
                            ('Double move only allowed from the starting row', GETDATE());
                        END;
                        ELSE
                        BEGIN
                            -- The skipped-over square must also be empty
                            SET @SQL
                                = N'
                            SELECT @MidOut = Piece
                            FROM   ' + QUOTENAME(@TargetTable)
                                  + N'
                            WHERE  RowNum = @MidRow
                            AND    Col    = @MidCol';

                            EXEC sp_executesql @SQL,
                                               N'@MidRow INT, @MidCol CHAR(1), @MidOut NVARCHAR(100) OUTPUT',
                                               @MidRowNum,
                                               @FromColumn,
                                               @MidPiece OUTPUT;

                            IF NULLIF(@MidPiece, '') IS NOT NULL
                                INSERT INTO #tmpMessage
                                VALUES
                                ('Cannot jump over a piece', GETDATE());
                        END;
                    END;

                    ELSE IF ABS(@RowDiff) <> 1
                    BEGIN
                        INSERT INTO #tmpMessage
                        VALUES
                        ('Pawn can only move 1 square forward (or 2 from its starting row)', GETDATE());
                    END;
                END;

                -- -------------------------------------------------
                -- Rule 3: Diagonal capture (1 column, 1 row)
                -- -------------------------------------------------
                ELSE IF @ColDiff = 1
                        AND ABS(@RowDiff) = 1
                BEGIN
                    SET @SQL
                        = N'
                    SELECT @POut = Piece
                    FROM   ' + QUOTENAME(@TargetTable)
                          + N'
                    WHERE  RowNum = CAST(@ToRow AS INT)
                    AND    Col    = @ToCol';

                    EXEC sp_executesql @SQL,
                                       N'@ToRow CHAR(1), @ToCol CHAR(1), @POut NVARCHAR(100) OUTPUT',
                                       @ToRow,
                                       @ToColumn,
                                       @TargetPiece OUTPUT;

                    IF NULLIF(@TargetPiece, '') IS NULL
                    BEGIN
                        INSERT INTO #tmpMessage
                        VALUES
                        ('Pawns can only capture diagonally on an occupied square', GETDATE());
                    END;
                    ELSE IF (
                                @Side = 'WHITE'
                                AND @TargetPiece IN ( N'♙', N'♖', N'♘', N'♗', N'♕', N'♔' )
                            )
                            OR
                            (
                                @Side = 'BLACK'
                                AND @TargetPiece IN ( N'♟', N'♜', N'♞', N'♝', N'♛', N'♚' )
                            )
                    BEGIN
                        INSERT INTO #tmpMessage
                        VALUES
                        ('Cannot capture your own piece', GETDATE());
                    END;
                END;

                -- -------------------------------------------------
                -- Rule 4: Any other geometry is illegal for a pawn
                -- -------------------------------------------------
                ELSE
                BEGIN
                    INSERT INTO #tmpMessage
                    VALUES
                    ('Invalid pawn move', GETDATE());
                END;
            END; -- end pawn validation
        END;
        -- =====================================================
        -- Apply the move when all validation passes
        -- =====================================================
        IF
        (
            SELECT COUNT(*)FROM #tmpMessage
        ) = 0
        AND NULLIF(@IsReset, 0) IS NULL
        BEGIN
            SET @SQL
                = N'
                UPDATE ' + QUOTENAME(@TargetTable)
                  + N'
                SET    Piece = @Piece
                WHERE  RowNum = CAST(@ToRow AS INT) AND Col = @ToCol;

                UPDATE ' + QUOTENAME(@TargetTable)
                  + N'
                SET    Piece = N''''
                WHERE  RowNum = CAST(@FromRow AS INT) AND Col = @FromCol;

                UPDATE ' + QUOTENAME(@TargetTable) + N'
                SET    Moves = Moves + 1;
            ';

            EXEC sp_executesql @SQL,
                               N'@Piece NVARCHAR(100), @FromRow CHAR(1), @FromCol CHAR(1), @ToRow CHAR(1), @ToCol CHAR(1)',
                               @Piece,
                               @FromRow,
                               @FromColumn,
                               @ToRow,
                               @ToColumn;
        END;
    END; -- end move processing

    -- =========================================================
    -- Return any validation messages
    -- =========================================================
    IF EXISTS (SELECT 1 FROM #tmpMessage)
        SELECT *
        FROM #tmpMessage;

    -- =========================================================
    -- Return the board as a pivot
    -- White view: row 8 at top (DESC); Black view: row 1 at top (ASC)
    -- =========================================================
    SET @SortOrder = CASE
                         WHEN @Side = 'WHITE' THEN
                             N'DESC'
                         ELSE
                             N'ASC'
                     END;

    SET @SQL
        = N'
        SELECT *
        FROM (
            SELECT RowNum, Col, Piece
            FROM   ' + QUOTENAME(@TargetTable)
          + N'
        ) s
        PIVOT (
            MAX(Piece)
            FOR Col IN ([A],[B],[C],[D],[E],[F],[G],[H])
        ) p
        ORDER BY RowNum ' + @SortOrder + N';
    ';

    EXEC sp_executesql @SQL;

    DROP TABLE IF EXISTS #tmpMessage;

    COMMIT TRAN;
END;
GO

