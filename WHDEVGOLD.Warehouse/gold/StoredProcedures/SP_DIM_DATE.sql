CREATE       PROCEDURE gold.SP_DIM_DATE
(
      @StartDate DATE = '1800-01-01'
    , @EndDate   DATE = '2100-12-31'
)
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------------------
    -- 1. Generate date series using Fabric-supported GENERATE_SERIES
    -------------------------------------------------------------------
    WITH DateSeries AS
    (
        SELECT DATEADD(DAY, value, @StartDate) AS CALENDAR_DATE
        FROM GENERATE_SERIES(0, DATEDIFF(DAY, @StartDate, @EndDate), 1)
    )

    -------------------------------------------------------------------
    -- 2. Upsert (SCD Type‑1) into DIM_DATE
    -------------------------------------------------------------------
    MERGE gold.DIM_DATE AS T
    USING
    (
        SELECT
              CAST(CONVERT(CHAR(8), DS.CALENDAR_DATE, 112) AS INT) AS SK_DATE
            , DS.CALENDAR_DATE

            -- MONTH_YEAR (e.g., JAN-2025)
            , UPPER(LEFT(DATENAME(MONTH, DS.CALENDAR_DATE),3)) 
              + '-' + CAST(YEAR(DS.CALENDAR_DATE) AS CHAR(4)) AS MONTH_YEAR

            , DATEPART(WEEKDAY, DS.CALENDAR_DATE) AS DAY_NUMBER_IN_WEEK
            , DATEPART(DAYOFYEAR, DS.CALENDAR_DATE) AS DAY_NUMBER_IN_YEAR
            , DATEPART(WEEK, DS.CALENDAR_DATE) AS WEEK_NUMBER_IN_YEAR
            , MONTH(DS.CALENDAR_DATE) AS MONTH_NUMBER_IN_YEAR
            , DATEPART(QUARTER, DS.CALENDAR_DATE) AS QUARTER_NUMBER_IN_YEAR

            , CASE WHEN DATENAME(WEEKDAY, DS.CALENDAR_DATE) IN ('Saturday','Sunday') 
                   THEN 'Y' ELSE 'N' END AS IS_WEEKEND

            , YEAR(DS.CALENDAR_DATE) AS YEAR_NUMBER
            , UPPER(DATENAME(WEEKDAY, DS.CALENDAR_DATE)) AS DAY_NAME
            , UPPER(DATENAME(MONTH, DS.CALENDAR_DATE)) AS MONTH_NAME

            , DATEDIFF(DAY, '1800-01-01', DS.CALENDAR_DATE) AS JULIAN_DATE
            , YEAR(DS.CALENDAR_DATE) * 1000 + DATEPART(DAYOFYEAR, DS.CALENDAR_DATE) AS ASAT_JULIAN

            , DATEPART(ISO_WEEK, DS.CALENDAR_DATE) AS ISO_WEEK

            -- ISO YEAR (Fabric-safe)
            , CASE 
                  WHEN MONTH(DS.CALENDAR_DATE) = 1 
                       AND DATEPART(ISO_WEEK, DS.CALENDAR_DATE) >= 52 
                       THEN YEAR(DS.CALENDAR_DATE) - 1
                  WHEN MONTH(DS.CALENDAR_DATE) = 12 
                       AND DATEPART(ISO_WEEK, DS.CALENDAR_DATE) = 1 
                       THEN YEAR(DS.CALENDAR_DATE) + 1
                  ELSE YEAR(DS.CALENDAR_DATE)
              END AS ISO_YEAR

            -- Fiscal (April 1 start)
            , DATEPART(DAYOFYEAR, DATEADD(MONTH, -3, DS.CALENDAR_DATE)) AS FISCAL_DAY
            , DATEPART(WEEK, DATEADD(MONTH, -3, DS.CALENDAR_DATE)) AS FISCAL_WEEK
            , DATEPART(MONTH, DATEADD(MONTH, -3, DS.CALENDAR_DATE)) AS FISCAL_MONTH
            , DATEPART(QUARTER, DATEADD(MONTH, -3, DS.CALENDAR_DATE)) AS FISCAL_QUARTER
            , YEAR(DATEADD(MONTH, -3, DS.CALENDAR_DATE)) AS FISCAL_YEAR

            -- Tax (July 1 start)
            , DATEPART(MONTH, DATEADD(MONTH, -6, DS.CALENDAR_DATE)) AS TAX_PERIOD
            , DATEPART(QUARTER, DATEADD(MONTH, -6, DS.CALENDAR_DATE)) AS TAX_QUARTER
            , YEAR(DATEADD(MONTH, -6, DS.CALENDAR_DATE)) AS TAX_YEAR

            -- Long date (e.g., 01 JANUARY 2025)
            , RIGHT('0' + CAST(DAY(DS.CALENDAR_DATE) AS VARCHAR(2)),2)
              + ' ' + UPPER(DATENAME(MONTH, DS.CALENDAR_DATE))
              + ' ' + CAST(YEAR(DS.CALENDAR_DATE) AS CHAR(4)) AS LONG_DATE_DESCRIPTION

            , CASE WHEN EOMONTH(DS.CALENDAR_DATE) = DS.CALENDAR_DATE 
                   THEN 'Y' ELSE 'N' END AS MONTH_END_INDICATOR

            , 'N' AS PUBLIC_HOLIDAY_INDICATOR

            , CAST(YEAR(DS.CALENDAR_DATE) AS VARCHAR(4)) 
              + '-Q' + CAST(DATEPART(QUARTER, DS.CALENDAR_DATE) AS VARCHAR(1)) AS YEAR_QUARTER

            , CAST(YEAR(DS.CALENDAR_DATE) AS VARCHAR(4)) 
              + '-M' + RIGHT('0' + CAST(MONTH(DS.CALENDAR_DATE) AS VARCHAR(2)),2) AS YEAR_MONTH

            , CAST(YEAR(DS.CALENDAR_DATE) AS VARCHAR(4)) 
              + '-W' + RIGHT('0' + CAST(DATEPART(WEEK, DS.CALENDAR_DATE) AS VARCHAR(2)),2) AS YEAR_ISO_WEEK

            , DAY(EOMONTH(DS.CALENDAR_DATE)) AS NUMBER_OF_DAYS_IN_MONTH

            , CASE WHEN YEAR(DS.CALENDAR_DATE) % 4 = 0 
                       AND (YEAR(DS.CALENDAR_DATE) % 100 <> 0 
                       OR YEAR(DS.CALENDAR_DATE) % 400 = 0)
                   THEN 366 ELSE 365 END AS NUMBER_OF_DAYS_IN_YEAR

            , CAST(YEAR(DS.CALENDAR_DATE) AS VARCHAR(4)) 
              + '-H' + CASE WHEN MONTH(DS.CALENDAR_DATE) <= 6 THEN '1' ELSE '2' END AS YEAR_HALFYEAR

            , CAST(YEAR(DS.CALENDAR_DATE) AS VARCHAR(4)) 
              + '-W' + RIGHT('0' + CAST(DATEPART(WEEK, DS.CALENDAR_DATE) AS VARCHAR(2)),2) AS TRADING_WEEK

            , SYSDATETIME() AS LOAD_DATE
            , SYSDATETIME() AS LOAD_TIME

        FROM DateSeries DS
    ) AS S
    ON T.SK_DATE = S.SK_DATE

    WHEN MATCHED THEN
        UPDATE SET
              T.CALENDAR_DATE = S.CALENDAR_DATE
            , T.MONTH_YEAR = S.MONTH_YEAR
            , T.DAY_NUMBER_IN_WEEK = S.DAY_NUMBER_IN_WEEK
            , T.DAY_NUMBER_IN_YEAR = S.DAY_NUMBER_IN_YEAR
            , T.WEEK_NUMBER_IN_YEAR = S.WEEK_NUMBER_IN_YEAR
            , T.MONTH_NUMBER_IN_YEAR = S.MONTH_NUMBER_IN_YEAR
            , T.QUARTER_NUMBER_IN_YEAR = S.QUARTER_NUMBER_IN_YEAR
            , T.IS_WEEKEND = S.IS_WEEKEND
            , T.YEAR_NUMBER = S.YEAR_NUMBER
            , T.DAY_NAME = S.DAY_NAME
            , T.MONTH_NAME = S.MONTH_NAME
            , T.JULIAN_DATE = S.JULIAN_DATE
            , T.ASAT_JULIAN = S.ASAT_JULIAN
            , T.ISO_WEEK = S.ISO_WEEK
            , T.ISO_YEAR = S.ISO_YEAR
            , T.FISCAL_DAY = S.FISCAL_DAY
            , T.FISCAL_WEEK = S.FISCAL_WEEK
            , T.FISCAL_MONTH = S.FISCAL_MONTH
            , T.FISCAL_QUARTER = S.FISCAL_QUARTER
            , T.FISCAL_YEAR = S.FISCAL_YEAR
            , T.TAX_PERIOD = S.TAX_PERIOD
            , T.TAX_QUARTER = S.TAX_QUARTER
            , T.TAX_YEAR = S.TAX_YEAR
            , T.LONG_DATE_DESCRIPTION = S.LONG_DATE_DESCRIPTION
            , T.MONTH_END_INDICATOR = S.MONTH_END_INDICATOR
            , T.PUBLIC_HOLIDAY_INDICATOR = S.PUBLIC_HOLIDAY_INDICATOR
            , T.YEAR_QUARTER = S.YEAR_QUARTER
            , T.YEAR_MONTH = S.YEAR_MONTH
            , T.YEAR_ISO_WEEK = S.YEAR_ISO_WEEK
            , T.NUMBER_OF_DAYS_IN_MONTH = S.NUMBER_OF_DAYS_IN_MONTH
            , T.NUMBER_OF_DAYS_IN_YEAR = S.NUMBER_OF_DAYS_IN_YEAR
            , T.YEAR_HALFYEAR = S.YEAR_HALFYEAR
            , T.TRADING_WEEK = S.TRADING_WEEK
            , T.LOAD_DATE = S.LOAD_DATE
            , T.LOAD_TIME = S.LOAD_TIME

    WHEN NOT MATCHED THEN
        INSERT (
              SK_DATE
            , CALENDAR_DATE
            , MONTH_YEAR
            , DAY_NUMBER_IN_WEEK
            , DAY_NUMBER_IN_YEAR
            , WEEK_NUMBER_IN_YEAR
            , MONTH_NUMBER_IN_YEAR
            , QUARTER_NUMBER_IN_YEAR
            , IS_WEEKEND
            , YEAR_NUMBER
            , DAY_NAME
            , MONTH_NAME
            , JULIAN_DATE
            , ASAT_JULIAN
            , ISO_WEEK
            , ISO_YEAR
            , FISCAL_DAY
            , FISCAL_WEEK
            , FISCAL_MONTH
            , FISCAL_QUARTER
            , FISCAL_YEAR
            , TAX_PERIOD
            , TAX_QUARTER
            , TAX_YEAR
            , LONG_DATE_DESCRIPTION
            , MONTH_END_INDICATOR
            , PUBLIC_HOLIDAY_INDICATOR
            , YEAR_QUARTER
            , YEAR_MONTH
            , YEAR_ISO_WEEK
            , NUMBER_OF_DAYS_IN_MONTH
            , NUMBER_OF_DAYS_IN_YEAR
            , YEAR_HALFYEAR
            , TRADING_WEEK
            , LOAD_DATE
            , LOAD_TIME
        )
        VALUES (
              S.SK_DATE
            , S.CALENDAR_DATE
            , S.MONTH_YEAR
            , S.DAY_NUMBER_IN_WEEK
            , S.DAY_NUMBER_IN_YEAR
            , S.WEEK_NUMBER_IN_YEAR
            , S.MONTH_NUMBER_IN_YEAR
            , S.QUARTER_NUMBER_IN_YEAR
            , S.IS_WEEKEND
            , S.YEAR_NUMBER
            , S.DAY_NAME
            , S.MONTH_NAME
            , S.JULIAN_DATE
            , S.ASAT_JULIAN
            , S.ISO_WEEK
            , S.ISO_YEAR
            , S.FISCAL_DAY
            , S.FISCAL_WEEK
            , S.FISCAL_MONTH
            , S.FISCAL_QUARTER
            , S.FISCAL_YEAR
            , S.TAX_PERIOD
            , S.TAX_QUARTER
            , S.TAX_YEAR
            , S.LONG_DATE_DESCRIPTION
            , S.MONTH_END_INDICATOR
            , S.PUBLIC_HOLIDAY_INDICATOR
            , S.YEAR_QUARTER
            , S.YEAR_MONTH
            , S.YEAR_ISO_WEEK
            , S.NUMBER_OF_DAYS_IN_MONTH
            , S.NUMBER_OF_DAYS_IN_YEAR
            , S.YEAR_HALFYEAR
            , S.TRADING_WEEK
            , S.LOAD_DATE
            , S.LOAD_TIME
        );

END;