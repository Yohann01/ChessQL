SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [ChessQL]
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
    DECLARE @FromColumn VARCHAR(10);
    DECLARE @FromRow VARCHAR(10);
    DECLARE @ToColumn VARCHAR(10);
    DECLARE @ToRow VARCHAR(10);
    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @IsTableExist BIT;
    DECLARE @Piece NVARCHAR(100);
    DECLARE @Turn VARCHAR(10);
    DECLARE @SortOrder NVARCHAR(4);

    -- Shared coordinate integers (all validators reuse these)
    DECLARE @FromRowNum INT;
    DECLARE @ToRowNum INT;
    DECLARE @FromColOrd INT;
    DECLARE @ToColOrd INT;
    DECLARE @RowDiff INT; -- may be signed or ABS depending on context
    DECLARE @ColDiff INT;



    CREATE TABLE [#tmpMessage]
    (
        [MessageID] INT IDENTITY(1, 1),
        [MessageText] NVARCHAR(500),
        [CreatedAt] DATETIME
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
        EXEC [sp_executesql] @SQL;
        COMMIT TRAN;
        RETURN;
    END;

    -- =========================================================
    -- Create / reset board
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
            EXEC [sp_executesql] @SQL;
        END;
        ELSE
        BEGIN
            SET @SQL = N'TRUNCATE TABLE ' + QUOTENAME(@TargetTable);
            EXEC [sp_executesql] @SQL;
        END;

        -- Row 1 = White back rank, Row 8 = Black back rank
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
        EXEC [sp_executesql] @SQL;
    END;

    -- =========================================================
    -- Parse coordinates  e.g. 'E2' -> Col='E', RowNum='2'
    -- =========================================================
    SET @FromColumn = LEFT(@From, 1);
    SET @FromRow = SUBSTRING(@From, 2, 1);
    SET @ToColumn = LEFT(@To, 1);
    SET @ToRow = SUBSTRING(@To, 2, 1);

    -- =========================================================
    -- Whose turn?
    -- =========================================================
    SET @SQL = N'
        SELECT @TurnOut = IIF((MAX(Moves) + 1) % 2 = 0, ''BLACK'', ''WHITE'')
        FROM ' + QUOTENAME(@TargetTable);

    EXEC [sp_executesql] @SQL, N'@TurnOut NVARCHAR(10) OUTPUT', @Turn OUTPUT;

    -- =========================================================
    -- Basic guard checks
    -- =========================================================
    IF (@Turn NOT LIKE '%' + @Side + '%')
       AND NULLIF(@IsViewOnly, 0) IS NULL
       AND NULLIF(@IsRevertMove, 0) IS NULL
        INSERT INTO [#tmpMessage]
        VALUES
        ('It''s not your turn yet', GETDATE());

    IF NULLIF(@Side, '') IS NULL
        INSERT INTO [#tmpMessage]
        VALUES
        ('Select your side', GETDATE());

    IF NULLIF(@To, '') IS NULL
       OR NULLIF(@From, '') IS NULL
        INSERT INTO [#tmpMessage]
        VALUES
        ('No coordinates provided', GETDATE());

    -- =========================================================
    -- Move processing
    -- =========================================================
    IF
    (
        SELECT COUNT(*)FROM [#tmpMessage]
    ) = 0
    AND ISNULL(@IsViewOnly, 0) = 0
    BEGIN
        -- Fetch the moving piece
        SET @SQL
            = N'
            SELECT @PieceOut = Piece
            FROM   ' + QUOTENAME(@TargetTable)
              + N'
            WHERE  RowNum = CAST(@FromRow AS INT)
            AND    Col    = @FromCol';

        EXEC [sp_executesql] @SQL,
                             N'@FromRow CHAR(1), @FromCol CHAR(1), @PieceOut NVARCHAR(100) OUTPUT',
                             @FromRow,
                             @FromColumn,
                             @Piece OUTPUT;

        IF NULLIF(@Piece, '') IS NULL
           AND NULLIF(@IsReset, 0) IS NULL
           AND ISNULL(@IsRevertMove, 0) IS NULL
            INSERT INTO [#tmpMessage]
            VALUES
            ('No piece on the selected square', GETDATE());

        IF
        (
            SELECT COUNT(*)FROM [#tmpMessage]
        ) = 0
        AND NULLIF(@IsRevertMove, 0) IS NULL
        AND NULLIF(@IsReset, 0) IS NULL
        BEGIN


            SET @FromRowNum = CAST(@FromRow AS INT);
            SET @ToRowNum = CAST(@ToRow AS INT);
            SET @FromColOrd = ASCII(@FromColumn) - ASCII('A') + 1;
            SET @ToColOrd = ASCII(@ToColumn) - ASCII('A') + 1;


            -- =======================================================
            -- HELPER: fetch destination piece (reused by every validator)
            -- =======================================================
            -- (done inside each block so @TargetPiece is always fresh)

            -- =======================================================
            -- PAWN 
            -- =======================================================
            SET @RowDiff = @ToRowNum - @FromRowNum; -- signed
            SET @ColDiff = ABS(@ToColOrd - @FromColOrd);

            EXEC [dbo].[pr_Pawn_Validation] @FromRow = @FromRow,         -- varchar(1)
                                            @FromColumn = @FromColumn,   -- varchar(1)
                                            @ToRow = @ToRow,             -- varchar(1)
                                            @ToColumn = @ToColumn,       -- varchar(1)
                                            @RowDiff = @RowDiff,         -- int
                                            @ColDiff = @ColDiff,         -- int
                                            @Piece = @Piece,
                                            @Side = @Side,               -- varchar(10)
                                            @TargetTable = @TargetTable; -- sysname

            -- =======================================================
            -- KNIGHT
            -- =======================================================

            EXEC [dbo].[pr_Knight_Validation] @RowDiff = @RowDiff,
                                              @ColDiff = @ColDiff,         -- int
                                              @ToRow = @ToRow,             -- varchar(10)
                                              @ToColumn = @ToColumn,       -- varchar(10)
                                              @Piece = @Piece,             -- nvarchar(100)
                                              @Side = @Piece,              -- varchar(10)
                                              @TargetTable = @TargetTable; -- sysname

            -- =======================================================
            -- BISHOP
            -- =======================================================
            EXEC [dbo].[pr_Bishop_Validation] @RowDiff = @RowDiff,         -- int
                                              @ColDiff = @ColDiff,         -- int
                                              @FromRowNum = @FromRowNum,   -- int
                                              @ToRowNum = @ToRowNum,       -- int
                                              @FromColOrd = @FromColOrd,   -- int
                                              @ToColOrd = @ToColOrd,       -- int
                                              @ToRow = @ToRow,             -- varchar(10)
                                              @ToColumn = @ToColumn,       -- varchar(10)
                                              @Piece = @Piece,             -- nvarchar(100)
                                              @Side = @Side,               -- varchar(10)
                                              @TargetTable = @TargetTable; -- sysname

            -- =======================================================
            -- ROOK
            -- =======================================================

            EXEC [dbo].[pr_Rook_Validation] @RowDiff = @RowDiff,         -- int
                                            @ColDiff = @ColDiff,         -- int
                                            @FromRowNum = @FromRowNum,   -- int
                                            @ToRowNum = @ToRowNum,       -- int
                                            @FromColOrd = @FromColOrd,   -- int
                                            @ToColOrd = @ToColOrd,       -- int
                                            @ToRow = @ToRow,             -- varchar(10)
                                            @ToColumn = @ToColumn,       -- varchar(10)
                                            @Piece = @Piece,             -- nvarchar(100)
                                            @Side = @Side,               -- varchar(10)
                                            @TargetTable = @TargetTable; -- sysname



        END;
        -- =======================================================
        -- Apply the move when all validation passes
        -- =======================================================



        IF NULLIF(@IsRevertMove, 0) IS NULL
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
						SET    Moves = Moves + 1; ';
        END;
        ELSE IF NULLIF(@IsRevertMove, 0) IS NOT NULL
                AND NULLIF(@IsReset, 0) IS NULL
        BEGIN
            SET @SQL
                = N'
					SELECT @PieceOut = Piece
					FROM   ' + QUOTENAME(@TargetTable)
                  + N'
					WHERE  RowNum = CAST(@ToRow AS INT)
					AND    Col    = @ToCol';

            EXEC [sp_executesql] @SQL,
                                 N'@ToRow CHAR(1), @ToCol CHAR(1), @PieceOut NVARCHAR(100) OUTPUT',
                                 @ToRow,
                                 @ToColumn,
                                 @Piece OUTPUT;

            IF NULLIF(@Piece, '') IS NULL
                INSERT INTO [#tmpMessage]
                VALUES
                ('No piece on the selected square', GETDATE());

            SET @SQL
                = N'
					UPDATE ' + QUOTENAME(@TargetTable)
                  + N'
					SET    Piece = @Piece
					WHERE  RowNum = CAST(@FromRow AS INT) AND Col = @FromCol;

					UPDATE ' + QUOTENAME(@TargetTable)
                  + N'
					SET    Piece = N''''
					WHERE  RowNum = CAST(@ToRow AS INT) AND Col = @ToCol;';
        END;


        IF
        (
            SELECT COUNT(*)FROM [#tmpMessage]
        ) = 0
        AND NULLIF(@IsReset, 0) IS NULL
        BEGIN
            EXEC [sp_executesql] @SQL,
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
    IF EXISTS (SELECT 1 FROM [#tmpMessage])
        SELECT *
        FROM [#tmpMessage];

    -- =========================================================
    -- Return the board as a pivot (rank x file)
    -- White view: row 8 at top; Black view: row 1 at top
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

    EXEC [sp_executesql] @SQL;

    DROP TABLE IF EXISTS [#tmpMessage];

    COMMIT TRAN;
END;
GO

