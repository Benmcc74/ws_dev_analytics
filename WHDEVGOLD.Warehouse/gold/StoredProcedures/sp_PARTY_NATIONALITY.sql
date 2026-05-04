CREATE                       PROCEDURE [gold].[sp_PARTY_NATIONALITY]
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
    DROP TABLE IF EXISTS #SourceStaging_Nationality;
    SELECT DISTINCT
        PN.PARTY_MDM_ID AS PARTY_MDM_ID,
        PN.NATIONALITY_CODE AS NATIONALITY,
        PN.FIRST_DECLARED_NTNLTY_FLAG,
        CAST(PN.SOURCE_EDIT_DATE AS DATETIME2(3)) AS SOURCE_EDIT_DATE,
        @CurrentTimestamp AS START_DATE,
        PN.DELETED_FLAG AS DELETED_FLAG,
        PN.VALID_TO AS VALID_TO,
        @CurrentTimestamp AS LOAD_DATE,
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
            CONCAT_WS('|',
                PN.PARTY_MDM_ID,
                PN.NATIONALITY_CODE,
                PN.FIRST_DECLARED_NTNLTY_FLAG,
                FORMAT(PN.SOURCE_EDIT_DATE, 'yyyy-MM-dd HH:mm:ss.ffffff')
            )
        ), 2) AS HASH_VALUE
    INTO #SourceStaging_Nationality
    FROM [LHDEVGOLDSTAGING].[silver].[party_nationalities] AS PN
    WHERE PN.VALID_TO IS NULL
      AND PN.DELETED_FLAG = 'N'; -- Only consider currently active records from source
    SET @source_count = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 2. Expire Old Records (SCD Type 2 Update)
    ---------------------------------------------------------
    UPDATE Target
    SET Target.END_DATE =  @CurrentTimestamp -- End the old record just before the new one starts
    FROM [gold].[DIM_PARTY_NATIONALITY] AS Target
    INNER JOIN #SourceStaging_Nationality AS Source
        ON Target.PARTY_MDM_ID = Source.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE Target.END_DATE IS NULL      -- Only update currently active records
      AND Target.DELETED_FLAG = 'N'    -- Only update non-deleted records
      AND Target.HASH_VALUE <> Source.HASH_VALUE; -- Only update if attributes have changed
    SET @updated = @@ROWCOUNT;
    ---------------------------------------------------------
    -- Insert FIRST-TIME records & UPDATED Versions
    ---------------------------------------------------------
    INSERT INTO [gold].[DIM_PARTY_NATIONALITY]
    (
        SK_PARTY_NATIONALITY,
        PARTY_MDM_ID,
        NATIONALITY,
        FIRST_DECL_NTNLTY_FLAG,
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
        Source.NATIONALITY,
        Source.FIRST_DECLARED_NTNLTY_FLAG,
        Source.SOURCE_EDIT_DATE,
        Source.START_DATE,
        NULL AS END_DATE, -- Active until further update
        CONVERT(VARCHAR(64), Source.HASH_VALUE),
        Source.DELETED_FLAG,
        @batch_id,
        Source.LOAD_DATE
    FROM #SourceStaging_Nationality AS Source
    LEFT JOIN [gold].[DIM_PARTY_NATIONALITY] AS Target
        ON Source.PARTY_MDM_ID = Target.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
        AND Target.END_DATE IS NULL   -- only match active rows
    WHERE Target.PARTY_MDM_ID IS NULL;  
    SET @insert_new = @@ROWCOUNT;

    ---------------------------------------------------------
    -- 3. Soft Delete Logic (based ONLY on most recent silver row)
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #ChangedKeys;
    SELECT DISTINCT PARTY_MDM_ID
    INTO #ChangedKeys
    FROM [LHDEVGOLDSTAGING].[silver].[party_nationalities]
    WHERE BATCH_ID = @batch_id
      AND DELETED_FLAG = 'Y'; -- This fetches only the impacted ids in the current batch
    UPDATE T
    SET T.DELETED_FLAG = 'Y',
        T.END_DATE =  @CurrentTimestamp
    FROM gold.DIM_PARTY_NATIONALITY T
    INNER JOIN #ChangedKeys F
        ON T.PARTY_MDM_ID = F.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE T.END_DATE IS NULL
      AND T.DELETED_FLAG = 'N';
    SET @updated = @updated + @@ROWCOUNT;
    ---------------------------------------------------------
    -- 4. Handle Deletions
    ---------------------------------------------------------
    -- 1. Capture IDs to delete
    DROP TABLE IF EXISTS #silverIDstoDelete;
    SELECT DISTINCT PARTY_MDM_ID
    INTO #silverIDstoDelete
    FROM [LHDEVGOLDSTAGING].[silver].[party_nationalities];
    DROP TABLE IF EXISTS #IDsToDelete;
    SELECT T.PARTY_MDM_ID AS ID
    INTO #IDsToDelete
    FROM gold.DIM_PARTY_NATIONALITY AS T
    LEFT JOIN #silverIDstoDelete AS S
        ON T.PARTY_MDM_ID = S.PARTY_MDM_ID COLLATE DATABASE_DEFAULT
    WHERE S.PARTY_MDM_ID IS NULL;
    -- 2. Delete from target table
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
        'PARTY_MDM_ID',
        ID,
        'DELETE',
        'silver.party_nationalities',
        'gold.DIM_PARTY_NATIONALITY',
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
        'silver.party_nationalities',
        'gold.DIM_PARTY_NATIONALITY',
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
    DROP TABLE IF EXISTS #SourceStaging_Nationality;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
 
        DROP TABLE IF EXISTS #IDsToDelete;
        DROP TABLE IF EXISTS #ChangedKeys;
        DROP TABLE IF EXISTS #silverIDstoDelete;
        DROP TABLE IF EXISTS #SourceStaging_Nationality;
 
        THROW;
    END CATCH
END;