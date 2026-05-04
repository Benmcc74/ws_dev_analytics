CREATE   PROCEDURE SP_REPORT_REFRESH 
AS 
BEGIN
    SET NOCOUNT ON;
 
    -- Drop the table if it exists
    IF OBJECT_ID('[audit].[latest_record_date]', 'U') IS NOT NULL
        DROP TABLE [audit].[latest_record_date];
 
    -- Recreate the table
    CREATE TABLE [audit].[latest_record_date] (
        data_as_of DATETIME
    );
 
    -- Insert the latest date from ops_record_count_log
    INSERT INTO [audit].[latest_record_date] (data_as_of)
    SELECT MAX(CREATED_DATE) as data_as_of
    FROM [audit].[ops_record_count_log];
END