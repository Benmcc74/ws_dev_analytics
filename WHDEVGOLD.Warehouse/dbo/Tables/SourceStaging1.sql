CREATE TABLE [dbo].[SourceStaging1] (

	[PARTY_MDM_ID] varchar(160) NOT NULL, 
	[PARTY_TYPE] varchar(1) NOT NULL, 
	[STATUS] varchar(1) NOT NULL, 
	[FIRST_NAMES] varchar(280) NULL, 
	[LAST_NAME] varchar(280) NULL, 
	[TITLE] varchar(28) NULL, 
	[SUFFIX] varchar(120) NULL, 
	[GENDER] varchar(4) NOT NULL, 
	[DOB] date NULL, 
	[MARITAL_STATUS] varchar(24) NOT NULL, 
	[NI_NUMBER] varchar(36) NULL, 
	[TAX_ID_NUMBER] varchar(120) NULL, 
	[TAX_DOMICILE] varchar(24) NULL, 
	[FATCA_ELIGIBLE] varchar(1) NOT NULL, 
	[RELATIONSHIP_START_DATE] datetime2(6) NULL, 
	[RELATIONSHIP_END_DATE] datetime2(6) NULL, 
	[RETENTION_END_DATE] varchar(1) NOT NULL, 
	[DECEASED_DATE] date NULL, 
	[DECEASED_NOTIFICATION_DATE] date NULL, 
	[DECEASED_EVIDENCE_DATE] date NULL, 
	[HASH_VALUE] varbinary(8000) NULL
);