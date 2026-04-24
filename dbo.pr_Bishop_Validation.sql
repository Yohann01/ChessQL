SET QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON
GO
ALTER   PROCEDURE [pr_Bishop_Validation]
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

    IF @Piece NOT IN ( N'♗', N'♝' )
        RETURN;


    IF @RowDiff = 0
       OR @RowDiff <> @ColDiff
        INSERT INTO [#tmpMessage]
        VALUES
        ('Bishop must move diagonally with equal row and column distance', GETDATE());
    ELSE
    BEGIN
        SET @StepRow = CASE
                           WHEN @ToRowNum > @FromRowNum THEN
                               1
                           ELSE
                               -1
                       END;
        SET @StepCol = CASE
                           WHEN @ToColOrd > @FromColOrd THEN
                               1
                           ELSE
                               -1
                       END;
        SET @PathBlocked = 0;
        SET @CurRow = @FromRowNum + @StepRow;
        SET @CurCol = @FromColOrd + @StepCol;

        WHILE @CurRow <> @ToRowNum AND @PathBlocked = 0
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
            ('Bishop path is blocked by an intervening piece', GETDATE());
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

