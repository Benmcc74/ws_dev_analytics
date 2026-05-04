CREATE                         PROCEDURE [gold].[sp_PARTY_DETAIL]
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
    DECLARE @deleted          INT = 0;
    DECLARE @source_count     INT = 0;
    DECLARE @updated          INT = 0;
    ---------------------------------------------------------
    -- 1. Prepare Source Data with HASH_VALUE in a temporary table
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #SourceStaging;
    SELECT DISTINCT
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
        CAST(PEOPLE.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE,
        @CurrentTimestamp AS START_DATE,
        PEOPLE.DELETED_FLAG AS DELETED_FLAG,
        PEOPLE.VALID_TO AS VALID_TO,
        @CurrentTimestamp AS LOAD_DATE,
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
                FORMAT(PEOPLE.DECEASED_EVIDENCE_DATE, 'yyyy-MM-dd'),
                FORMAT(PEOPLE.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff')
            )
        ), 2) AS HASH_VALUE
    INTO #SourceStaging
    FROM [LHDEVGOLDSTAGING].[silver].[people] AS PEOPLE
    LEFT JOIN [LHDEVGOLDSTAGING].[silver].[parties] AS PARTIES
        ON PEOPLE.PARTY_MDM_ID = PARTIES.PARTY_MDM_ID
       AND PARTIES.DELETED_FLAG = 'N'
    WHERE PEOPLE.VALID_TO IS NULL
      AND PEOPLE.DELETED_FLAG = 'N'; -- Only consider currently active records from PEOPLE
    SET @source_count = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 2. Expire Old Records (SCD Type 2 Update)
    ---------------------------------------------------------
    UPDATE Target
    SET Target.END_DATE =  @CurrentTimestamp -- End the old record just before the new one starts
    FROM gold.[DIM_PARTY_DETAIL] AS Target
    INNER JOIN #SourceStaging AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE Target.END_DATE IS NULL
      AND Target.DELETED_FLAG = 'N'
      AND Target.HASH_VALUE <> Source.HASH_VALUE;
    SET @updated = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 3. Insert New Records and New Versions of Updated Records
    ---------------------------------------------------------
    INSERT INTO [gold].[DIM_PARTY_DETAIL]
    (
        SK_PARTY_DETAIL,
        PARTY_MDM_ID,
        PARTY_TYPE,
        STATUS,
        FIRST_NAMES,
        LAST_NAMES,
        TITLE,
        SUFFIX,
        GENDER,
        DOB,
        MARITAL_STATUS,
        NI_NUMBER,
        TAX_ID_NUMBER,
        TAX_DOMICILE,
        FATCA_ELIGIBLE,
        RELATIONSHIP_START_DATE,
        RELATIONSHIP_END_DATE,
        RETENTION_END_DATE,
        DECEASED_DATE,
        DECEASED_NOTIFICATION_DATE,
        DECEASED_EVIDENCE_DATE,
        SOURCE_EDIT_DATE,
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
        Source.SOURCE_EDIT_DATE,
        Source.START_DATE,
        NULL AS END_DATE, -- Active until further update
        CONVERT(VARCHAR(64), Source.HASH_VALUE),
        Source.DELETED_FLAG,
        @batch_id,
        Source.LOAD_DATE
    FROM #SourceStaging AS Source
    LEFT JOIN gold.[DIM_PARTY_DETAIL] AS Target
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
    FROM [LHDEVGOLDSTAGING].[silver].[people]
    WHERE BATCH_ID = @batch_id
      AND DELETED_FLAG = 'Y'; -- This fetches only the impacted ids in the current batch
    UPDATE T
    SET T.DELETED_FLAG = 'Y',
        T.END_DATE =  @CurrentTimestamp
    FROM gold.DIM_PARTY_DETAIL T
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
    FROM gold.DIM_PARTY_DETAIL AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;
    DELETE FROM gold.DIM_PARTY_DETAIL
    WHERE PARTY_MDM_ID IN (SELECT ID FROM #IDsToDelete);
    SET @deleted = @@ROWCOUNT;
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
        'silver.people',
        'gold.DIM_PARTY_DETAIL',
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
        'silver.people',
        'gold.DIM_PARTY_DETAIL',
        SYSUTCDATETIME(),
        COALESCE(@source_count, 0),
        COALESCE(@insert_new, 0),
        COALESCE(@updated, 0),
        COALESCE(@deleted, 0);
    ---------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------

	DROP TABLE IF EXISTS #IDsToDelete;
    DROP TABLE IF EXISTS #silverIDstoDelete;
    DROP TABLE IF EXISTS #ChangedKeys;
    DROP TABLE IF EXISTS #SourceStaging;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        DROP TABLE IF EXISTS #IDsToDelete;
        DROP TABLE IF EXISTS #silverIDstoDelete;
        DROP TABLE IF EXISTS #ChangedKeys;
        DROP TABLE IF EXISTS #SourceStaging;
 

 
        THROW;
    END CATCH
END;