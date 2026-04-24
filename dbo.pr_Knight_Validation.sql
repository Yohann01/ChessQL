SET QUOTED_IDENTIFIER ON
SET ANSI_NULLS ON
GO
CREATE OR ALTER PROCEDURE [pr_Knight_Validation]
(
    @RowDiff INT,
    @ColDiff INT,
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

    IF @Piece IN ( N'♘', N'♞' )
        RETURN;

    IF NOT (
               (
                   @RowDiff = 1
                   AND @ColDiff = 2
               )
               OR
               (
                   @RowDiff = 2
                   AND @ColDiff = 1
               )
           )
        INSERT INTO [#tmpMessage]
        VALUES
        ('Knight must move in an L-shape (2+1 squares)', GETDATE());
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
GO

