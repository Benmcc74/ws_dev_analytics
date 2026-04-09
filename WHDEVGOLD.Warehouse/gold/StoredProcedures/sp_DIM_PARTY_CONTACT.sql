CREATE                                                     PROCEDURE [gold].[sp_DIM_PARTY_CONTACT]
(
   @batch_id NVARCHAR(100)
)
AS


BEGIN

    DECLARE @CurrentTimestamp DATETIME = GETDATE();

    DECLARE @insert_new    int = 0;
    DECLARE @insert_changed int = 0;
    DECLARE @updated int = 0;
    DECLARE @deleted int = 0;
    DECLARE @source_count int = 0;

    DROP TABLE IF EXISTS #SourceStaging; 

    SELECT
        PA.PARTY_MDM_ID AS PARTY_MDM_ID,
        PA.LINE_1,
        PA.LINE_2,
        PA.LINE_3,
        PA.LINE_4,
        PA.LINE_5,
        PA.POSTCODE,
        PA.ADDRESS_TYPE_CODE AS ADDRESS_TYPE,
        PA.COUNTRY_CODE AS COUNTRY,
        EA.EMAIL,
        PN_HOME.PHONE_NUMBER AS HOME_PHONE,
        PN_MOBILE.PHONE_NUMBER AS MOBILE_PHONE,
        PN_WORK.PHONE_NUMBER AS WORK_PHONE,
        NULL AS PREF_COMM_METHOD,
        PA.VALID_TO AS  VALID_TO,
        PA.DELETED_FLAG,
		(
        SELECT MAX(VALID_FROM)
        FROM (
        SELECT PA.VALID_FROM
        UNION ALL SELECT EA.VALID_FROM
        UNION ALL SELECT PN_HOME.VALID_FROM
        UNION ALL SELECT PN_MOBILE.VALID_FROM
        UNION ALL SELECT PN_WORK.VALID_FROM
          ) AS x
         ) AS START_DATE,
       	CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
        CONCAT_WS('|',
        PA.PARTY_MDM_ID,
         ISNULL(PA.LINE_1, ''),
        ISNULL(PA.LINE_2, ''),
        ISNULL(PA.LINE_3, ''),
        ISNULL(PA.LINE_4, ''),
        ISNULL(PA.LINE_5, ''),
        ISNULL(PA.POSTCODE, ''),
        ISNULL(PA.ADDRESS_TYPE_CODE, ''),
        ISNULL(PA.COUNTRY_CODE, ''),
        ISNULL(EA.EMAIL, ''),
        ISNULL(PN_HOME.PHONE_NUMBER, ''),
        ISNULL(PN_MOBILE.PHONE_NUMBER, ''),
        ISNULL(PN_WORK.PHONE_NUMBER, '')
                  )), 2) AS HASH_VALUE
    INTO #SourceStaging
    FROM
        [LHDEVGOLDSTAGING].[silver].[postal_addresses] AS PA
    LEFT JOIN
        [LHDEVGOLDSTAGING].[silver].[email_addresses] AS EA
        ON PA.PARTY_MDM_ID = EA.PARTY_MDM_ID
        AND EA.VALID_TO IS NULL AND EA.DELETED_FLAG = 'N'
    LEFT JOIN
        [LHDEVGOLDSTAGING].[silver].[phone_numbers] AS PN_HOME
        ON PA.PARTY_MDM_ID = PN_HOME.PARTY_MDM_ID
        AND PN_HOME.PHONE_TYPE_CODE = 'HOME'
        AND PN_HOME.VALID_TO IS NULL AND PN_HOME.DELETED_FLAG = 'N'
    LEFT JOIN
        [LHDEVGOLDSTAGING].[silver].[phone_numbers] AS PN_MOBILE
        ON PA.PARTY_MDM_ID = PN_MOBILE.PARTY_MDM_ID
        AND PN_MOBILE.PHONE_TYPE_CODE = 'MOBILE'
        AND PN_MOBILE.VALID_TO IS NULL AND PN_MOBILE.DELETED_FLAG = 'N'
    LEFT JOIN
        [LHDEVGOLDSTAGING].[silver].[phone_numbers] AS PN_WORK
        ON PA.PARTY_MDM_ID = PN_WORK.PARTY_MDM_ID
        AND PN_WORK.PHONE_TYPE_CODE = 'WORK'
        AND PN_WORK.VALID_TO IS NULL AND PN_WORK.DELETED_FLAG = 'N'
    WHERE PA.VALID_TO IS NULL AND PA.DELETED_FLAG = 'N'; 

    SET @source_count = @@ROWCOUNT;

    ---------------------------------------------------------
    -- Insert FIRST‑TIME records (START_DATE = source VALID_FROM)
    ---------------------------------------------------------

    INSERT INTO [gold].[DIM_PARTY_CONTACT] (
        SK_PARTY_CONTACT,
        [PARTY_MDM_ID],
        [LINE_1],
        [LINE_2],
        [LINE_3],
        [LINE_4],
        [LINE_5],
        [POSTCODE],
        [ADDRESS_TYPE],
        [COUNTRY],
        [EMAIL],
        [HOME_PHONE],
        [MOBILE_PHONE],
        [WORK_PHONE],
        [PREF_COMM_METHOD],
        [START_DATE],
        [END_DATE],
        [HASH_VALUE],
        [DELETED_FLAG],
        [BATCH_ID]
    )

    SELECT DISTINCT
    NEWID(),
        Source.PARTY_MDM_ID,
        Source.LINE_1,
        Source.LINE_2,
        Source.LINE_3,
        Source.LINE_4,
        Source.LINE_5,
        Source.POSTCODE,
        Source.ADDRESS_TYPE,
        Source.COUNTRY,
        Source.EMAIL,
        Source.HOME_PHONE,
        Source.MOBILE_PHONE,
        Source.WORK_PHONE,
        Source.PREF_COMM_METHOD,
        Source.START_DATE AS START_DATE, -- New record -- First time insert only
        NULL AS END_DATE,      -- Active
        CONVERT(VARCHAR(64), source.HASH_VALUE) AS HASH_VALUE,
        Source.DELETED_FLAG AS DELETED_FLAG,              
        @batch_id
    FROM
        #SourceStaging AS Source
    LEFT JOIN
        [gold].[DIM_PARTY_CONTACT] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT -- Collation fix
    WHERE
        Target.PARTY_MDM_ID IS NULL -- This condition identifies truly new records (First time insert only)
;
    SET @insert_new = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 3B. Insert UPDATED versions (START_DATE = SYSDATE)
    ---------------------------------------------------------
    INSERT INTO [gold].[DIM_PARTY_CONTACT] (
        SK_PARTY_CONTACT,
        [PARTY_MDM_ID],
        [LINE_1],
        [LINE_2],
        [LINE_3],
        [LINE_4],
        [LINE_5],
        [POSTCODE],
        [ADDRESS_TYPE],
        [COUNTRY],
        [EMAIL],
        [HOME_PHONE],
        [MOBILE_PHONE],
        [WORK_PHONE],
        [PREF_COMM_METHOD],
        [START_DATE],
        [END_DATE],
        [HASH_VALUE],
        [DELETED_FLAG],
        [BATCH_ID]
    )

    SELECT DISTINCT
    NEWID(),
        Source.PARTY_MDM_ID,
        Source.LINE_1,
        Source.LINE_2,
        Source.LINE_3,
        Source.LINE_4,
        Source.LINE_5,
        Source.POSTCODE,
        Source.ADDRESS_TYPE,
        Source.COUNTRY,
        Source.EMAIL,
        Source.HOME_PHONE,
        Source.MOBILE_PHONE,
        Source.WORK_PHONE,
        Source.PREF_COMM_METHOD,
        @CurrentTimestamp AS START_DATE,   -- CHANGE → SYSDATE
        NULL AS END_DATE,      -- Active
        CONVERT(VARCHAR(64), source.HASH_VALUE) AS HASH_VALUE,
        Source.DELETED_FLAG AS DELETED_FLAG,              
        @batch_id
    FROM
        #SourceStaging AS Source
    INNER JOIN
        [gold].[DIM_PARTY_CONTACT] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT -- Collation fix
    WHERE
                Target.HASH_VALUE <> Source.HASH_VALUE -- This condition identifies new records as part of updates records
                AND Target.END_DATE IS NULL
    AND Target.DELETED_FLAG = 'N'
;

      SET @insert_changed = @insert_new + @@ROWCOUNT;  

    --- End the old record 
    UPDATE Target
    SET
        Target.END_DATE = DATEADD(ms, -3, @CurrentTimestamp)
    FROM
        [gold].[DIM_PARTY_CONTACT] AS Target
    INNER JOIN
        #SourceStaging AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE
        Target.END_DATE IS NULL -- Only update currently active records
        AND Target.DELETED_FLAG = 'N'     -- Only update non-deleted records
        AND Target.HASH_VALUE <> Source.HASH_VALUE; -- Only update if attributes have changed
 
SET @updated = @@ROWCOUNT
    --------------------------------------------------------------------
    --  Soft Delete Logic (based ONLY on most recent silver row)
    --------------------------------------------------------------------
---- This fetches only the impacted ids in the current batch
DROP TABLE IF EXISTS #ChangedKeys;
 
SELECT DISTINCT PARTY_MDM_ID
INTO #ChangedKeys
FROM [LHDEVGOLDSTAGING].[silver].[postal_addresses]
WHERE BATCH_ID = @batch_id and DELETED_FLAG = 'Y';

    UPDATE T
    SET
        T.DELETED_FLAG = 'Y',
        T.END_DATE = DATEADD(ms, -3, @CurrentTimestamp)
    FROM gold.DIM_PARTY_CONTACT T
    INNER JOIN #ChangedKeys F
        ON T.PARTY_MDM_ID = F.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE T.END_DATE IS NULL
      AND T.DELETED_FLAG = 'N' -- Flag should be N;

;
SET @updated = @updated + @@ROWCOUNT
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
    FROM gold.DIM_PARTY_CONTACT AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;

SET @deleted = @@ROWCOUNT;

    ---------------------------------------------------------
    -- 2. Delete from target table
    ---------------------------------------------------------
    DELETE FROM gold.DIM_PARTY_CONTACT
    WHERE PARTY_MDM_ID IN (SELECT ID FROM #IDsToDelete);


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
        'silver.postal_addresses' AS SOURCE_TABLE,
        'gold.DIM_PARTY_CONTACT' AS TARGET_TABLE,
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
        'silver.postal_addresses' AS SOURCE_TABLE,
        'gold.DIM_PARTY_CONTACT' AS TARGET_TABLE,
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