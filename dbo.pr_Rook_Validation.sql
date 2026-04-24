SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [pr_Rook_Validation]
(
    @RowDiff INT,
    @ColDiff INT,
    @FromRowNum INT,
    @ToRowNum INT,
    @FromColOrd INT,
    @ToColOrd INT,
    @ToRow VARCHAR(10),
    @ToColumn VARCHAR(10),
    @Piece NVARCHAR(100),
    @Side VARCHAR(10),
    @TargetTable sysname
)
AS
BEGIN

    DECLARE @SQL NVARCHAR(MAX);

    DECLARE @TargetPiece NVARCHAR(100);

    DECLARE @MidPiece NVARCHAR(100);
    DECLARE @StepRow INT;
    DECLARE @StepCol INT;
    DECLARE @CurRow INT;
    DECLARE @CurCol INT;
    DECLARE @CurColChar CHAR(1);
    DECLARE @PathBlocked BIT;

    IF @Piece IN ( N'♖', N'♜' )
        RETURN;

    SET @RowDiff = ABS(@ToRowNum - @FromRowNum);
    SET @ColDiff = ABS(@ToColOrd - @FromColOrd);

    IF @RowDiff > 0
       AND @ColDiff > 0
        INSERT INTO [#tmpMessage]
        VALUES
        ('Rook must move in a straight line (same row or same column)', GETDATE());
    ELSE IF @RowDiff = 0
            AND @ColDiff = 0
        INSERT INTO [#tmpMessage]
        VALUES
        ('Rook must move at least one square', GETDATE());
    ELSE
    BEGIN
        -- Step is 0 on the fixed axis, +/-1 on the moving axis
        SET @StepRow = CASE
                           WHEN @ToRowNum > @FromRowNum THEN
                               1
                           WHEN @ToRowNum < @FromRowNum THEN
                               -1
                           ELSE
                               0
                       END;
        SET @StepCol = CASE
                           WHEN @ToColOrd > @FromColOrd THEN
                               1
                           WHEN @ToColOrd < @FromColOrd THEN
                               -1
                           ELSE
                               0
                       END;
        SET @PathBlocked = 0;
        SET @CurRow = @FromRowNum + @StepRow;
        SET @CurCol = @FromColOrd + @StepCol;

        WHILE (@CurRow <> @ToRowNum OR @CurCol <> @ToColOrd) AND @PathBlocked = 0
        BEGIN
            SET @CurColChar = CHAR(ASCII('A') + @CurCol - 1);
            SET @SQL
                = N'SELECT @POut = Piece FROM ' + QUOTENAME(@TargetTable)
                  + N' WHERE RowNum = @CurRow AND Col = @CurColChar';
            EXEC [sp_executesql] @SQL,
                                 N'@CurRow INT, @CurColChar CHAR(1), @POut NVARCHAR(100) OUTPUT',
                                 @CurRow,
                                 @CurColChar,
                                 @MidPiece OUTPUT;

            IF NULLIF(@MidPiece, '') IS NOT NULL
                SET @PathBlocked = 1;
            SET @CurRow = @CurRow + @StepRow;
            SET @CurCol = @CurCol + @StepCol;
        END;

        IF @PathBlocked = 1
            INSERT INTO [#tmpMessage]
            VALUES
            ('Rook path is blocked by an intervening piece', GETDATE());
        ELSE
        BEGIN
            SET @SQL
                = N'SELECT @POut = Piece FROM ' + QUOTENAME(@TargetTable)
                  + N' WHERE RowNum = CAST(@ToRow AS INT) AND Col = @ToCol';
            EXEC [sp_executesql] @SQL,
                                 N'@ToRow CHAR(1), @ToCol CHAR(1), @POut NVARCHAR(100) OUTPUT',
                                 @ToRow,
                                 @ToColumn,
                                 @TargetPiece OUTPUT;

            IF (
                   @Side = 'WHITE'
                   AND @TargetPiece IN ( N'♙', N'♖', N'♘', N'♗', N'♕', N'♔' )
               )
               OR
               (
                   @Side = 'BLACK'
                   AND @TargetPiece IN ( N'♟', N'♜', N'♞', N'♝', N'♛', N'♚' )
               )
                INSERT INTO [#tmpMessage]
                VALUES
                ('Cannot capture your own piece', GETDATE());
        END;
    END;



END;
GO

