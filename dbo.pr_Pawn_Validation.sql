SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [pr_Pawn_Validation]
(
    @FromRow VARCHAR(10),
    @FromColumn VARCHAR(10),
    @ToRow VARCHAR(10),
    @ToColumn VARCHAR(10),
    @RowDiff INT,
    @ColDiff INT,
    @Piece NVARCHAR(100),
    @Side VARCHAR(10),
    @TargetTable sysname
)
AS
BEGIN

    DECLARE @SQL NVARCHAR(MAX);
    DECLARE @FromRowNum INT;

    DECLARE @Dir INT;
    DECLARE @StartRow INT;
    DECLARE @MidRowNum INT;

    DECLARE @MidPiece NVARCHAR(100);
    DECLARE @TargetPiece NVARCHAR(100);

    SET @FromRowNum = CAST(@FromRow AS INT);
    SET @Dir = CASE
                   WHEN @Side = 'WHITE' THEN
                       1
                   ELSE
                       -1
               END;
    IF @Piece NOT IN ( N'♙', N'♟' )
        RETURN;


    IF @RowDiff * @Dir <= 0
        INSERT INTO [#tmpMessage]
        VALUES
        ('Pawns cannot move backwards', GETDATE());

    ELSE IF @ColDiff = 0 -- forward move
    BEGIN

		-- Validate if target square is occupied by any piece
        SET @SQL
            = N'SELECT @POut = Piece FROM ' + QUOTENAME(@TargetTable)
              + N' WHERE RowNum = CAST(@ToRow AS INT) AND Col = @ToCol';


        EXEC [sp_executesql] @SQL,
                             N'@ToRow CHAR(1), @ToCol CHAR(1), @POut NVARCHAR(100) OUTPUT',
                             @ToRow,
                             @ToColumn,
                             @TargetPiece OUTPUT;



        IF NULLIF(@TargetPiece, '') IS NOT NULL
            INSERT INTO [#tmpMessage]
            VALUES
            ('Cannot move forward into an occupied square', GETDATE());



        ELSE IF ABS(@RowDiff) = 2
        BEGIN
            SET @StartRow = CASE
                                WHEN @Side = 'WHITE' THEN
                                    2
                                ELSE
                                    7
                            END;
            SET @MidRowNum = @FromRowNum + @Dir;

            IF @FromRowNum <> @StartRow
                INSERT INTO [#tmpMessage]
                VALUES
                ('Double advance only allowed from the starting rank', GETDATE());


            ELSE
            BEGIN


                SET @SQL
                    = N'SELECT @POut = Piece FROM ' + QUOTENAME(@TargetTable)
                      + N' WHERE RowNum = @MidRow AND Col = @MidCol';


                EXEC [sp_executesql] @SQL,
                                     N'@MidRow INT, @MidCol CHAR(1), @POut NVARCHAR(100) OUTPUT',
                                     @MidRowNum,
                                     @FromColumn,
                                     @MidPiece OUTPUT;


                IF NULLIF(@MidPiece, '') IS NOT NULL
                    INSERT INTO [#tmpMessage]
                    VALUES
                    ('Cannot jump over a piece', GETDATE());


            END;
        END;

        ELSE IF ABS(@RowDiff) <> 1
            INSERT INTO [#tmpMessage]
            VALUES
            ('Pawn moves 1 square forward (or 2 from starting rank)', GETDATE());

    END;

    ELSE IF @ColDiff = 1
            AND ABS(@RowDiff) = 1 -- diagonal capture
    BEGIN


        SET @SQL
            = N'SELECT @POut = Piece FROM ' + QUOTENAME(@TargetTable)
              + N' WHERE RowNum = CAST(@ToRow AS INT) AND Col = @ToCol';
        EXEC [sp_executesql] @SQL,
                             N'@ToRow CHAR(1), @ToCol CHAR(1), @POut NVARCHAR(100) OUTPUT',
                             @ToRow,
                             @ToColumn,
                             @TargetPiece OUTPUT;


        IF NULLIF(@TargetPiece, '') IS NULL
            INSERT INTO [#tmpMessage]
            VALUES
            ('Pawns capture diagonally only on occupied squares', GETDATE());


        ELSE IF (
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

    ELSE
        INSERT INTO [#tmpMessage]
        VALUES
        ('Invalid pawn move', GETDATE());


END;
GO

