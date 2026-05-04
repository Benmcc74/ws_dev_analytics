CREATE   PROCEDURE SP_DIM_DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Drop the table if it exists
    IF OBJECT_ID('[DIM_DATE_REPORT]', 'U') IS NOT NULL
        DROP TABLE [DIM_DATE_REPORT];

    -- Recreate the table
    CREATE TABLE [DIM_DATE_REPORT] (
        SK_DATE                INT,
        CALENDAR_DATE          DATE,
        MONTH_NUMBER_IN_YEAR   INT,
        YEAR_MONTH             VARCHAR(7),
        YEAR_NUMBER            INT,
        MONTH_NAME             VARCHAR(20),
        LOAD_DATE              DATETIME
    );

    -- Insert data
    INSERT INTO [DIM_DATE_REPORT]
    SELECT
        SK_DATE,
        CAST(CALENDAR_DATE AS DATE),
        MONTH_NUMBER_IN_YEAR,
        FORMAT(CALENDAR_DATE, 'yyyy-MM'),
        YEAR_NUMBER,
        MONTH_NAME,
        LOAD_DATE
    FROM [gold].[DIM_DATE]
    WHERE CALENDAR_DATE BETWEEN
    (
        SELECT MIN(MIN_DATE)
        FROM (
            SELECT MIN(CONVERT(date, CONVERT(varchar(8), SK_START_DATE))) AS MIN_DATE
            FROM [gold].[PARTY_DEMOGRAPHICS_FACTLESS]
            WHERE SK_START_DATE IS NOT NULL
            UNION
            SELECT MIN(RELATIONSHIP_START_DATE)
            FROM [gold].[DIM_PARTY_DETAIL]
            WHERE RELATIONSHIP_START_DATE IS NOT NULL
        ) AS MinDates
    )
    AND
    (
        SELECT MAX(MAX_DATE)
        FROM (
            SELECT MAX(CONVERT(date, CONVERT(varchar(8), SK_START_DATE))) AS MAX_DATE
            FROM [gold].[PARTY_DEMOGRAPHICS_FACTLESS]
            WHERE SK_START_DATE IS NOT NULL
            UNION
            SELECT MAX(RELATIONSHIP_START_DATE)
            FROM [gold].[DIM_PARTY_DETAIL]
            WHERE RELATIONSHIP_START_DATE IS NOT NULL
        ) AS MaxDates
    );
END