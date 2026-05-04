CREATE   Procedure test_Gold_Scd
as
    DECLARE @CurrentBatchId NVARCHAR(100) = 'Load_' + FORMAT(GETDATE(), 'yyyyMMddHHmmss');

    DECLARE @FutureEndDate DATETIME = '9999-12-31 23:59:59.997';

    DECLARE @CurrentTimestamp DATETIME = GETDATE();
 
    -- 1. Prepare Source Data with HASH_VALUE in a temporary table

    -- This makes it easier to reference the source data multiple times.

    DROP TABLE IF EXISTS #SourceStaging;
 
    SELECT
            PEOPLE.PARTY_ID AS PARTY_MDM_ID,
            -- Default empty strings for columns not directly mapped or if source is NULL
            '' AS PARTY_TYPE,
            '' AS STATUS,
            PEOPLE.FIRST_NAMES AS FIRST_NAMES,
            PEOPLE.LAST_NAME AS LAST_NAME,
            PEOPLE.TITLE_CODE AS TITLE,
            PEOPLE.SUFFIX AS SUFFIX,
            ISNULL(PEOPLE.GENDER_CODE, '') AS GENDER,
            PEOPLE.DATE_OF_BIRTH AS DOB,
            ISNULL(PEOPLE.MARITAL_STATUS_CODE, '') AS MARITAL_STATUS,
            PEOPLE.NATIONAL_INSURANCE_NUMBER AS NI_NUMBER,
            PEOPLE.TAX_ID_NUMBER AS TAX_ID_NUMBER,
            PEOPLE.TAX_DOMICILE_CODE AS TAX_DOMICILE,
            -- Assuming FATCA_ELIGIBLE is a BIT, convert if necessary
            '' AS FATCA_ELIGIBLE,
            PEOPLE.RELATIONSHIP_START_DATE AS RELATIONSHIP_START_DATE,
            PEOPLE.RELATIONSHIP_END_DATE AS RELATIONSHIP_END_DATE,
           '' AS RETENTION_END_DATE, -- Use a default for hash if NULL
            PEOPLE.DECEASED_DATE AS DECEASED_DATE,
            PEOPLE.DECEASED_NOTIFICATION_DATE AS DECEASED_NOTIFICATION_DATE,
            PEOPLE.DECEASED_EVIDENCE_DATE AS DECEASED_EVIDENCE_DATE,
            -- VALID_FROM and VALID_TO from source might be used for initial load,
            -- but for SCD Type 2, START_DATE/END_DATE are managed by the procedure.
            -- We'll use GETDATE() for new records' START_DATE.
            -- PEOPLE.VALID_FROM AS SOURCE_VALID_FROM,
            -- PEOPLE.VALID_TO AS SOURCE_VALID_TO,
 
            -- Calculate HASH_VALUE for change detection.
            -- Concatenate all relevant columns and hash them.
            -- Ensure consistent data types for hashing.
            HASHBYTES('SHA2_256',
                CONCAT_WS('|',
                    PEOPLE.PARTY_ID,
                    ISNULL('', ''),
                    ISNULL('', ''),
                    PEOPLE.FIRST_NAMES,
                    PEOPLE.LAST_NAME,
                    ISNULL(PEOPLE.TITLE_CODE, ''),
                    PEOPLE.SUFFIX,
                    ISNULL(PEOPLE.GENDER_CODE, ''),
                    FORMAT(PEOPLE.DATE_OF_BIRTH, 'yyyy-MM-dd'), -- Format dates for consistent hashing
                    ISNULL(PEOPLE.MARITAL_STATUS_CODE, ''),
                    PEOPLE.NATIONAL_INSURANCE_NUMBER,
                    PEOPLE.TAX_ID_NUMBER,
                    PEOPLE.TAX_DOMICILE_CODE,
                    '', -- Convert BIT to string
                    FORMAT(PEOPLE.RELATIONSHIP_START_DATE, 'yyyy-MM-dd'),
                    FORMAT(PEOPLE.RELATIONSHIP_END_DATE, 'yyyy-MM-dd'),
                    '',
                    FORMAT(PEOPLE.DECEASED_DATE, 'yyyy-MM-dd'),
                    FORMAT(PEOPLE.DECEASED_NOTIFICATION_DATE, 'yyyy-MM-dd'),
                    FORMAT(PEOPLE.DECEASED_EVIDENCE_DATE, 'yyyy-MM-dd')
                )
            ) AS HASH_VALUE
 

    INTO #SourceStaging

    FROM [LHDEVGOLDSTAGINGTEMP].[silver].[people] AS PEOPLE;


	    -- 2. Expire Old Records (SCD Type 2 Update)

    -- Identify active records in DIM_PARTY_DETAILS that have changed in the source

    -- and set their END_DATE to close them off.

    UPDATE Target

    SET

        Target.END_DATE = DATEADD(ms, -3, @CurrentTimestamp), -- End the old record just before the new one starts

        Target.BATCH_ID = @CurrentBatchId

    FROM

        [dbo].[DIM_PARTY_DETAIL] AS Target

    INNER JOIN

        #SourceStaging AS Source

        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT

    WHERE

        Target.END_DATE = @FutureEndDate -- Only update currently active records

        AND Target.DELETED_FLAG = 0       -- Only update non-deleted records

        AND Target.HASH_VALUE <> Source.HASH_VALUE; -- Only update if attributes have changed



	    -- 3. Insert New Records and New Versions of Updated Records

    -- This includes:

    --   a) Completely new records (not in DIM_PARTY_DETAILS at all).

    --   b) New versions of records that were just expired in step 2.

    INSERT INTO [dbo].[DIM_PARTY_DETAIL] (

        [PARTY_MDM_ID],

        [PARTY_TYPE],

        [STATUS],

        [FIRST_NAMES],

        [LAST_NAME],

        [TITLE],

        [SUFFIX],

        [GENDER],

        [DOB],

        [MARITAL_STATUS],

        [NI_NUMBER],

        [TAX_ID_NUMBER],

        [TAX_DOMICILE],

        [FATCA_ELIGIBLE],

        [RELATIONSHIP_START_DATE],

        [RELATIONSHIP_END_DATE],

        [RETENTION_END_DATE],

        [DECEASED_DATE],

        [DECEASED_NOTIFICATION_DATE],

        [DECEASED_EVIDENCE_DATE],

        [START_DATE],

        [END_DATE],

        [HASH_VALUE],

        [DELETED_FLAG],

        [BATCH_ID]

    )

    SELECT

        Source.PARTY_MDM_ID,

        Source.PARTY_TYPE,

        Source.STATUS,

        Source.FIRST_NAMES,

        Source.LAST_NAME,

        Source.TITLE,

        Source.SUFFIX,

        Source.GENDER,

        Source.DOB,

        Source.MARITAL_STATUS,

        Source.NI_NUMBER,

        Source.TAX_ID_NUMBER,

        Source.TAX_DOMICILE,

        Source.FATCA_ELIGIBLE,

        Source.RELATIONSHIP_START_DATE,

        Source.RELATIONSHIP_END_DATE,

        Source.RETENTION_END_DATE,

        Source.DECEASED_DATE,

        Source.DECEASED_NOTIFICATION_DATE,

        Source.DECEASED_EVIDENCE_DATE,

        @CurrentTimestamp AS START_DATE, -- New record starts now

        @FutureEndDate AS END_DATE,      -- Active until further notice

        Source.HASH_VALUE,

        0 AS DELETED_FLAG,               -- Not deleted

        @CurrentBatchId

    FROM

        #SourceStaging AS Source

    LEFT JOIN

        [dbo].[DIM_PARTY_DETAIL] AS Target

        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT -- Collation fix

        AND Target.END_DATE = @FutureEndDate -- Only consider currently active records in target

        AND Target.DELETED_FLAG = 0

        -- Explicitly cast HASH_VALUE in the ON clause to prevent implicit conversion issues

        AND CAST(Target.HASH_VALUE AS VARBINARY(64)) = CAST(Source.HASH_VALUE AS VARBINARY(64))

    WHERE

        Target.PARTY_MDM_ID IS NULL -- This condition identifies truly new records

        OR (

            Target.PARTY_MDM_ID IS NOT NULL

            AND CAST(Target.HASH_VALUE AS VARBINARY(64)) <> CAST(Source.HASH_VALUE AS VARBINARY(64)) -- This condition identifies updated records

        );
 

 -- 4. Handle Deletions (SCD Type 2 Logical Delete)
    -- Identify active records in DIM_PARTY_DETAILS that are no longer present in the source
    -- and mark them as logically deleted by setting DELETED_FLAG and ending their validity.
    UPDATE Target
    SET
        Target.END_DATE = DATEADD(ms, -3, @CurrentTimestamp), -- End the record
        Target.DELETED_FLAG = 1, -- Mark as logically deleted
        Target.BATCH_ID = @CurrentBatchId
    FROM
        [dbo].[DIM_PARTY_DETAIL] AS Target
    LEFT JOIN
        #SourceStaging AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE
        Source.PARTY_MDM_ID IS NULL -- Record exists in target but not in source
        AND Target.END_DATE = @FutureEndDate -- Only update currently active records
        AND Target.DELETED_FLAG = 0; -- Only update non-deleted records
 
    -- Clean up the temporary table
    DROP TABLE IF EXISTS #SourceStaging;