CREATE                         PROCEDURE [gold].[sp_DIM_PARTY_CONTACT]
(
    @batch_id NVARCHAR(100)
)
AS
BEGIN
 
    BEGIN TRY
        BEGIN TRANSACTION;
 
      DECLARE @CurrentTimestamp DATETIME2(3) = GETDATE();
    DECLARE @insert_new       INT = 0;
    DECLARE @insert_changed   INT = 0;
    DECLARE @updated          INT = 0;
    DECLARE @deleted          INT = 0;
    DECLARE @source_count     INT = 0;
    ---------------------------------------------------------
    -- 1. Prepare Source Data with HASH_VALUE in a temporary table
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #SourceStaging;
    SELECT DISTINCT
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
        PA.VALID_TO AS VALID_TO,
        PA.DELETED_FLAG,
        CAST(PN_WORK.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE_WORK_PHONE,
        CAST(PN_MOBILE.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE_MOBILE_PHONE,
        CAST(PN_HOME.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE_HOME_PHONE,
        CAST(EA.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE_EMAIL,
        CAST(PA.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE_ADDRESS,
        @CurrentTimestamp AS START_DATE,
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
                ISNULL(PN_WORK.PHONE_NUMBER, ''),
                ISNULL(FORMAT(PN_WORK.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff'), ''),
                ISNULL(FORMAT(PN_MOBILE.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff'), ''),
                ISNULL(FORMAT(PN_HOME.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff'), ''),
                ISNULL(FORMAT(EA.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff'), ''),
                ISNULL(FORMAT(PA.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff'), '')
            )
        ), 2) AS HASH_VALUE,
         @CurrentTimestamp AS LOAD_DATE
    INTO #SourceStaging
    FROM [LHDEVGOLDSTAGING].[silver].[postal_addresses] AS PA
    LEFT JOIN [LHDEVGOLDSTAGING].[silver].[email_addresses] AS EA
        ON PA.PARTY_MDM_ID = EA.PARTY_MDM_ID
       AND EA.VALID_TO IS NULL AND EA.DELETED_FLAG = 'N'
    LEFT JOIN [LHDEVGOLDSTAGING].[silver].[phone_numbers] AS PN_HOME
        ON PA.PARTY_MDM_ID = PN_HOME.PARTY_MDM_ID
       AND PN_HOME.PHONE_TYPE_CODE = 'HOME'
       AND PN_HOME.VALID_TO IS NULL AND PN_HOME.DELETED_FLAG = 'N'
    LEFT JOIN [LHDEVGOLDSTAGING].[silver].[phone_numbers] AS PN_MOBILE
        ON PA.PARTY_MDM_ID = PN_MOBILE.PARTY_MDM_ID
       AND PN_MOBILE.PHONE_TYPE_CODE = 'MOBILE'
       AND PN_MOBILE.VALID_TO IS NULL AND PN_MOBILE.DELETED_FLAG = 'N'
    LEFT JOIN [LHDEVGOLDSTAGING].[silver].[phone_numbers] AS PN_WORK
        ON PA.PARTY_MDM_ID = PN_WORK.PARTY_MDM_ID
       AND PN_WORK.PHONE_TYPE_CODE = 'WORK'
       AND PN_WORK.VALID_TO IS NULL AND PN_WORK.DELETED_FLAG = 'N'
    WHERE PA.VALID_TO IS NULL
      AND PA.DELETED_FLAG = 'N';
    SET @source_count = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 2. Expire Old Records (SCD Type 2 Update)
    ---------------------------------------------------------
    UPDATE Target
    SET Target.END_DATE =  @CurrentTimestamp
    FROM [gold].[DIM_PARTY_CONTACT] AS Target
    INNER JOIN #SourceStaging AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE Target.END_DATE IS NULL
      AND Target.DELETED_FLAG = 'N'
      AND Target.HASH_VALUE <> Source.HASH_VALUE;
    SET @updated = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 3. Insert FIRST-TIME records
    ---------------------------------------------------------
    INSERT INTO [gold].[DIM_PARTY_CONTACT]
    (
        SK_PARTY_CONTACT,
        PARTY_MDM_ID,
        LINE_1,
        LINE_2,
        LINE_3,
        LINE_4,
        LINE_5,
        POSTCODE,
        ADDRESS_TYPE,
        COUNTRY,
        EMAIL,
        HOME_PHONE,
        MOBILE_PHONE,
        WORK_PHONE,
        PREF_COMM_METHOD,
        SOURCE_EDIT_DATE_WORK_PHONE,
        SOURCE_EDIT_DATE_MOBILE_PHONE,
        SOURCE_EDIT_DATE_HOME_PHONE,
        SOURCE_EDIT_DATE_EMAIL,
        SOURCE_EDIT_DATE_ADDRESS,
        START_DATE,
        END_DATE,
        HASH_VALUE,
        DELETED_FLAG,
        BATCH_ID,
        LOAD_DATE
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
        Source.SOURCE_EDIT_DATE_WORK_PHONE,
        Source.SOURCE_EDIT_DATE_MOBILE_PHONE,
        Source.SOURCE_EDIT_DATE_HOME_PHONE,
        Source.SOURCE_EDIT_DATE_EMAIL,
        Source.SOURCE_EDIT_DATE_ADDRESS,
        Source.START_DATE,
        NULL AS END_DATE, -- Active
        CONVERT(VARCHAR(64), Source.HASH_VALUE),
        Source.DELETED_FLAG,
        @batch_id,
        Source.LOAD_DATE
    FROM #SourceStaging AS Source
    LEFT JOIN [gold].[DIM_PARTY_CONTACT] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
        AND Target.END_DATE IS NULL   -- only match active rows
    WHERE Target.PARTY_MDM_ID IS NULL;  
    SET @insert_new = @@ROWCOUNT;

 
    ---------------------------------------------------------
    -- 4. Soft Delete Logic (based ONLY on most recent silver row)
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #ChangedKeys;
    SELECT DISTINCT PARTY_MDM_ID
    INTO #ChangedKeys
    FROM [LHDEVGOLDSTAGING].[silver].[postal_addresses]
    WHERE BATCH_ID = @batch_id
      AND DELETED_FLAG = 'Y';
    UPDATE T
    SET T.DELETED_FLAG = 'Y',
        T.END_DATE =  @CurrentTimestamp
    FROM gold.DIM_PARTY_CONTACT T
    INNER JOIN #ChangedKeys F
        ON T.PARTY_MDM_ID = F.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE T.END_DATE IS NULL
      AND T.DELETED_FLAG = 'N';
    SET @updated = @updated + @@ROWCOUNT;
    ---------------------------------------------------------
    -- 5. Handle Hard Deletions
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #silverIDstoDelete;
    SELECT DISTINCT PARTY_MDM_ID
    INTO #silverIDstoDelete
    FROM [LHDEVGOLDSTAGING].[silver].[people];
    DROP TABLE IF EXISTS #IDsToDelete;
    SELECT T.PARTY_MDM_ID AS ID
    INTO #IDsToDelete
    FROM gold.DIM_PARTY_CONTACT AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;
    SET @deleted = @@ROWCOUNT;
    DELETE FROM gold.DIM_PARTY_CONTACT
    WHERE PARTY_MDM_ID IN (SELECT ID FROM #IDsToDelete);
    ---------------------------------------------------------
    -- 6. Insert audit log
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
        'PARTY_MDM_ID',
        ID,
        'DELETE',
        'silver.postal_addresses',
        'gold.DIM_PARTY_CONTACT',
        CURRENT_TIMESTAMP,
        @batch_id
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
        @batch_id,
        'silver.postal_addresses',
        'gold.DIM_PARTY_CONTACT',
        SYSUTCDATETIME(),
        COALESCE(@source_count, 0),
        COALESCE(@insert_new, 0),
        COALESCE(@updated, 0),
        COALESCE(@deleted, 0);
    ---------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #IDsToDelete;
    DROP TABLE IF EXISTS #SourceStaging;
    DROP TABLE IF EXISTS #silverIDstoDelete;
    DROP TABLE IF EXISTS #ChangedKeys;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #IDsToDelete;
        DROP TABLE IF EXISTS #SourceStaging;
        DROP TABLE IF EXISTS #silverIDstoDelete;
        DROP TABLE IF EXISTS #ChangedKeys;
 

 
        THROW;
    END CATCH
END;