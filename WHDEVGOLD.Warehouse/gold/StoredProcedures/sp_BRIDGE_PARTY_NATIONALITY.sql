CREATE                           PROCEDURE gold.sp_BRIDGE_PARTY_NATIONALITY
(
    @batch_id NVARCHAR(100)
)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
 
    DECLARE @CurrentTimestamp DATETIME2(3) = GETDATE();
    DECLARE @insert_new     INT = 0;
    DECLARE @insert_changed INT = 0;
    DECLARE @scd2_exp       INT = 0;
    DECLARE @updated        INT = 0;
    DECLARE @deleted        INT = 0;
    DECLARE @source_count   INT = 0;
    DECLARE @sft_dlt        INT = 0;
    /*========================================================
      1. Prepare source snapshot
    ========================================================*/
    DROP TABLE IF EXISTS #SRC_BRIDGE_PARTY_NATIONALITY;
    SELECT DISTINCT
        DPN.PARTY_MDM_ID,
        -- FK lookups
        DPN.SK_PARTY_NATIONALITY,
        DPD.SK_PARTY_DETAIL,
        -- Dates
        @CurrentTimestamp AS START_DATE,
        NULL AS END_DATE,
        -- Hash for change detection
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
            CONCAT_WS('|',
                DPN.SK_PARTY_NATIONALITY,
                DPD.SK_PARTY_DETAIL
            )
        ), 2) AS HASH_VALUE,
        @CurrentTimestamp AS LOAD_DATE
    INTO #SRC_BRIDGE_PARTY_NATIONALITY
    FROM gold.DIM_PARTY_DETAIL DPD
    INNER JOIN gold.DIM_PARTY_NATIONALITY DPN
        ON DPN.PARTY_MDM_ID = DPD.PARTY_MDM_ID
        AND DPN.END_DATE IS NULL
        AND DPN.DELETED_FLAG = 'N'
    WHERE DPD.END_DATE IS NULL
      AND DPD.DELETED_FLAG = 'N';

    SET @source_count = @@ROWCOUNT;
    /*========================================================
      2. Expire changed BRIDGE_PARTY_NATIONALITY records (SCD2)
    ========================================================*/
    UPDATE TGT
    SET TGT.END_DATE = @CurrentTimestamp
    FROM gold.BRIDGE_PARTY_NATIONALITY TGT
    LEFT JOIN #SRC_BRIDGE_PARTY_NATIONALITY SRC
        ON TGT.SK_PARTY_NATIONALITY = SRC.SK_PARTY_NATIONALITY
       AND TGT.SK_PARTY_DETAIL     = SRC.SK_PARTY_DETAIL
    WHERE TGT.END_DATE IS NULL
      AND TGT.DELETED_FLAG = 'N'
      AND SRC.SK_PARTY_NATIONALITY IS NULL;
    SET @scd2_exp = @@ROWCOUNT;
    /*========================================================
      3. Insert new records
    ========================================================*/
    INSERT INTO gold.BRIDGE_PARTY_NATIONALITY
    (
        SK_BRIDGE_PARTY_NATIONALITY,
        SK_PARTY_NATIONALITY,
        SK_PARTY_DETAIL,
        START_DATE,
        END_DATE,
        HASH_VALUE,
        DELETED_FLAG,
        BATCH_ID,
        LOAD_DATE
    )
    SELECT DISTINCT
        NEWID(),
        SRC.SK_PARTY_NATIONALITY,
        SRC.SK_PARTY_DETAIL,
        SRC.START_DATE,
        NULL AS END_DATE,
        SRC.HASH_VALUE,
        'N' AS DELETED_FLAG,
        @batch_id,
        SRC.LOAD_DATE
    FROM #SRC_BRIDGE_PARTY_NATIONALITY SRC
    LEFT JOIN gold.BRIDGE_PARTY_NATIONALITY TGT
        ON TGT.SK_PARTY_NATIONALITY = SRC.SK_PARTY_NATIONALITY
       AND TGT.SK_PARTY_DETAIL     = SRC.SK_PARTY_DETAIL
       AND TGT.END_DATE IS NULL
       AND TGT.DELETED_FLAG = 'N'
    WHERE TGT.SK_BRIDGE_PARTY_NATIONALITY IS NULL;
    SET @insert_new = @@ROWCOUNT;
  
    ---------------------------------------------------------
    -- Soft Delete
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #DeletedKeys_nationality;
    SELECT SK_PARTY_NATIONALITY
    INTO #DeletedKeys_nationality
    FROM gold.DIM_PARTY_NATIONALITY
    WHERE DELETED_FLAG = 'Y';
    DROP TABLE IF EXISTS #DeletedKeys_Detail;
    SELECT SK_PARTY_DETAIL
    INTO #DeletedKeys_Detail
    FROM gold.DIM_PARTY_DETAIL
    WHERE DELETED_FLAG = 'Y';
    UPDATE T
    SET
        T.DELETED_FLAG = 'Y',
        T.END_DATE = @CurrentTimestamp
    FROM gold.BRIDGE_PARTY_NATIONALITY T
    LEFT JOIN #DeletedKeys_nationality C
        ON T.SK_PARTY_NATIONALITY = C.SK_PARTY_NATIONALITY
    LEFT JOIN #DeletedKeys_Detail N
        ON T.SK_PARTY_DETAIL = N.SK_PARTY_DETAIL
    WHERE T.DELETED_FLAG = 'N'
      AND (C.SK_PARTY_NATIONALITY IS NOT NULL OR N.SK_PARTY_DETAIL IS NOT NULL);
    SET @sft_dlt = @@ROWCOUNT;
    SET @updated = @scd2_exp + @sft_dlt;
    ---------------------------------------------------------
    -- Hard Delete
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #goldnationalityIDstoDelete;
    DROP TABLE IF EXISTS #golddetailIDstoDelete;
    SELECT DISTINCT SK_PARTY_NATIONALITY
    INTO #goldnationalityIDstoDelete
    FROM gold.DIM_PARTY_NATIONALITY;
    SELECT DISTINCT SK_PARTY_DETAIL
    INTO #golddetailIDstoDelete
    FROM gold.DIM_PARTY_DETAIL;
    DROP TABLE IF EXISTS #IDsToDelete;
    SELECT
        T.SK_BRIDGE_PARTY_NATIONALITY AS ID,
        T.SK_PARTY_NATIONALITY,
        T.SK_PARTY_DETAIL
    INTO #IDsToDelete
    FROM gold.BRIDGE_PARTY_NATIONALITY T
    LEFT JOIN #goldnationalityIDstoDelete S
        ON T.SK_PARTY_NATIONALITY = S.SK_PARTY_NATIONALITY
    LEFT JOIN #golddetailIDstoDelete D
        ON T.SK_PARTY_DETAIL = D.SK_PARTY_DETAIL
    WHERE S.SK_PARTY_NATIONALITY IS NULL
       OR D.SK_PARTY_DETAIL IS NULL;
    DELETE FROM gold.BRIDGE_PARTY_NATIONALITY
    WHERE SK_BRIDGE_PARTY_NATIONALITY IN (SELECT ID FROM #IDsToDelete);
    SET @deleted = @@ROWCOUNT;
    ---------------------------------------------------------
    -- Audit Log
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
        'SK_BRIDGE_PARTY_NATIONALITY',
        ID,
        'DELETE',
        'DIM_PARTY_NATIONALITY, DIM_PARTY_DETAIL',
        'gold.BRIDGE_PARTY_NATIONALITY',
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
        'DIM_PARTY_NATIONALITY, DIM_PARTY_DETAIL',
        'gold.BRIDGE_PARTY_NATIONALITY',
        SYSUTCDATETIME(),
        COALESCE(@source_count, 0),
        COALESCE(@insert_new, 0),
        COALESCE(@updated, 0),
        COALESCE(@deleted, 0);
    ---------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #IDsToDelete;
    DROP TABLE IF EXISTS #SRC_BRIDGE_PARTY_NATIONALITY;
    DROP TABLE IF EXISTS #goldnationalityIDstoDelete;
    DROP TABLE IF EXISTS #golddetailIDstoDelete;
    DROP TABLE IF EXISTS #DeletedKeys_nationality;
    DROP TABLE IF EXISTS #DeletedKeys_Detail;
 
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
 
        DROP TABLE IF EXISTS #IDsToDelete;
        DROP TABLE IF EXISTS #SRC_BRIDGE_PARTY_NATIONALITY;
        DROP TABLE IF EXISTS #goldnationalityIDstoDelete;
        DROP TABLE IF EXISTS #golddetailIDstoDelete;
        DROP TABLE IF EXISTS #DeletedKeys_nationality;
        DROP TABLE IF EXISTS #DeletedKeys_Detail;
 
        THROW;
    END CATCH
END;