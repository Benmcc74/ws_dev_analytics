CREATE                                      PROCEDURE [gold].[sp_PARTY_NATIONALITY]
(
   @batch_id NVARCHAR(100)
)
AS
BEGIN
 

DECLARE @CurrentTimestamp DATETIME = GETDATE();

    DECLARE @insert_new    int = 0;
    DECLARE @insert_changed int = 0;
    DECLARE @deleted int = 0;
    DECLARE @source_count int = 0;
    DECLARE @updated int = 0;

-- 1. Prepare Source Data with HASH_VALUE in a temporary table

DROP TABLE IF EXISTS #SourceStaging_Nationality;
SELECT
    PN.PARTY_MDM_ID AS PARTY_MDM_ID,
    PN.NATIONALITY_CODE AS NATIONALITY,
    PN.FIRST_DECLARED_NTNLTY_FLAG,
    PN.VALID_FROM AS START_DATE,
    PN.DELETED_FLAG AS DELETED_FLAG,
    PN.VALID_TO AS VALID_TO,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
        CONCAT_WS('|',
            PN.PARTY_MDM_ID,
            PN.NATIONALITY_CODE,
            PN.FIRST_DECLARED_NTNLTY_FLAG
        )
    ), 2) AS HASH_VALUE
INTO #SourceStaging_Nationality
FROM
    [LHDEVGOLDSTAGING].[silver].[party_nationalities] AS PN
WHERE
    PN.VALID_TO IS NULL and PN.DELETED_FLAG = 'N'; -- Only consider currently active records from source

SET @source_count = @@ROWCOUNT;


    ---------------------------------------------------------
    -- Insert FIRST‑TIME records (START_DATE = source VALID_FROM)
    ---------------------------------------------------------
INSERT INTO [gold].[DIM_PARTY_NATIONALITY] (
    SK_PARTY_NATIONALITY,
    PARTY_MDM_ID,
    NATIONALITY,
    FIRST_DECL_NTNLTY_FLAG,
    START_DATE,
    END_DATE,
    HASH_VALUE,
    DELETED_FLAG,
    BATCH_ID
)
SELECT
   DISTINCT
    NEWID(),
    Source.PARTY_MDM_ID,
    Source.NATIONALITY,
    Source.FIRST_DECLARED_NTNLTY_FLAG,
    Source.START_DATE AS START_DATE,
    NULL AS END_DATE,      -- Active until further update
    CONVERT(VARCHAR(64), Source.HASH_VALUE) AS HASH_VALUE,
    Source.DELETED_FLAG AS DELETED_FLAG,               
    @batch_id
FROM
    #SourceStaging_Nationality AS Source
LEFT JOIN
    [gold].[DIM_PARTY_NATIONALITY] AS Target
    ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID  COLLATE DATABASE_DEFAULT
    WHERE
        Target.PARTY_MDM_ID IS NULL; -- This condition identifies truly new records (First time insert only)

SET @insert_new = @@ROWCOUNT;
    ---------------------------------------------------------
    -- Insert UPDATED versions (START_DATE = SYSDATE)
    ---------------------------------------------------------
INSERT INTO [gold].[DIM_PARTY_NATIONALITY] (
    SK_PARTY_NATIONALITY,
    PARTY_MDM_ID,
    NATIONALITY,
    FIRST_DECL_NTNLTY_FLAG,
    START_DATE,
    END_DATE,
    HASH_VALUE,
    DELETED_FLAG,
    BATCH_ID
)
SELECT
    NEWID(),
    Source.PARTY_MDM_ID,
    Source.NATIONALITY,
    Source.FIRST_DECLARED_NTNLTY_FLAG,
    @CurrentTimestamp  AS START_DATE,
    NULL AS END_DATE,      -- Active until further update
    CONVERT(VARCHAR(64), Source.HASH_VALUE) AS HASH_VALUE,
    Source.DELETED_FLAG AS DELETED_FLAG,                 
    @batch_id
FROM
    #SourceStaging_Nationality AS Source
INNER JOIN
    [gold].[DIM_PARTY_NATIONALITY] AS Target
    ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID  COLLATE DATABASE_DEFAULT
    WHERE
                     Target.HASH_VALUE <> Source.HASH_VALUE -- This condition identifies new records as part of updates records
                     AND Target.END_DATE IS NULL
     AND Target.DELETED_FLAG = 'N'
;

SET @insert_changed = @insert_new + @@ROWCOUNT;

-- 2. Expire Old Records (SCD Type 2 Update)
-- Identify active records in DIM_PARTY_NATIONALITY that have changed in the source
-- and set their END_DATE to close them off.
UPDATE Target
SET
    Target.END_DATE = DATEADD(ms, -3, @CurrentTimestamp) -- End the old record just before the new one starts

FROM
    [gold].[DIM_PARTY_NATIONALITY] AS Target
INNER JOIN
    #SourceStaging_Nationality AS Source
    ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID  COLLATE DATABASE_DEFAULT
WHERE
    Target.END_DATE IS NULL  -- Only update currently active records
    AND Target.DELETED_FLAG = 'N'     -- Only update non-deleted records
    AND Target.HASH_VALUE <> Source.HASH_VALUE; -- Only update if attributes have changed
    
SET @updated = @@ROWCOUNT;
    --------------------------------------------------------------------
    --  Soft Delete Logic (based ONLY on most recent silver row)
    --------------------------------------------------------------------
---- This fetches only the impacted ids in the current batch
DROP TABLE IF EXISTS #ChangedKeys;
 
SELECT DISTINCT PARTY_MDM_ID
INTO #ChangedKeys
FROM [LHDEVGOLDSTAGING].[silver].[party_nationalities]
WHERE BATCH_ID = @batch_id AND DELETED_FLAG = 'Y';


    UPDATE T
    SET
        T.DELETED_FLAG = 'Y',
        T.END_DATE = DATEADD(ms, -3, @CurrentTimestamp)
	FROM gold.DIM_PARTY_NATIONALITY T
    INNER JOIN #ChangedKeys F
        ON T.PARTY_MDM_ID = F.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE 
       T.END_DATE IS NULL
      AND T.DELETED_FLAG = 'N';

SET @updated = @updated + @@ROWCOUNT

-- 4. Handle Deletions 

    ---------------------------------------------------------
    -- 1. Capture IDs to delete
    ---------------------------------------------------------

    DROP TABLE IF EXISTS #silverIDstoDelete;
 
    SELECT DISTINCT PARTY_MDM_ID
    INTO #silverIDstoDelete
    FROM [LHDEVGOLDSTAGING].[silver].[party_nationalities]
    ;

    DROP TABLE IF EXISTS  #IDsToDelete;
    SELECT T.PARTY_MDM_ID AS ID
    INTO #IDsToDelete
    FROM gold.DIM_PARTY_NATIONALITY AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;

    

    ---------------------------------------------------------
    -- 2. Delete from target table
    ---------------------------------------------------------
    DELETE FROM gold.DIM_PARTY_NATIONALITY
    WHERE PARTY_MDM_ID IN (SELECT ID FROM #IDsToDelete);
    SET @deleted = @@ROWCOUNT;

    ---------------------------------------------------------
    -- 3. Insert audit log
    ---------------------------------------------------------
    INSERT INTO audit.ops_delete_log
    (
        ATTRIBUTE_NAME,
        ATTRIBUTE_VALUE,
        EVENT_TYPE,
        SOURCE_TABLE,
        TARGET_TABLE,
        DELETED_DATE,
        BATCH_ID
    )
    SELECT
        'PARTY_MDM_ID' AS ATTRIBUTE_NAME,
        ID AS ATTRIBUTE_VALUE,
        'DELETE' AS EVENT_TYPE,
        'silver.party_nationalities' AS SOURCE_TABLE,
        'gold.DIM_PARTY_NATIONALITY' AS TARGET_TABLE,
        CURRENT_TIMESTAMP AS DELETED_DATE,
        @batch_id AS BATCH_ID
    FROM #IDsToDelete;

    INSERT INTO audit.ops_record_count_log
    (
        BATCH_ID,
        SOURCE_TABLE,
        TARGET_TABLE,
        CREATED_DATE,
        SOURCE_RECORDS,
        INSERT_RECORDS,
        UPDATE_RECORDS,
        DELETE_RECORDS
           )
    SELECT
        @batch_id AS BATCH_ID,
        'silver.party_nationalities' AS SOURCE_TABLE,
        'gold.DIM_PARTY_NATIONALITY' AS TARGET_TABLE,
        SYSUTCDATETIME()                         AS EVENT_DATE,
        COALESCE(@source_count,   0) AS SOURCE_RECORDS,
        COALESCE(@insert_changed,     0) AS INSERT_RECORDS,
        COALESCE(@updated, 0) AS UPDATE_RECORDS,
        COALESCE(@deleted,        0) AS DELETE_RECORDS;
    ---------------------------------------------------------
    -- 4. Cleanup
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #IDsToDelete;
    DROP TABLE IF EXISTS #ChangedKeys;
    DROP TABLE IF EXISTS #silverIDstoDelete;
 
 
    -- Clean up the temporary table
    DROP TABLE IF EXISTS #SourceStaging_Nationality;

END;