CREATE TABLE [audit].[ops_record_count_log] (

	[BATCH_ID] varchar(400) NULL, 
	[SOURCE_TABLE] varchar(400) NULL, 
	[TARGET_TABLE] varchar(400) NULL, 
	[CREATED_DATE] datetime2(6) NULL, 
	[SOURCE_RECORDS] bigint NULL, 
	[INSERT_RECORDS] bigint NULL, 
	[UPDATE_RECORDS] bigint NULL, 
	[DELETE_RECORDS] bigint NULL
);