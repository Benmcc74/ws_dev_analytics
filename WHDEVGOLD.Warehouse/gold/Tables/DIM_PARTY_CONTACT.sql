CREATE TABLE [gold].[DIM_PARTY_CONTACT] (

	[SK_PARTY_CONTACT] uniqueidentifier NOT NULL, 
	[PARTY_MDM_ID] varchar(40) NOT NULL, 
	[LINE_1] varchar(35) NOT NULL, 
	[LINE_2] varchar(35) NULL, 
	[LINE_3] varchar(35) NULL, 
	[LINE_4] varchar(35) NULL, 
	[LINE_5] varchar(35) NULL, 
	[POSTCODE] varchar(7) NULL, 
	[COUNTRY] varchar(100) NULL, 
	[ADDRESS_TYPE] varchar(100) NULL, 
	[EMAIL] varchar(70) NULL, 
	[MOBILE_PHONE] varchar(50) NULL, 
	[HOME_PHONE] varchar(50) NULL, 
	[WORK_PHONE] varchar(50) NULL, 
	[PREF_COMM_METHOD] varchar(6) NULL, 
	[SOURCE_EDIT_DATE_WORK_PHONE] datetime2(3) NULL, 
	[SOURCE_EDIT_DATE_MOBILE_PHONE] datetime2(3) NULL, 
	[SOURCE_EDIT_DATE_HOME_PHONE] datetime2(3) NULL, 
	[SOURCE_EDIT_DATE_EMAIL] datetime2(3) NULL, 
	[SOURCE_EDIT_DATE_ADDRESS] datetime2(3) NULL, 
	[START_DATE] datetime2(3) NOT NULL, 
	[END_DATE] datetime2(3) NULL, 
	[HASH_VALUE] varchar(256) NULL, 
	[DELETED_FLAG] varchar(1) NULL, 
	[BATCH_ID] varchar(256) NOT NULL, 
	[LOAD_DATE] datetime2(3) NOT NULL
);


GO
ALTER TABLE [gold].[DIM_PARTY_CONTACT] ADD CONSTRAINT DCUSCT_PK primary key NONCLUSTERED ([SK_PARTY_CONTACT]);