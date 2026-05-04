CREATE       PROCEDURE gold.sp_DISPATCHER_STORED_PROCEDURE
    @child_stored_procedure_name NVARCHAR(200),
    @batch_id NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        -- Validate that the procedure exists in gold schema
        IF NOT EXISTS (
            SELECT 1
            FROM sys.procedures
            WHERE name = @child_stored_procedure_name
              AND SCHEMA_NAME(schema_id) = 'gold'
        )
        BEGIN
            THROW 50001, 'Unknown child stored procedure name.', 1;
        END;

        DECLARE @sql NVARCHAR(MAX) =
            N'EXEC gold.' + QUOTENAME(@child_stored_procedure_name) +
            N' @batch_id = @batch_id_param';

        EXEC sp_executesql
            @sql,
            N'@batch_id_param NVARCHAR(100)',
            @batch_id_param = @batch_id;

    END TRY
    BEGIN CATCH

        DECLARE @origNum INT = ERROR_NUMBER();
        DECLARE @state INT = ERROR_STATE();

        DECLARE @msg NVARCHAR(4000) =
            'Error ' + CAST(@origNum AS NVARCHAR(10)) +
            ' in child procedure [gold].[' + @child_stored_procedure_name + ']: '
            + ERROR_MESSAGE();

        -- throw a valid custom error number (>= 50000)
        THROW 50002, @msg, @state;

    END CATCH
END;