CREATE TABLE [gold].[Sample_DIM_PARTY_NATIONALITY] (

	[SK_CUSTOMER_NATIONALITY] uniqueidentifier NOT NULL, 
	[PARTY_MDM_ID] varchar(40) NOT NULL, 
	[NATIONALITY] varchar(70) NULL, 
	[FIRST_DECL_NTNLTY_FLAG] varchar(1) NULL, 
	[START_DATE] datetime2(3) NOT NULL, 
	[END_DATE] datetime2(3) NULL, 
	[HASH_VALUE] varchar(256) NULL, 
	[DELETED_FLAG] varchar(1) NULL, 
	[BATCH_ID] varchar(256) NOT NULL
);