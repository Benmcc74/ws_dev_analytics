# Fabric notebook source

# METADATA ********************

# META {
# META   "kernel_info": {
# META     "name": "synapse_pyspark"
# META   },
# META   "dependencies": {}
# META }

# CELL ********************

# MAGIC %%sql
# MAGIC 
# MAGIC ALTER TABLE [WHDEVGOLD].[gold].[BRIDGE_PARTY_NATIONALITY]  ADD  CONSTRAINT [BPARNT_DPARDT_FK] FOREIGN KEY([SK_PARTY_DETAIL]) REFERENCES [WHDEVGOLD].[gold].[DIM_PARTY_DETAIL] ([SK_PARTY_DETAIL])


# METADATA ********************

# META {
# META   "language": "sparksql",
# META   "language_group": "synapse_pyspark"
# META }
