CREATE                     PROCEDURE [gold].[sp_PARTY_FLAG]
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
    DROP TABLE IF EXISTS #SourceStaging_PartyFlag;
    SELECT DISTINCT
        P.PARTY_MDM_ID AS PARTY_MDM_ID,
        NULL AS IS_ASSUMED_VC_FLAG,
        P.DORMANT_FLAG AS IS_DORMANT_FLAG,
        CASE WHEN P.DECEASED_DATE IS NOT NULL THEN 'Y' ELSE 'N' END AS IS_DECEASED_FLAG,
        P.MCNR_DEBT_FLAG AS MCNR_DEBT_FLAG,
        P.OPEN_COMPLAINT_FLAG AS OPEN_COMPLAINT_FLAG,
        P.OPEN_LITIGATION_FLAG,
        NULL AS YBS_WEB_ENABLED_FLAG,
        NULL AS AML_WEB_ENABLED_FLAG,
        NULL AS CBS_WEB_ENABLED_FLAG,
        CAST(P.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE,
        @CurrentTimestamp AS START_DATE,
        P.VALID_TO AS VALID_TO,
        P.DELETED_FLAG AS DELETED_FLAG,
        @CurrentTimestamp AS LOAD_DATE,
        -- Calculate HASH_VALUE for change detection.
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
            CONCAT_WS('|',
                P.PARTY_MDM_ID,
                ISNULL(P.ASSUMED_VC, ''),
                ISNULL(P.DORMANT_FLAG, ''),
                CASE WHEN P.DECEASED_DATE IS NOT NULL THEN 'Y' ELSE 'N' END,
                ISNULL(P.MCNR_DEBT_FLAG, ''),
                ISNULL(P.OPEN_COMPLAINT_FLAG, ''),
                ISNULL(P.OPEN_LITIGATION_FLAG, ''),
                FORMAT(P.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff')
            )
        ), 2) AS HASH_VALUE
    INTO #SourceStaging_PartyFlag
    FROM [LHDEVGOLDSTAGING].[silver].[people] AS P
    WHERE P.VALID_TO IS NULL
      AND P.DELETED_FLAG = 'N'; -- Only consider currently active records from PEOPLE
    SET @source_count = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 2. Expire Old Records (SCD Type 2 Update)
    ---------------------------------------------------------
    UPDATE Target
    SET Target.END_DATE =  @CurrentTimestamp -- End the old record just before the new one starts
    FROM [gold].[DIM_PARTY_FLAG] AS Target
    INNER JOIN #SourceStaging_PartyFlag AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE Target.END_DATE IS NULL
      AND Target.DELETED_FLAG = 'N'
      AND Target.HASH_VALUE <> Source.HASH_VALUE;
    SET @updated = @@ROWCOUNT;
    ---------------------------------------------------------
    -- Insert FIRST-TIME records (START_DATE = source VALID_FROM)
    ---------------------------------------------------------
    INSERT INTO [gold].[DIM_PARTY_FLAG]
    (
        SK_PARTY_FLAG,
        PARTY_MDM_ID,
        IS_ASSUMED_VC_FLAG,
        IS_DORMANT_FLAG,
        IS_DECEASED_FLAG,
        MCNR_DEBT_FLAG,
        OPEN_COMPLAINT_FLAG,
        OPEN_LITIGATION_FLAG,
        YBS_WEB_ENABLED_FLAG,
        AML_WEB_ENABLED_FLAG,
        CBS_WEB_ENABLED_FLAG,
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
        Source.IS_ASSUMED_VC_FLAG,
        Source.IS_DORMANT_FLAG,
        Source.IS_DECEASED_FLAG,
        Source.MCNR_DEBT_FLAG,
        Source.OPEN_COMPLAINT_FLAG,
        Source.OPEN_LITIGATION_FLAG,
        Source.YBS_WEB_ENABLED_FLAG,
        Source.AML_WEB_ENABLED_FLAG,
        Source.CBS_WEB_ENABLED_FLAG,
        Source.SOURCE_EDIT_DATE,
        Source.START_DATE,
        NULL AS END_DATE, -- Active until further notice
        CONVERT(VARCHAR(64), Source.HASH_VALUE) AS HASH_VALUE,
        Source.DELETED_FLAG,
        @batch_id,
        Source.LOAD_DATE
    FROM #SourceStaging_PartyFlag AS Source
    LEFT JOIN [gold].[DIM_PARTY_FLAG] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
        AND Target.END_DATE IS NULL   -- only match active rows
    WHERE Target.PARTY_MDM_ID IS NULL;  
    SET @insert_new = @@ROWCOUNT;

    ---------------------------------------------------------
    -- Soft Delete Logic (based ONLY on most recent silver row)
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
    FROM gold.DIM_PARTY_FLAG T
    INNER JOIN #ChangedKeys F
        ON T.PARTY_MDM_ID = F.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE T.END_DATE IS NULL
      AND T.DELETED_FLAG = 'N'; -- Flag should be N
    SET @updated = @updated + @@ROWCOUNT;
    ---------------------------------------------------------
    -- Handle Hard Deletions
    ---------------------------------------------------------
    -- 1. Capture IDs to delete
    DROP TABLE IF EXISTS #silverIDstoDelete;
    SELECT DISTINCT PARTY_MDM_ID
    INTO #silverIDstoDelete
    FROM [LHDEVGOLDSTAGING].[silver].[people];
    DROP TABLE IF EXISTS #IDsToDelete;
    SELECT T.PARTY_MDM_ID AS ID
    INTO #IDsToDelete
    FROM gold.DIM_PARTY_FLAG AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;
    -- 2. Delete from target table
    DELETE FROM gold.DIM_PARTY_FLAG
    WHERE PARTY_MDM_ID IN (SELECT ID FROM #IDsToDelete);
    SET @deleted = @@ROWCOUNT;
    -- 3. Insert audit log
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
        'gold.DIM_PARTY_FLAG',
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
        'gold.DIM_PARTY_FLAG',
        SYSUTCDATETIME(),
        COALESCE(@source_count, 0),
        COALESCE(@insert_new, 0),
        COALESCE(@updated, 0),
        COALESCE(@deleted, 0);
    ---------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #IDsToDelete;
    DROP TABLE IF EXISTS #ChangedKeys;
    DROP TABLE IF EXISTS #silverIDstoDelete;
    DROP TABLE IF EXISTS #SourceStaging_PartyFlag;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
 
        DROP TABLE IF EXISTS #IDsToDelete;
        DROP TABLE IF EXISTS #ChangedKeys;
        DROP TABLE IF EXISTS #silverIDstoDelete;
        DROP TABLE IF EXISTS #SourceStaging_PartyFlag;
 
        THROW;
    END CATCH
END;