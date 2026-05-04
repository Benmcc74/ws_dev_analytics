-- Auto Generated (Do not modify) 9AA810E90B9665AA9CFB7BBFAB4DDA92B861B644A1D6100555004725B8195EE4
CREATE                                         VIEW [gold].[VW_PARTY_DETAIL]
AS SELECT 

t.*,
CASE 
WHEN AGE_BAND = 'Unknown' THEN 7 --'07'
	  when AGE_BAND = '<20' THEN 1 --'01'
	  WHEN AGE_BAND ='20-29' THEN 2 --'02'
	  WHEN AGE_BAND = '30-39' THEN 3 --'03'
	  WHEN AGE_BAND = '40-49' THEN 4 --'04'
	  WHEN AGE_BAND = '50-59' THEN 5 -- '05'
	  ELSE 6 --'06'
	END AS AGE_GROUP_SORT,

CASE
WHEN CUSTOMER_TENURE_BAND = 'Unknown'
	THEN 5 --'05'
 	WHEN CUSTOMER_TENURE_BAND = '0-5 Years'
	THEN 1 --'01'
	WHEN CUSTOMER_TENURE_BAND = '5-10 Years'
	THEN 2 --'02'
	WHEN CUSTOMER_TENURE_BAND = '10-20 Years'
	THEN 3 --'03'
	ELSE 4 --'04'
	END AS TENURE_SORT
    FROM( 
    SELECT

CAST( SK_PARTY_DETAIL AS VARCHAR(36)) AS SK_PARTY_DETAIL, PARTY_MDM_ID,
 CASE 
 	WHEN GENDER IS NULL OR LTRIM(RTRIM(GENDER)) = '' THEN 'Unknown'
	WHEN GENDER = 'F' THEN 'Female'
	WHEN GENDER = 'M' THEN 'Male'
	 ELSE GENDER END AS GENDER,  
 PARTY_TYPE,
 DOB,

 CASE
        WHEN DOB IS NULL THEN 'Unknown'
        ELSE
            CASE
                WHEN
                    (
                        DATEDIFF(YEAR, DOB, GETDATE())
                        - CASE
                              WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                              THEN 1
                              ELSE 0
                          END
                    ) < 20
                THEN '<20'
 
                WHEN
                    (
                        DATEDIFF(YEAR, DOB, GETDATE())
                        - CASE
                              WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                              THEN 1
                              ELSE 0
                          END
                    ) BETWEEN 20 AND 29
                THEN '20-29'
 
                WHEN
                    (
                        DATEDIFF(YEAR, DOB, GETDATE())
                        - CASE
                              WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                              THEN 1
                              ELSE 0
                          END
                    ) BETWEEN 30 AND 39
                THEN '30-39'
 
                WHEN
                    (
                        DATEDIFF(YEAR, DOB, GETDATE())
                        - CASE
                              WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                              THEN 1
                              ELSE 0
                          END
                    ) BETWEEN 40 AND 49
                THEN '40-49'
 
                WHEN
                    (
                        DATEDIFF(YEAR, DOB, GETDATE())
                        - CASE
                              WHEN DATEADD(YEAR, DATEDIFF(YEAR, DOB, GETDATE()), DOB) > GETDATE()
                              THEN 1
                              ELSE 0
                          END
                    ) BETWEEN 50 AND 59
                THEN '50-59'
 
                ELSE '60+'
            END
    END AS AGE_BAND,



  CAST([RELATIONSHIP_START_DATE] AS DATE) AS [RELATIONSHIP_START_DATE],
FORMAT(RELATIONSHIP_START_DATE,'yyyy') AS RELATIONSHIP_START_YEAR,
CASE
    WHEN RELATIONSHIP_START_DATE IS NULL THEN 'Unknown'
    ELSE
        CASE 
            WHEN 
                (
                    DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()) 
                    - CASE 
                          WHEN DATEADD(YEAR, DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()), RELATIONSHIP_START_DATE) > GETDATE()
                          THEN 1 
                          ELSE 0 
                      END
                ) < 5
            THEN '0-5 Years'

            WHEN 
                (
                    DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()) 
                    - CASE 
                          WHEN DATEADD(YEAR, DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()), RELATIONSHIP_START_DATE) > GETDATE()
                          THEN 1 
                          ELSE 0 
                      END
                ) < 10
            THEN '5-10 Years'

            WHEN 
                (
                    DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()) 
                    - CASE 
                          WHEN DATEADD(YEAR, DATEDIFF(YEAR, RELATIONSHIP_START_DATE, GETDATE()), RELATIONSHIP_START_DATE) > GETDATE()
                          THEN 1 
                          ELSE 0 
                      END
                ) < 20
            THEN '10-20 Years'

            ELSE '20+ Years'
        END
END AS CUSTOMER_TENURE_BAND
FROM [gold].[DIM_PARTY_DETAIL] WHERE (RELATIONSHIP_END_DATE IS NULL OR RELATIONSHIP_END_DATE > GETDATE() ) AND END_DATE IS NULL ) t