CREATE     PROCEDURE SP_BUILD_SEMANTIC_MODEL_TABLES
AS
BEGIN
    SET NOCOUNT ON;

    /********************************************************************
     PROCEDURE: SP_BUILD_SEMANTIC_MODEL_TABLES
     PURPOSE  : Materialise all reporting tables used by the Semantic Model
     NOTES    :
       - Replaces reporting views with physical tables
       - Each table reflects its original view logic exactly
       - Tables are dropped and recreated on each execution
       - Semantic model refresh must run AFTER this procedure
     ********************************************************************/

    /* ================================================================
       TABLE: PARTY_DETAIL_ACTIVE
       SOURCE: gold.DIM_PARTY_DETAIL
       REPLACES VIEW: gold.VW_PARTY_DETAIL
       ================================================================ */
    IF OBJECT_ID('[PARTY_DETAIL_ACTIVE]', 'U') IS NOT NULL
        DROP TABLE [PARTY_DETAIL_ACTIVE];

    CREATE TABLE [PARTY_DETAIL_ACTIVE] (
        SK_PARTY_DETAIL          VARCHAR(36),  -- Surrogate key
        PARTY_MDM_ID             VARCHAR(50),  -- Business party identifier
        GENDER                   VARCHAR(20),  -- Normalised gender value
        PARTY_TYPE               VARCHAR(50),  -- Party classification
        DOB                      DATE,         -- Date of birth
        AGE_BAND                 VARCHAR(20),  -- Derived age band
        RELATIONSHIP_START_DATE  DATE,         -- Relationship start date
        RELATIONSHIP_START_YEAR  VARCHAR(4),   -- Year for reporting
        CUSTOMER_TENURE_BAND     VARCHAR(20),  -- Derived tenure band
        AGE_GROUP_SORT           INT,          -- Age band sort order
        TENURE_SORT              INT           -- Tenure band sort order
    );

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
        END,
        CASE
            WHEN CUSTOMER_TENURE_BAND = 'Unknown' THEN 5
            WHEN CUSTOMER_TENURE_BAND = '0-5 Years' THEN 1
            WHEN CUSTOMER_TENURE_BAND = '5-10 Years' THEN 2
            WHEN CUSTOMER_TENURE_BAND = '10-20 Years' THEN 3
            ELSE 4
        END
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
                WHEN DATEDIFF(YEAR, DOB, GETDATE()) < 20 THEN '<20'
                WHEN DATEDIFF(YEAR, DOB, GETDATE()) BETWEEN 20 AND 29 THEN '20-29'
                WHEN DATEDIFF(YEAR, DOB, GETDATE()) BETWEEN 30 AND 39 THEN '30-39'
                WHEN DATEDIFF(YEAR, DOB, GETDATE()) BETWEEN 40 AND 49 THEN '40-49'
                WHEN DATEDIFF(YEAR, DOB, GETDATE()) BETWEEN 50 AND 59 THEN '50-59'
                ELSE '60+'
            END AS AGE_BAND,
            CAST(RELATIONSHIP_START_DATE AS DATE) AS RELATIONSHIP_START_DATE,
            FORMAT(RELATIONSHIP_START_DATE,'yyyy') AS RELATIONSHIP_START_YEAR,
            CASE
                WHEN RELATIONSHIP_START_DATE IS NULL THEN 'Unknown'
                WHEN DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()) < 5 THEN '0-5 Years'
                WHEN DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()) < 10 THEN '5-10 Years'
                WHEN DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()) < 20 THEN '10-20 Years'
                ELSE '20+ Years'
            END AS CUSTOMER_TENURE_BAND
        FROM [gold].[DIM_PARTY_DETAIL]
        WHERE (RELATIONSHIP_END_DATE IS NULL OR RELATIONSHIP_END_DATE > GETDATE())
          AND END_DATE IS NULL
    ) t;

    /* ================================================================
       TABLE: PARTY_FLAG_ACTIVE
       REPLACES VIEW: gold.VW_PARTY_FLAG
       ================================================================ */
    IF OBJECT_ID('[PARTY_FLAG_ACTIVE]', 'U') IS NOT NULL
        DROP TABLE [PARTY_FLAG_ACTIVE];

    CREATE TABLE [PARTY_FLAG_ACTIVE] (
        SK_PARTY_FLAG        VARCHAR(36),
        PARTY_MDM_ID         VARCHAR(50),
        IS_ASSUMED_VC_FLAG   BIT,
        IS_DORMANT_FLAG      BIT,
        IS_DECEASED_FLAG     BIT,
        MCNR_DEBT_FLAG       BIT,
        OPEN_COMPLAINT_FLAG  BIT,
        OPEN_LITIGATION_FLAG BIT
    );

    INSERT INTO [PARTY_FLAG_ACTIVE]
    SELECT
        CAST(SK_PARTY_FLAG AS VARCHAR(36)),
        PARTY_MDM_ID,
        IS_ASSUMED_VC_FLAG,
        IS_DORMANT_FLAG,
        IS_DECEASED_FLAG,
        MCNR_DEBT_FLAG,
        OPEN_COMPLAINT_FLAG,
        OPEN_LITIGATION_FLAG
    FROM [gold].[DIM_PARTY_FLAG]
    WHERE END_DATE IS NULL;

    /* ================================================================
       TABLE: PARTY_NATIONALITY_ACTIVE
       REPLACES VIEW: gold.VW_PARTY_NATIONALITY
       ================================================================ */
    IF OBJECT_ID('[PARTY_NATIONALITY_ACTIVE]', 'U') IS NOT NULL
        DROP TABLE [PARTY_NATIONALITY_ACTIVE];

    CREATE TABLE [PARTY_NATIONALITY_ACTIVE] (
        SK_PARTY_NATIONALITY   VARCHAR(36),
        PARTY_MDM_ID           VARCHAR(50),
        NATIONALITY            VARCHAR(100),
        FIRST_DECL_NTNLTY_FLAG BIT
    );

    INSERT INTO [PARTY_NATIONALITY_ACTIVE]
    SELECT 
        CAST(N.SK_PARTY_NATIONALITY AS VARCHAR(36)),
        D.PARTY_MDM_ID,
        COALESCE(N.NATIONALITY, 'UNKNOWN'),
        N.FIRST_DECL_NTNLTY_FLAG
    FROM [gold].[DIM_PARTY_DETAIL] D
    LEFT JOIN [gold].[DIM_PARTY_NATIONALITY] N
           ON N.PARTY_MDM_ID = D.PARTY_MDM_ID
          AND N.END_DATE IS NULL
    WHERE (D.RELATIONSHIP_END_DATE IS NULL OR D.RELATIONSHIP_END_DATE > GETDATE())
      AND D.END_DATE IS NULL;

    /* ================================================================
       TABLE: PARTY_CONTACT_ACTIVE
       REPLACES VIEW: gold.VW_PARTY_CONTACT
       ================================================================ */
    IF OBJECT_ID('[PARTY_CONTACT_ACTIVE]', 'U') IS NOT NULL
        DROP TABLE [PARTY_CONTACT_ACTIVE];

    CREATE TABLE [PARTY_CONTACT_ACTIVE] (
        SK_PARTY_CONTACT VARCHAR(36),
        PARTY_MDM_ID     VARCHAR(50),
        POSTCODE         VARCHAR(20),
        COUNTRY          VARCHAR(50),
        ADDRESS_TYPE     VARCHAR(50)
    );

    INSERT INTO [PARTY_CONTACT_ACTIVE]
    SELECT
        CAST(PC.SK_PARTY_CONTACT AS VARCHAR(36)),
        PD.PARTY_MDM_ID,
        PC.POSTCODE,
        PC.COUNTRY,
        PC.ADDRESS_TYPE
    FROM [gold].[DIM_PARTY_DETAIL] PD
    LEFT JOIN [gold].[DIM_PARTY_CONTACT] PC
           ON PC.PARTY_MDM_ID = PD.PARTY_MDM_ID
          AND PC.END_DATE IS NULL
    WHERE PD.END_DATE IS NULL
      AND (PD.RELATIONSHIP_END_DATE IS NULL OR PD.RELATIONSHIP_END_DATE > GETDATE());

END;