CREATE                                               PROCEDURE [gold].[sp_PARTY_DETAIL]
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

    DROP TABLE IF EXISTS #SourceStaging; 
    SELECT
            PEOPLE.PARTY_MDM_ID AS PARTY_MDM_ID,
            NULL AS PARTY_TYPE,
            PARTIES.STATUS AS STATUS,
            PEOPLE.FIRST_NAMES AS FIRST_NAMES,
            PEOPLE.LAST_NAME AS LAST_NAME,
            PEOPLE.TITLE_CODE AS TITLE,
            PEOPLE.SUFFIX AS SUFFIX,
            PEOPLE.GENDER_CODE AS GENDER,
            PEOPLE.DATE_OF_BIRTH AS DOB,
            PEOPLE.MARITAL_STATUS_CODE AS MARITAL_STATUS,
            PEOPLE.NATIONAL_INSURANCE_NUMBER AS NI_NUMBER,
            PEOPLE.TAX_ID_NUMBER AS TAX_ID_NUMBER,
            PEOPLE.TAX_DOMICILE_CODE AS TAX_DOMICILE,
            NULL AS FATCA_ELIGIBLE,
            PEOPLE.RELATIONSHIP_START_DATE AS RELATIONSHIP_START_DATE,
            PEOPLE.RELATIONSHIP_END_DATE AS RELATIONSHIP_END_DATE,
            CAST(NULL AS DATETIME2(6)) AS RETENTION_END_DATE,
            PEOPLE.DECEASED_DATE AS DECEASED_DATE,
            PEOPLE.DECEASED_NOTIFICATION_DATE AS DECEASED_NOTIFICATION_DATE,
            PEOPLE.DECEASED_EVIDENCE_DATE AS DECEASED_EVIDENCE_DATE,
            PEOPLE.VALID_FROM AS START_DATE,
            PEOPLE.DELETED_FLAG AS DELETED_FLAG,
            PEOPLE.VALID_TO AS VALID_TO,
    CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
                CONCAT_WS('|',
                    PEOPLE.PARTY_MDM_ID,
                     '', 
                     '', 
                    PEOPLE.FIRST_NAMES,
                    PEOPLE.LAST_NAME,
                    PEOPLE.TITLE_CODE,
                    PEOPLE.SUFFIX,
                    PEOPLE.GENDER_CODE,
                    FORMAT(PEOPLE.DATE_OF_BIRTH, 'yyyy-MM-dd'), -- Format dates for consistent hashing
                    PEOPLE.MARITAL_STATUS_CODE,
                    PEOPLE.NATIONAL_INSURANCE_NUMBER,
                    PEOPLE.TAX_ID_NUMBER,
                    PEOPLE.TAX_DOMICILE_CODE,
                    '', 
                    FORMAT(PEOPLE.RELATIONSHIP_START_DATE, 'yyyy-MM-dd'),
                    FORMAT(PEOPLE.RELATIONSHIP_END_DATE, 'yyyy-MM-dd'),
                    '',
                    FORMAT(PEOPLE.DECEASED_DATE, 'yyyy-MM-dd'),
                    FORMAT(PEOPLE.DECEASED_NOTIFICATION_DATE, 'yyyy-MM-dd'),
                    FORMAT(PEOPLE.DECEASED_EVIDENCE_DATE, 'yyyy-MM-dd')            
                )
            ) , 2) AS HASH_VALUE 

    INTO #SourceStaging
    FROM [LHDEVGOLDSTAGING].[silver].[people] AS PEOPLE
    LEFT JOIN [LHDEVGOLDSTAGING].[silver].[parties] AS PARTIES
    ON PEOPLE.PARTY_MDM_ID=PARTIES.PARTY_MDM_ID
    AND PARTIES.DELETED_FLAG = 'N'
    WHERE PEOPLE.VALID_TO IS NULL and PEOPLE.DELETED_FLAG = 'N'; -- Only consider currently active records from PEOPLE

    	SET @source_count = @@ROWCOUNT;



	    -- 3. Insert New Records and New Versions of Updated Records
    -- This includes:
    --   a) Completely new records (not in DIM_PARTY_DETAILS at all).
    --   b) New versions of records that were just expired in step 2.
   
   
   INSERT INTO [gold].[DIM_PARTY_DETAIL] (
        [SK_PARTY_DETAIL],
        [PARTY_MDM_ID],	
        [PARTY_TYPE],
        [STATUS],
        [FIRST_NAMES],
        [LAST_NAMES],
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
        [DELETED_FLAG]
        ,[BATCH_ID] 

    ) 
	
    SELECT
        NEWID(),
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
        Source.START_DATE AS START_DATE, -- New record starts now
       NULL AS END_DATE,      -- Active until further update
       CONVERT(VARCHAR(64), Source.HASH_VALUE) AS HASH_VALUE,
       Source.DELETED_FLAG,             
        @batch_id 
    FROM
        #SourceStaging AS Source
    LEFT JOIN
        [gold].[DIM_PARTY_DETAIL] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT -- Collation fix
    WHERE
        Target.PARTY_MDM_ID IS NULL -- This condition identifies truly new records
;
    SET @insert_new = @@ROWCOUNT;
 
    ---------------------------------------------------------
    -- 3B. Insert UPDATED versions (START_DATE = SYSDATE)
    ---------------------------------------------------------
    
   INSERT INTO [gold].[DIM_PARTY_DETAIL] (
        [SK_PARTY_DETAIL],
        [PARTY_MDM_ID],	
        [PARTY_TYPE],
        [STATUS],
        [FIRST_NAMES],
        [LAST_NAMES],
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
        [DELETED_FLAG]
        ,[BATCH_ID] 

    ) 
	
    SELECT
	    DISTINCT
        NEWID(),
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
       NULL AS END_DATE,      -- Active until further update
       CONVERT(VARCHAR(64), Source.HASH_VALUE) AS HASH_VALUE,
        Source.DELETED_FLAG,               
        @batch_id 
    FROM
        #SourceStaging AS Source
    INNER JOIN
        [gold].[DIM_PARTY_DETAIL] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT -- Collation fix
    WHERE
    Target.HASH_VALUE <> Source.HASH_VALUE -- This condition identifies new records as part of updates records
    AND Target.END_DATE IS NULL
    AND Target.DELETED_FLAG = 'N'
;

SET @insert_changed = @insert_new + @@ROWCOUNT;


	    -- 2. Expire Old Records (SCD Type 2 Update)
    -- Identify active records in DIM_PARTY_DETAILS that have changed in the source
    -- and set their END_DATE to close them off.

    UPDATE Target
    SET
        Target.END_DATE = DATEADD(ms, -3, @CurrentTimestamp) -- End the old record just before the new one starts
    FROM
        gold.[DIM_PARTY_DETAIL] AS Target
    INNER JOIN
        #SourceStaging AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE
        Target.END_DATE IS NULL-- Only update currently active records
        AND Target.DELETED_FLAG = 'N'       -- Only update non-deleted records
        AND Target.HASH_VALUE <> Source.HASH_VALUE; -- Only update if attributes have changed
    SET @updated = @@ROWCOUNT
    --------------------------------------------------------------------
    --  Soft Delete Logic (based ONLY on most recent silver row)
    --------------------------------------------------------------------
---- This fetches only the impacted ids in the current batch
DROP TABLE IF EXISTS #ChangedKeys;
 
SELECT DISTINCT PARTY_MDM_ID
INTO #ChangedKeys
FROM [LHDEVGOLDSTAGING].[silver].[people]
WHERE BATCH_ID = @batch_id and DELETED_FLAG = 'Y';



    UPDATE T
    SET
        T.DELETED_FLAG = 'Y',
        T.END_DATE = DATEADD(ms, -3, @CurrentTimestamp)
    FROM gold.DIM_PARTY_DETAIL T
    INNER JOIN #ChangedKeys F
        ON T.PARTY_MDM_ID = F.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE T.END_DATE IS NULL
      AND T.DELETED_FLAG = 'N';
SET @updated = @updated +@@ROWCOUNT

 -- 4. Handle Deletions 

    ---------------------------------------------------------
    -- 1. Capture IDs to delete
    ---------------------------------------------------------

    DROP TABLE IF EXISTS #silverIDstoDelete;
 
    SELECT DISTINCT PARTY_MDM_ID
    INTO #silverIDstoDelete
    FROM [LHDEVGOLDSTAGING].[silver].[people]
    ;


    DROP TABLE IF EXISTS  #IDsToDelete;
    SELECT T.PARTY_MDM_ID AS ID
        INTO #IDsToDelete
    FROM gold.DIM_PARTY_DETAIL AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;

   
    ---------------------------------------------------------
    -- 2. Delete from target table
    ---------------------------------------------------------
    DELETE FROM gold.DIM_PARTY_DETAIL
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
        'silver.people' AS SOURCE_TABLE,
        'gold.DIM_PARTY_DETAIL' AS TARGET_TABLE,
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
        'silver.people' AS SOURCE_TABLE,
        'gold.DIM_PARTY_DETAIL' AS TARGET_TABLE,
        SYSUTCDATETIME()                         AS EVENT_DATE,
        COALESCE(@source_count,   0) AS SOURCE_RECORDS,
        COALESCE(@insert_changed,     0) AS INSERT_RECORDS,
        COALESCE(@updated, 0) AS UPDATE_RECORDS,
        COALESCE(@deleted,        0) AS DELETE_RECORDS;
    ---------------------------------------------------------
    -- 4. Cleanup
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #IDsToDelete;
 
    -- Clean up the temporary table
    DROP TABLE IF EXISTS #SourceStaging;

END;