﻿CREATE VIEW [dbo].[vw_sqlwatch_report_dim_index] with schemabinding
	AS 
select [sql_instance], [sqlwatch_database_id], [sqlwatch_table_id], [sqlwatch_index_id], [index_name], [index_id], [index_type_desc], [date_added], [date_updated], [date_deleted]
from dbo.sqlwatch_meta_index
