CREATE     PROCEDURE SP_PARTY_DETAIL
AS
BEGIN
    SET NOCOUNT ON;

    -- Drop the table if it exists
    IF OBJECT_ID('[PARTY_DETAIL_ACTIVE]', 'U') IS NOT NULL
        DROP TABLE [PARTY_DETAIL_ACTIVE];

    -- Recreate the table
    CREATE TABLE [PARTY_DETAIL_ACTIVE] (
        SK_PARTY_DETAIL            VARCHAR(36),
        PARTY_MDM_ID               VARCHAR(50),
        GENDER                     VARCHAR(20),
        PARTY_TYPE                 VARCHAR(50),
        DOB                        DATE,
        AGE_BAND                   VARCHAR(20),
        RELATIONSHIP_START_DATE    DATE,
        RELATIONSHIP_START_YEAR    VARCHAR(4),
        CUSTOMER_TENURE_BAND       VARCHAR(20),
        AGE_GROUP_SORT             INT,
        TENURE_SORT                INT
    );

    -- Insert data
    INSERT INTO [PARTY_DETAIL_ACTIVE]
    SELECT
        t.SK_PARTY_DETAIL,
        t.PARTY_MDM_ID,
        t.GENDER,
        t.PARTY_TYPE,
        t.DOB,
        t.AGE_BAND,
        t.RELATIONSHIP_START_DATE,
        t.RELATIONSHIP_START_YEAR,
        t.CUSTOMER_TENURE_BAND,

        CASE 
            WHEN AGE_BAND = 'Unknown' THEN 7
            WHEN AGE_BAND = '<20' THEN 1
            WHEN AGE_BAND = '20-29' THEN 2
            WHEN AGE_BAND = '30-39' THEN 3
            WHEN AGE_BAND = '40-49' THEN 4
            WHEN AGE_BAND = '50-59' THEN 5
            ELSE 6
        END AS AGE_GROUP_SORT,

        CASE
            WHEN CUSTOMER_TENURE_BAND = 'Unknown' THEN 5
            WHEN CUSTOMER_TENURE_BAND = '0-5 Years' THEN 1
            WHEN CUSTOMER_TENURE_BAND = '5-10 Years' THEN 2
            WHEN CUSTOMER_TENURE_BAND = '10-20 Years' THEN 3
            ELSE 4
        END AS TENURE_SORT
    FROM (
        SELECT
            CAST(SK_PARTY_DETAIL AS VARCHAR(36)) AS SK_PARTY_DETAIL,
            PARTY_MDM_ID,

            CASE 
                WHEN GENDER IS NULL OR LTRIM(RTRIM(GENDER)) = '' THEN 'Unknown'
                WHEN GENDER = 'F' THEN 'Female'
                WHEN GENDER = 'M' THEN 'Male'
                ELSE GENDER
            END AS GENDER,

            PARTY_TYPE,
            DOB,

            CASE
                WHEN DOB IS NULL THEN 'Unknown'
                ELSE
                    CASE
                        WHEN
                            (
                                DATEDIFF(YEAR, DOB, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) < 20
                        THEN '<20'
                        WHEN
                            (
                                DATEDIFF(YEAR, DOB, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) BETWEEN 20 AND 29
                        THEN '20-29'
                        WHEN
                            (
                                DATEDIFF(YEAR, DOB, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) BETWEEN 30 AND 39
                        THEN '30-39'
                        WHEN
                            (
                                DATEDIFF(YEAR, DOB, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) BETWEEN 40 AND 49
                        THEN '40-49'
                        WHEN
                            (
                                DATEDIFF(YEAR, DOB, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) BETWEEN 50 AND 59
                        THEN '50-59'
                        ELSE '60+'
                    END
            END AS AGE_BAND,

            CAST(RELATIONSHIP_START_DATE AS DATE) AS RELATIONSHIP_START_DATE,
            FORMAT(RELATIONSHIP_START_DATE, 'yyyy') AS RELATIONSHIP_START_YEAR,

            CASE
                WHEN RELATIONSHIP_START_DATE IS NULL THEN 'Unknown'
                ELSE
                    CASE 
                        WHEN
                            (
                                DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()), RELATIONSHIP_START_DATE) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) < 5
                        THEN '0-5 Years'
                        WHEN
                            (
                                DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()), RELATIONSHIP_START_DATE) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) < 10
                        THEN '5-10 Years'
                        WHEN
                            (
                                DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE())
                                - CASE
                                      WHEN DATEADD(YEAR, DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()), RELATIONSHIP_START_DATE) > GETDATE()
                                      THEN 1
                                      ELSE 0
                                  END
                            ) < 20
                        THEN '10-20 Years'
                        ELSE '20+ Years'
                    END
            END AS CUSTOMER_TENURE_BAND
        FROM [gold].[DIM_PARTY_DETAIL]
        WHERE (RELATIONSHIP_END_DATE IS NULL OR RELATIONSHIP_END_DATE > GETDATE())
          AND END_DATE IS NULL
    ) t;
END;