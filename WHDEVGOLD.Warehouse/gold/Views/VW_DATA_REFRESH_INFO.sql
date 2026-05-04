-- Auto Generated (Do not modify) 216D2D289AEEA29EA739E2ABA60398E8B47DD0829B609D4C3712891F8461040D
CREATE                   VIEW [gold].[VW_DATA_REFRESH_INFO]


AS SELECT MAX(CREATED_DATE) as data_as_of from [audit].[ops_record_count_log]