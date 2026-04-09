CREATE                                 PROCEDURE [gold].[sp_PARTY_DEMOGRAPHICS_FACTLESS]
(
    @batch_id NVARCHAR(100)
)
AS
BEGIN

 
    DECLARE @CURRENT_TS DATETIME = SYSDATETIME();
    DECLARE @TODAY DATE = CAST(@CURRENT_TS AS DATE);

    DECLARE @insert_new    int = 0;
    DECLARE @insert_changed int = 0;
    DECLARE @deleted int = 0;
    DECLARE @source_count int = 0;
    DECLARE @updated int = 0;
 
    /*========================================================
      1. Resolve Date Surrogate Keys
    ========================================================*/

    DECLARE @START_DATE_SK INT;
    SELECT @START_DATE_SK = SK_DATE
    FROM [gold].[DIM_DATE]
    WHERE CALENDAR_DATE = @TODAY;
 
    /*========================================================
      2. Build Source Snapshot
    ========================================================*/
    DROP TABLE IF EXISTS #SRC_PARTY_DEMO;
 
    SELECT
        PD.SK_PARTY_DETAIL,
        PC.SK_PARTY_CONTACT,
        PF.SK_PARTY_FLAG,
 
        @START_DATE_SK AS SK_START_DATE,
        NULL AS SK_END_DATE, 
        CAST(@CURRENT_TS AS DATE) AS LOAD_DATE,
        CAST(@CURRENT_TS AS DATETIME2(6)) AS LOAD_TIME,
 
        CONVERT(VARCHAR(64), HASHBYTES('SHA2_256',
            CONCAT_WS('|',
                PD.SK_PARTY_DETAIL,
                PC.SK_PARTY_CONTACT,
                PF.SK_PARTY_FLAG
            )
        ), 2) AS HASH_VALUE
 
    INTO #SRC_PARTY_DEMO
    FROM [gold].[DIM_PARTY_DETAIL] PD
    INNER JOIN [gold].[DIM_PARTY_CONTACT] PC
        ON PD.PARTY_MDM_ID = PC.PARTY_MDM_ID
    INNER JOIN [gold].[DIM_PARTY_FLAG] PF
        ON PD.PARTY_MDM_ID = PF.PARTY_MDM_ID
    WHERE
        PD.END_DATE IS NULL
       AND PC.END_DATE IS NULL
        AND PF.END_DATE IS NULL
        AND PD.DELETED_FLAG = 'N'
        AND PC.DELETED_FLAG = 'N'
        AND PF.DELETED_FLAG = 'N';
    
    SET @source_count = @@ROWCOUNT;
    /*========================================================
      3. Expire Changed Records (SCD2)
    ========================================================*/
    UPDATE TGT
    SET
        TGT.SK_END_DATE = @START_DATE_SK
    FROM [gold].[PARTY_DEMOGRAPHICS_FACTLESS] TGT
    LEFT JOIN #SRC_PARTY_DEMO SRC
        ON TGT.SK_PARTY_DETAIL  = SRC.SK_PARTY_DETAIL
        AND TGT.SK_PARTY_CONTACT = SRC.SK_PARTY_CONTACT
        AND TGT.SK_PARTY_FLAG   = SRC.SK_PARTY_FLAG
    WHERE
        SRC.SK_PARTY_DETAIL IS NULL AND
        TGT.SK_END_DATE IS NULL
        AND TGT.DELETED_FLAG = 'N';

    SET @updated = @@ROWCOUNT;
    /*========================================================
      4. Insert New & Changed Records
    ========================================================*/
    INSERT INTO [gold].[PARTY_DEMOGRAPHICS_FACTLESS]
    (
        SK_PARTY_DEMO_FACTLESS,
        SK_PARTY_DETAIL,
        SK_PARTY_CONTACT,
        SK_PARTY_FLAG,
        SK_START_DATE,
        SK_END_DATE,
        LOAD_DATE,
        LOAD_TIME,
        HASH_VALUE,
        DELETED_FLAG,
        BATCH_ID
    )
    SELECT
    NEWID(),
        SRC.SK_PARTY_DETAIL,
        SRC.SK_PARTY_CONTACT,
        SRC.SK_PARTY_FLAG,
        SRC.SK_START_DATE,
        SRC.SK_END_DATE,
        SRC.LOAD_DATE,
        SRC.LOAD_TIME,
        SRC.HASH_VALUE,
        'N' AS DELETED_FLAG,
        @batch_id
    FROM #SRC_PARTY_DEMO SRC
    LEFT JOIN [gold].[PARTY_DEMOGRAPHICS_FACTLESS] TGT
        ON TGT.SK_PARTY_DETAIL   = SRC.SK_PARTY_DETAIL
        AND TGT.SK_PARTY_CONTACT = SRC.SK_PARTY_CONTACT
        AND TGT.SK_PARTY_FLAG    = SRC.SK_PARTY_FLAG
        AND TGT.SK_END_DATE      IS NULL
        AND TGT.DELETED_FLAG     = 'N'
    WHERE
        TGT.SK_PARTY_DEMO_FACTLESS IS NULL
    AND NOT EXISTS (
        SELECT 1
        FROM [gold].[PARTY_DEMOGRAPHICS_FACTLESS] T2
        WHERE T2.SK_PARTY_DETAIL   = SRC.SK_PARTY_DETAIL
          AND T2.SK_PARTY_CONTACT = SRC.SK_PARTY_CONTACT
          AND T2.SK_PARTY_FLAG    = SRC.SK_PARTY_FLAG
          AND T2.HASH_VALUE        = SRC.HASH_VALUE
          AND T2.SK_END_DATE IS NULL
    );

   
    SET @insert_new = @@ROWCOUNT;
---------Deletions logic----------------------------------

    -- Soft Delete


DROP TABLE IF EXISTS #DeletedKeys_contact;
 
    SELECT SK_PARTY_CONTACT
    INTO #DeletedKeys_contact
    FROM gold.DIM_PARTY_CONTACT
    WHERE DELETED_FLAG = 'Y'

DROP TABLE IF EXISTS #DeletedKeys_Detail;

    SELECT SK_PARTY_DETAIL
    INTO #DeletedKeys_Detail
    FROM gold.DIM_PARTY_DETAIL
    WHERE DELETED_FLAG = 'Y'

DROP TABLE IF EXISTS #DeletedKeys_Flag;

    SELECT SK_PARTY_FLAG
    INTO #DeletedKeys_Flag
    FROM gold.DIM_PARTY_FLAG
    WHERE DELETED_FLAG = 'Y'


UPDATE T
SET
    T.DELETED_FLAG = 'Y',
    T.SK_END_DATE = @START_DATE_SK
FROM gold.PARTY_DEMOGRAPHICS_FACTLESS T
LEFT JOIN #DeletedKeys_contact C
    ON T.SK_PARTY_CONTACT = C.SK_PARTY_CONTACT
LEFT JOIN #DeletedKeys_Detail N
    ON T.SK_PARTY_DETAIL = N.SK_PARTY_DETAIL
LEFT JOIN #DeletedKeys_Flag F
    ON T.SK_PARTY_FLAG = F.SK_PARTY_FLAG
WHERE
    T.DELETED_FLAG = 'N'
    AND (
           N.SK_PARTY_DETAIL IS NOT NULL OR C.SK_PARTY_CONTACT IS NOT NULL OR F.SK_PARTY_FLAG IS NOT NULL)

SET @updated = @updated + @@ROWCOUNT;
 ---------------------------------------------------------
-- Hard delete
---------------------------------------------------------

-- 1. Capture rows to delete

     DROP TABLE IF EXISTS #goldcontactIDstoDelete;
     DROP TABLE IF EXISTS #golddetailIDstoDeletefact;
     DROP TABLE IF EXISTS #goldflagIDstoDelete;

 
    SELECT DISTINCT SK_PARTY_CONTACT
    INTO #goldcontactIDstoDelete
    FROM gold.DIM_PARTY_CONTACT

    ;

        SELECT DISTINCT SK_PARTY_DETAIL
    INTO #golddetailIDstoDeletefact
    FROM gold.DIM_PARTY_DETAIL
    ;

            SELECT DISTINCT SK_PARTY_FLAG
    INTO #goldflagIDstoDelete
    FROM gold.DIM_PARTY_FLAG
    ;

     DROP TABLE IF EXISTS  #IDsToDelete;
    SELECT 
      T.SK_PARTY_DEMO_FACTLESS AS ID,
      T.SK_PARTY_DETAIL,
      T.SK_PARTY_CONTACT,
      T.SK_PARTY_FLAG
    INTO #IDsToDelete
    FROM gold.PARTY_DEMOGRAPHICS_FACTLESS AS T
   LEFT JOIN #goldcontactIDstoDelete AS S
        ON  T.SK_PARTY_CONTACT   = S.SK_PARTY_CONTACT
    LEFT JOIN #golddetailIDstoDeletefact D
       ON T.SK_PARTY_DETAIL = D.SK_PARTY_DETAIL
        LEFT JOIN #goldflagIDstoDelete F
       ON T.SK_PARTY_FLAG = F.SK_PARTY_FLAG
    WHERE 
      (D.SK_PARTY_DETAIL IS NULL
         OR S.SK_PARTY_CONTACT IS NULL
         OR F.SK_PARTY_FLAG IS NULL
            ); 
SET @deleted = @@ROWCOUNT;
---------------------------------------------------------
-- 2. Delete from target table
---------------------------------------------------------
DELETE FROM gold.PARTY_DEMOGRAPHICS_FACTLESS
WHERE SK_PARTY_DEMO_FACTLESS IN (SELECT ID FROM #IDsToDelete);


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
    'SK_PARTY_DEMO_FACTLESS' AS ATTRIBUTE_NAME,
    ID AS ATTRIBUTE_VALUE,
    'DELETE' AS EVENT_TYPE,
    'gold.DIM_PARTY_DETAIL, DIM_PARTY_FLAG,gold.DIM_PARTY_CONTACT' AS SOURCE_TABLE,
    'gold.PARTY_DEMOGRAPHICS_FACTLESS' AS TARGET_TABLE,
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
        'gold.DIM_PARTY_DETAIL, DIM_PARTY_FLAG,gold.DIM_PARTY_CONTACT' AS SOURCE_TABLE,
    'gold.PARTY_DEMOGRAPHICS_FACTLESS' AS TARGET_TABLE,
        SYSUTCDATETIME()                         AS EVENT_DATE,
        COALESCE(@source_count,   0) AS SOURCE_RECORDS,
        COALESCE(@insert_changed,     0) AS INSERT_RECORDS,
        COALESCE(@updated, 0) AS UPDATE_RECORDS,
        COALESCE(@deleted,        0) AS DELETE_RECORDS;
---------------------------------------------------------
-- 4. Cleanup
---------------------------------------------------------
DROP TABLE IF EXISTS #IDsToDelete;
DROP TABLE IF EXISTS #SRC_PARTY_DEMO;
DROP TABLE IF EXISTS #goldcontactIDstoDelete;
DROP TABLE IF EXISTS #golddetailIDstoDeletefact;
DROP TABLE IF EXISTS #goldflagIDstoDelete;
DROP TABLE IF EXISTS #DeletedKeys_Flag; 
DROP TABLE IF EXISTS #DeletedKeys_Detail;
DROP TABLE IF EXISTS #DeletedKeys_contact;
 
END;