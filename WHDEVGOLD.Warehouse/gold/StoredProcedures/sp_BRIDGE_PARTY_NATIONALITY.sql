CREATE                                             PROCEDURE [gold].[sp_BRIDGE_PARTY_NATIONALITY]
(
  @batch_id NVARCHAR(100)
)
AS
BEGIN

   DECLARE @CURRENT_TS DATETIME = GETDATE();
   
   
    SET NOCOUNT ON;

    DECLARE @insert_new    int = 0;
    DECLARE @insert_changed int = 0;
    DECLARE @updated int = 0;
    DECLARE @deleted int = 0;
    DECLARE @source_count int = 0;



   /*========================================================
     1. Prepare source snapshot
   ========================================================*/
   DROP TABLE IF EXISTS #SRC_BRIDGE_PARTY_NATIONALITY;
   SELECT
       DPN.PARTY_MDM_ID,
       -- FK lookups
       DPN.SK_PARTY_NATIONALITY,
       DPD.SK_PARTY_DETAIL,
       -- Dates
       CASE
           WHEN DPN.START_DATE >= DPD.START_DATE THEN DPN.START_DATE
           ELSE DPD.START_DATE
       END AS START_DATE,
       NULL AS END_DATE,
       -- Hash for change detection
       CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
           CONCAT_WS('|',
               DPN.SK_PARTY_NATIONALITY,
               DPD.SK_PARTY_DETAIL
           )
       ), 2) AS HASH_VALUE
   INTO #SRC_BRIDGE_PARTY_NATIONALITY
   FROM [gold].[DIM_PARTY_NATIONALITY] DPN
   INNER JOIN [gold].[DIM_PARTY_DETAIL] DPD
       ON DPN.PARTY_MDM_ID = DPD.PARTY_MDM_ID
   WHERE
       DPN.END_DATE IS NULL
       AND DPD.END_DATE IS NULL
       AND DPN.DELETED_FLAG = 'N'
       AND DPD.DELETED_FLAG = 'N';

       SET @source_count = @@ROWCOUNT;
   /*========================================================
     2. Expire changed BRIDGE_PARTY_NATIONALITY records (SCD2)
   ========================================================*/
   UPDATE TGT
   SET
       TGT.END_DATE   = DATEADD(ms, -3, @CURRENT_TS)

   FROM [gold].[BRIDGE_PARTY_NATIONALITY] TGT
   LEFT JOIN #SRC_BRIDGE_PARTY_NATIONALITY SRC
       ON TGT.SK_PARTY_NATIONALITY = SRC.SK_PARTY_NATIONALITY
       AND TGT.SK_PARTY_DETAIL     = SRC.SK_PARTY_DETAIL
   WHERE
       TGT.END_DATE IS NULL
       AND TGT.DELETED_FLAG = 'N'
       AND SRC.SK_PARTY_NATIONALITY IS NULL;
       SET @updated = @@ROWCOUNT;
   /*========================================================
     3. Insert new  records
   ========================================================*/
   INSERT INTO [gold].[BRIDGE_PARTY_NATIONALITY]
   (
       SK_BRIDGE_PARTY_NATIONALITY,
	   SK_PARTY_NATIONALITY,
       SK_PARTY_DETAIL,
       START_DATE,
       END_DATE,
       HASH_VALUE,
       DELETED_FLAG,
       BATCH_ID
   )
   SELECT
	NEWID() AS SK_BRIDGE_PARTY_NATIONALITY,
	SRC.SK_PARTY_NATIONALITY,
       SRC.SK_PARTY_DETAIL,
       SRC.START_DATE,
       NULL AS END_DATE,
       SRC.HASH_VALUE,
       'N' AS DELETED_FLAG,
       @batch_id
   FROM #SRC_BRIDGE_PARTY_NATIONALITY SRC
   LEFT JOIN [gold].[BRIDGE_PARTY_NATIONALITY] TGT
       ON TGT.SK_PARTY_NATIONALITY = SRC.SK_PARTY_NATIONALITY
       AND TGT.SK_PARTY_DETAIL     = SRC.SK_PARTY_DETAIL
         AND       TGT.END_DATE IS NULL
       AND TGT.DELETED_FLAG = 'N'
   WHERE
       TGT.SK_BRIDGE_PARTY_NATIONALITY IS NULL
       ;


    SET @insert_new = @@ROWCOUNT;

  

    ---------------------------------------------------------
    -- Soft Delete
    ---------------------------------------------------------

DROP TABLE IF EXISTS #DeletedKeys_nationality;
 
    SELECT SK_PARTY_NATIONALITY
    INTO #DeletedKeys_nationality
    FROM gold.DIM_PARTY_NATIONALITY
    WHERE DELETED_FLAG = 'Y' 

DROP TABLE IF EXISTS #DeletedKeys_Detail;

    SELECT SK_PARTY_DETAIL
    INTO #DeletedKeys_Detail
    FROM gold.DIM_PARTY_DETAIL
    WHERE DELETED_FLAG = 'Y'

UPDATE T
SET
    T.DELETED_FLAG = 'Y',
    T.END_DATE = DATEADD(ms, -3, @CURRENT_TS)
FROM gold.BRIDGE_PARTY_NATIONALITY T
LEFT JOIN #DeletedKeys_nationality C
    ON T.SK_PARTY_NATIONALITY = C.SK_PARTY_NATIONALITY
LEFT JOIN #DeletedKeys_Detail N
    ON T.SK_PARTY_DETAIL = N.SK_PARTY_DETAIL
WHERE
T.DELETED_FLAG = 'N'
    AND (
           C.SK_PARTY_NATIONALITY IS NOT NULL OR N.SK_PARTY_DETAIL IS NOT NULL
        );
SET @updated = @updated + @@ROWCOUNT;
    ---------------------------------------------------------
    --  Hard Delete
    ---------------------------------------------------------

    -- 1. Capture rows to delete


     DROP TABLE IF EXISTS #goldnationalityIDstoDelete;
     DROP TABLE IF EXISTS #golddetailIDstoDelete;

 
    SELECT DISTINCT SK_PARTY_NATIONALITY
    INTO #goldnationalityIDstoDelete
    FROM gold.DIM_PARTY_NATIONALITY

    ;

        SELECT DISTINCT SK_PARTY_DETAIL
    INTO #golddetailIDstoDelete
    FROM gold.DIM_PARTY_DETAIL
    ;

     DROP TABLE IF EXISTS  #IDsToDelete;
    SELECT 
        T.SK_BRIDGE_PARTY_NATIONALITY AS ID,
        T.SK_PARTY_NATIONALITY,
        T.SK_PARTY_DETAIL
    INTO #IDsToDelete
    FROM gold.BRIDGE_PARTY_NATIONALITY AS T
   LEFT JOIN #goldnationalityIDstoDelete AS S
        ON  T.SK_PARTY_NATIONALITY   = S.SK_PARTY_NATIONALITY
    LEFT JOIN #golddetailIDstoDelete D
       ON T.SK_PARTY_DETAIL = D.SK_PARTY_DETAIL
    WHERE 
      (S.SK_PARTY_NATIONALITY IS NULL
             OR D.SK_PARTY_DETAIL IS NULL
            );

    SET @deleted = @@ROWCOUNT;
    ---------------------------------------------------------
    -- 2. Delete from target table
    ---------------------------------------------------------
    DELETE FROM gold.BRIDGE_PARTY_NATIONALITY
    WHERE SK_BRIDGE_PARTY_NATIONALITY IN (SELECT ID FROM #IDsToDelete);


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
        'SK_BRIDGE_PARTY_NATIONALITY' AS ATTRIBUTE_NAME,
        ID AS ATTRIBUTE_VALUE,
        'DELETE' AS EVENT_TYPE,
        'DIM_PARTY_NATIONALITY, DIM_PARTY_DETAIL' AS SOURCE_TABLE,
        'gold.BRIDGE_PARTY_NATIONALITY' AS TARGET_TABLE,
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
        'DIM_PARTY_NATIONALITY, DIM_PARTY_DETAIL' AS SOURCE_TABLE,
        'gold.BRIDGE_PARTY_NATIONALITY'          AS TARGET_TABLE,
        SYSUTCDATETIME()                         AS CREATED_DATE,
        COALESCE(@source_count,   0) AS SOURCE_RECORDS,
        COALESCE(@insert_new,     0) AS INSERT_RECORDS,
        COALESCE(@updated, 0) AS UPDATE_RECORDS,
        COALESCE(@deleted,        0) AS DELETE_RECORDS;


        
        
 

    ---------------------------------------------------------
    -- 4. Cleanup
    ---------------------------------------------------------
    DROP TABLE IF EXISTS #IDsToDelete;
    DROP TABLE IF EXISTS #SRC_BRIDGE_PARTY_NATIONALITY;
    DROP TABLE IF EXISTS #goldnationalityIDstoDelete;
    DROP TABLE IF EXISTS #golddetailIDstoDelete;
    DROP TABLE IF EXISTS #DeletedKeys_nationality;
    DROP TABLE IF EXISTS #DeletedKeys_Detail;

END;


EXEC [gold].[sp_BRIDGE_PARTY_NATIONALITY] @batch_id = 'test'