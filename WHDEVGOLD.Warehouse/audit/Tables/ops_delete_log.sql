CREATE TABLE [audit].[ops_delete_log] (

	[ATTRIBUTE_NAME] varchar(50) NULL, 
	[ATTRIBUTE_VALUE] varchar(50) NULL, 
	[EVENT_TYPE] varchar(50) NULL, 
	[SOURCE_TABLE] varchar(100) NULL, 
	[TARGET_TABLE] varchar(100) NULL, 
	[DELETED_DATE] datetime2(6) NULL, 
	[BATCH_ID] varchar(50) NULL
);